// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "./XpswapERC20.sol";
import "../lib/Math.sol";

import "forge-std/console.sol";

contract XpswapPool is XpswapERC20 {
    using Math for uint256;

    IERC20 public tokenA;
    IERC20 public tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

    uint8 txFees = 3;

    constructor(address tokenA_, address tokenB_) XpswapERC20() {
        tokenA = IERC20(tokenA_);
        tokenB = IERC20(tokenB_);
    }

    function addLiquidity(uint amountA, uint amountB) public {
        console.log("<<<<<<<< ADD LIQUIDITY >>>>>>>>>>");

        require(amountA > 0, "Pool: Invalid amount for token A");
        require(amountB > 0, "Pool: Invalid amount for token B");

        amountA = _safeTransferFrom(tokenA, msg.sender, address(this), amountA);
        amountB = _safeTransferFrom(tokenB, msg.sender, address(this), amountB);
        
        uint256 liquidityIn;
        uint256 liquidity = totalSupply;
        uint256 effectiveAmountA = amountA;
        uint256 effectiveAmountB = amountB;
        
        if (liquidity == 0) {
            uint256 liquidityMinimum = 1000;
            liquidityIn = (amountA * amountB).sqrt() - liquidityMinimum;
            _mint(address(0), liquidityMinimum);
        }
        else {
            uint256 ratioA = amountA * liquidity / reserveA;
            uint256 ratioB = amountB * liquidity / reserveB;
            liquidityIn = ratioA.min(ratioB);
            if (ratioB < ratioA) {
                effectiveAmountA = amountB * reserveA / reserveB;
                _safeTransfer(tokenA, msg.sender, amountA - effectiveAmountA);
            } else {
                effectiveAmountB = amountA * reserveB / reserveA;
                _safeTransfer(tokenB, msg.sender, amountB - effectiveAmountB);
            }
        }
        reserveA += effectiveAmountA;
        reserveB += effectiveAmountB;

        _mint(msg.sender, liquidityIn);

        console.log("<<<<<<<<<<<< END ADD LIQUIDITY >>>>>>>>>>>");
    }

    function removeLiquidity(uint liquidityOut) public {
        console.log("<<<<<<<<<<<< REMOVE LIQUIDITY >>>>>>>>>>>");
        uint256 liquidity = totalSupply;

        require(liquidityOut > 0, "Pool: Invalid amount for token LP");
        require(balanceOf[msg.sender] >= liquidityOut, "Pool: Insufficient LP balance");
        require(liquidityOut <= liquidity, "Pool: Invalid liquidity amount");

        uint256 amountA = (reserveA * liquidityOut) / liquidity;
        uint256 amountB = (reserveB * liquidityOut) / liquidity;

        require(amountA < reserveA, "Pool: Insufficient liquidity in pool");
        require(amountB < reserveB, "Pool: Insufficient liquidity in pool");

        reserveA -= amountA;
        reserveB -= amountB;

        _burn(msg.sender, liquidityOut);
        _safeTransfer(tokenA, msg.sender, amountA);
        _safeTransfer(tokenB, msg.sender, amountB);
        console.log("<<<<<<<<<<<< REMOVE LIQUIDITY >>>>>>>>>>>");
    }

    function swapWithOutput(uint256 outputAmount, address outputToken) public {
        console.log("<<<<<<<<<<<< SWAP >>>>>>>>>>>>>");
        require(outputToken == address(tokenA) || outputToken == address(tokenB), "Pool: Invalid token address");
        require(outputAmount > 0, "Pool: Invalid output amount");
        (IERC20 tokenOut, IERC20 tokenIn, uint256 reserveOut, uint256 reserveIn) = 
            outputToken == address(tokenA)
            ? (tokenA, tokenB, reserveA, reserveB)
            : (tokenB, tokenA, reserveB, reserveA);
        
        require(outputAmount < reserveOut, "Pool: Insufficient liquidity in pool");

        uint256 numerator = outputAmount * reserveIn * 1000;
        uint256 denominator = (reserveOut - outputAmount) * (1000 - txFees);
        uint256 inputAmount = numerator / denominator;
        console.log("inputamount->>>> ", inputAmount);

        uint256 actualInputAmount = _safeTransferFrom(tokenIn, msg.sender, address(this), inputAmount);
        require(actualInputAmount >= inputAmount, "Pool: Insufficient input amount");
        inputAmount = actualInputAmount;
        _safeTransfer(tokenOut, msg.sender, outputAmount);

        reserveIn += inputAmount;
        reserveOut -= (outputAmount);

        if (outputToken == address(tokenA)) {
            reserveA = reserveOut;
            reserveB = reserveIn;
        } else {
            reserveA = reserveIn;
            reserveB = reserveOut;
        }
        console.log("<<<<<<<<<< END SWAP >>>>>>>>>>>>");
    }

    function swapWithInput(uint256 inputAmount, uint256 minOutputAmount, address inputToken) public {
        console.log("<<<<<<<<<<<< SWAP >>>>>>>>>>>>>");
        require(inputToken == address(tokenA) || inputToken == address(tokenB), "Pool: Invalid token address");
        require(inputAmount > 0, "Pool: Invalid input amount");
        (IERC20 tokenIn, IERC20 tokenOut, uint256 reserveIn, uint256 reserveOut) = 
            inputToken == address(tokenA)
            ? (tokenA, tokenB, reserveA, reserveB)
            : (tokenB, tokenA, reserveB, reserveA);
        
        uint256 actualInputAmount = _safeTransferFrom(tokenIn, msg.sender, address(this), inputAmount);

        uint256 effectiveInputAmount = actualInputAmount * 997 / 1000;
        require(effectiveInputAmount > 0, "Pool: Input too small after fees");

        uint256 numerator = effectiveInputAmount * reserveOut;
        uint256 denominator = reserveIn + effectiveInputAmount;
        uint256 outputAmount = numerator / denominator;

        console.log(outputAmount);
        require(outputAmount >= minOutputAmount, "Pool: Insufficient output amount");
        require(outputAmount < reserveOut, "Pool: Insufficient liquidity in pool");

        _safeTransfer(tokenOut, msg.sender, outputAmount);

        reserveIn += actualInputAmount;
        reserveOut -= (outputAmount);

        if (inputToken == address(tokenA)) {
            reserveA = reserveIn;
            reserveB = reserveOut;
        } else {
            reserveA = reserveOut;
            reserveB = reserveIn;
        }
        console.log("<<<<<<<<<< END SWAP >>>>>>>>>>>>");
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) private {
        uint256 balanceBefore = token.balanceOf(address(this));
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        uint256 balanceAfter = token.balanceOf(address(this));
    
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
        require(balanceBefore - amount == balanceAfter, 'Pool: Transfer amount incorrect');
    }

    function _safeTransferFrom(IERC20 token, address from, address to, uint256 amount) private returns (uint256) {
        uint256 balanceBefore = token.balanceOf(to);
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        uint256 balanceAfter = token.balanceOf(to);
        
        console.log(success);
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
        require(balanceAfter > balanceBefore, 'Pool: Transfer amount incorrect');
    
        return balanceAfter - balanceBefore;
    }

}
