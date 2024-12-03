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

    function _getReserves() private view returns (uint112, uint112) {
        uint112 _reserveA = reserveA;
        uint112 _reserveB = reserveB;
        return (_reserveA, _reserveB);
    }

    function addLiquidity(address to) public reentrancyGuard {
        (uint112 _reserveA, uint112 _reserveB) = _getReserves();

        uint112 amountA = uint112(IERC20(tokenA).balanceOf(address(this))) - _reserveA;
        uint112 amountB = uint112(IERC20(tokenB).balanceOf(address(this))) - _reserveB;

        require(amountA > 0, "Pool: Invalid amount for token A");
        require(amountB > 0, "Pool: Invalid amount for token B");
        
        uint liquidityIn = 0;
        uint liquidity = totalSupply;
        uint effectiveAmountA = amountA;
        uint effectiveAmountB = amountB;

        bool feeOn = _mintFee(_reserveA, _reserveB);
        
        if (liquidity == 0) {
            uint liquidityMinimum = 1000;
            liquidityIn = Math.sqrt(amountA * amountB) - liquidityMinimum;
            _mint(address(0), liquidityMinimum);
        }
        else {
            uint ratioA = amountA * liquidity / _reserveA;
            uint ratioB = amountB * liquidity / _reserveB;
            liquidityIn = Math.min(ratioA, ratioB);
            if (ratioB < ratioA) {
                effectiveAmountA = amountB * _reserveA / _reserveB;
                _safeTransfer(tokenA, to, amountA - effectiveAmountA);
            } else {
                effectiveAmountB = amountA * _reserveB / _reserveA;
                _safeTransfer(tokenB, to, amountB - effectiveAmountB);
            }
        }

        _reserveUpdate();
        if (feeOn) lastK = uint(reserveA) * uint(reserveB);
        if (liquidityIn > 0) _mint(to, liquidityIn);
    }

    function removeLiquidity(address to) public reentrancyGuard {
        (uint112 _reserveA, uint112 _reserveB) = _getReserves();
        uint _totalSupply = totalSupply;
        bool feeOn = _mintFee(_reserveA, _reserveB);
        uint liquidityOut = balanceOf[address(this)];

        require(liquidityOut > 0, "Pool: Invalid amount for token LP");
        require(liquidityOut <= _totalSupply, "Pool: Invalid liquidity amount");

        uint amountA = (_reserveA * liquidityOut) / _totalSupply;
        uint amountB = (_reserveB * liquidityOut) / _totalSupply;

        require(amountA < _reserveA, "Pool: Insufficient liquidity in pool");
        require(amountB < _reserveB, "Pool: Insufficient liquidity in pool");

        _safeTransfer(tokenA, to, amountA);
        _safeTransfer(tokenB, to, amountB);

        _reserveUpdate();
        if (feeOn) lastK = uint(reserveA) * uint(reserveB);
    
        _burn(address(this), liquidityOut);
    }

    function swap(uint amountAOut, uint amountBOut, address to) public reentrancyGuard {
        (uint _reserveA, uint _reserveB) = _getReserves();
        uint8 _txFees = txFees;

        require(amountAOut > 0 || amountBOut > 0, "Pool: Invalid output amount");
        require(amountAOut < _reserveA && amountBOut < _reserveB, "Pool: Insufficient liquidity");

        uint balanceA = IERC20(tokenA).balanceOf(address(this));
        uint balanceB = IERC20(tokenB).balanceOf(address(this));

        uint amountAIn = amountBOut > 0 ? (balanceA - _reserveA) * (1000 - _txFees) / 1000 : 0;
        uint amountBIn = amountAOut > 0 ? (balanceB - _reserveB) * (1000 - _txFees) / 1000 : 0;

        require(amountAIn > 0 || amountBIn > 0, "Pool: Insufficient input amount");

        if (amountAOut > 0 ) _safeTransfer(tokenA, to, amountAOut);
        if (amountBOut > 0 ) _safeTransfer(tokenB, to, amountBOut);

        require((balanceA - amountAOut) * (balanceB - amountBOut) >= lastK , "Pool: invalid constant product k");

        _reserveUpdate();
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

    function _mintFee(uint112 _reserveA, uint112 _reserveB) private returns (bool) {
        address feeTo = XpswapFactory(factory).feeTo();
        bool feeOn = feeTo != address(0);

        uint rootCurrK = Math.sqrt(_reserveA * _reserveB);
        uint rootLastK = Math.sqrt(lastK);

        if (feeOn) {
            if (rootCurrK > rootLastK) {
                uint numerator = (rootCurrK - rootLastK) * totalSupply;
                uint denominator = rootCurrK * 5 + rootLastK;
                uint feeOut = numerator / denominator;
                if (feeOut > 0) _mint(feeTo, feeOut);
            }
        }
        else
            lastK = 0;

        return feeOn;
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) private {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
    }
}
