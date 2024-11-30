// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "./XpswapFactory.sol";
import "./XpswapERC20.sol";
import "../lib/Math.sol";
import "../lib/UQ112x112.sol";

import "forge-std/console.sol";

contract XpswapPool is XpswapERC20 {
    address factory;
    using UQ112x112 for uint224;

    IERC20 public tokenA;
    IERC20 public tokenB;

    uint112 public reserveA;
    uint112 public reserveB;

    uint private lastK;
    uint8 private txFees = 3;
    bool private mutex = false;

    uint32 blockTimestampLast;
    uint priceACumulativeLast;
    uint priceBCumulativeLast;

    constructor() {
        factory = msg.sender;
    }

    modifier reentrancyGuard() {
        require(mutex == false, "Pool: Reentrance forbidden");
        mutex = true;
        _;
        mutex = false;
    }

    function initialize(address tokenA_, address tokenB_) public {
        require(msg.sender == factory, "Pool: Only factory");
        tokenA = IERC20(tokenA_);
        tokenB = IERC20(tokenB_);
    }

    function _mintFee(address feeTo) private reentrancyGuard {
        uint rootCurrK = Math.sqrt(reserveA * reserveB);
        uint rootLastK = Math.sqrt(lastK);

        if (rootCurrK > rootLastK) {
            uint numerator = (rootCurrK - rootLastK) * totalSupply;
            uint denominator = rootCurrK * 5 + rootLastK;
            uint feeOut = numerator / denominator;
            if (feeOut > 0) _mint(feeTo, feeOut);
        }
    }

    function addLiquidity(uint amountA, uint amountB) public reentrancyGuard {
        require(amountA > 0, "Pool: Invalid amount for token A");
        require(amountB > 0, "Pool: Invalid amount for token B");

        _safeTransferFrom(tokenA, msg.sender, address(this), amountA);
        _safeTransferFrom(tokenB, msg.sender, address(this), amountB);
        
        address feeTo = XpswapFactory(factory).feeTo();
        uint liquidityIn = 0;
        uint liquidity = totalSupply;
        uint effectiveAmountA = amountA;
        uint effectiveAmountB = amountB;
        
        if (liquidity == 0) {
            uint liquidityMinimum = 1000;
            liquidityIn = Math.sqrt(amountA * amountB) - liquidityMinimum;
            _mint(address(0), liquidityMinimum);
        }
        else {
            if (feeTo != address(0))
                _mintFee(feeTo);
            liquidity = totalSupply;
            uint ratioA = amountA * liquidity / reserveA;
            uint ratioB = amountB * liquidity / reserveB;
            liquidityIn = Math.min(ratioA, ratioB);
            if (ratioB < ratioA) {
                effectiveAmountA = amountB * reserveA / reserveB;
                _safeTransfer(tokenA, msg.sender, amountA - effectiveAmountA);
            } else {
                effectiveAmountB = amountA * reserveB / reserveA;
                _safeTransfer(tokenB, msg.sender, amountB - effectiveAmountB);
            }
        }
        
        _reserveUpdate();
        
        lastK = reserveA * reserveB;

        _mint(msg.sender, liquidityIn);
    }

    function _reserveUpdate() private {
        uint balanceA = IERC20(tokenA).balanceOf(address(this));
        uint balanceB = IERC20(tokenB).balanceOf(address(this));

        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = uint32((blockTimestamp - blockTimestampLast) % 2**32);
        
        if (timeElapsed > 0 && reserveA != 0 && reserveB != 0) {
            priceACumulativeLast += uint(UQ112x112.encode(reserveB).uqdiv(reserveA)) * timeElapsed;
            priceBCumulativeLast += uint(UQ112x112.encode(reserveA).uqdiv(reserveB)) * timeElapsed;
        }

        reserveA = uint112(balanceA);
        reserveB = uint112(balanceB);
        blockTimestampLast = blockTimestamp;
    }

    function removeLiquidity(uint liquidityOut) public reentrancyGuard {
        uint liquidity = totalSupply;
        lastK = reserveA * reserveB;

        require(liquidityOut > 0, "Pool: Invalid amount for token LP");
        require(balanceOf[msg.sender] >= liquidityOut, "Pool: Insufficient LP balance");
        require(liquidityOut <= liquidity, "Pool: Invalid liquidity amount");

        uint amountA = (reserveA * liquidityOut) / liquidity;
        uint amountB = (reserveB * liquidityOut) / liquidity;

        require(amountA < reserveA, "Pool: Insufficient liquidity in pool");
        require(amountB < reserveB, "Pool: Insufficient liquidity in pool");

        _burn(msg.sender, liquidityOut);
        _safeTransfer(tokenA, msg.sender, amountA);
        _safeTransfer(tokenB, msg.sender, amountB);

        _reserveUpdate();
    }

    function swapWithOutput(uint256 outputAmount, address outputToken) public reentrancyGuard {
        require(outputToken == address(tokenA) || outputToken == address(tokenB), "Pool: Invalid token address");
        require(outputAmount > 0, "Pool: Invalid output amount");
        
        lastK = reserveA * reserveB;
        (IERC20 tokenOut, IERC20 tokenIn, uint256 reserveOut, uint256 reserveIn) = 
            outputToken == address(tokenA)
            ? (tokenA, tokenB, reserveA, reserveB)
            : (tokenB, tokenA, reserveB, reserveA);
        
        require(outputAmount < reserveOut, "Pool: Insufficient liquidity in pool");

        uint numerator = outputAmount * reserveIn * 1000;
        uint denominator = (reserveOut - outputAmount) * (1000 - txFees);
        uint inputAmount = numerator / denominator;
    
        _safeTransferFrom(tokenIn, msg.sender, address(this), inputAmount);
        _safeTransfer(tokenOut, msg.sender, outputAmount);

        _reserveUpdate();
    }

    function swapWithInput(uint256 inputAmount, uint256 minOutputAmount, address inputToken) public reentrancyGuard {
        require(inputToken == address(tokenA) || inputToken == address(tokenB), "Pool: Invalid token address");
        require(inputAmount > 0, "Pool: Invalid input amount");
        
        lastK = reserveA * reserveB;
        (IERC20 tokenIn, IERC20 tokenOut, uint256 reserveIn, uint256 reserveOut) = 
            inputToken == address(tokenA)
            ? (tokenA, tokenB, reserveA, reserveB)
            : (tokenB, tokenA, reserveB, reserveA);
        
        _safeTransferFrom(tokenIn, msg.sender, address(this), inputAmount);

        uint effectiveInputAmount = inputAmount * 997 / 1000;
        require(effectiveInputAmount > 0, "Pool: Input too small after fees");

        uint numerator = effectiveInputAmount * reserveOut;
        uint denominator = reserveIn + effectiveInputAmount;
        uint outputAmount = numerator / denominator + 1;

        require(outputAmount >= minOutputAmount, "Pool: Insufficient output amount");
        require(outputAmount < reserveOut, "Pool: Insufficient liquidity in pool");

        _safeTransfer(tokenOut, msg.sender, outputAmount);

        _reserveUpdate();
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) private reentrancyGuard {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
    }

    function _safeTransferFrom(IERC20 token, address from, address to, uint256 amount) private reentrancyGuard {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
    }

}
