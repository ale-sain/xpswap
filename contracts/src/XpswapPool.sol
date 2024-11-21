// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "./XpswapERC20.sol";

import "forge-std/console.sol";

contract XpswapPool is XpswapERC20 {
    IERC20 public tokenA;
    IERC20 public tokenB;

    uint public reserveA;
    uint public reserveB;
    uint public liquidity;

    uint8 txFees = 3;

    constructor(address tokenA_, address tokenB_) XpswapERC20() {
        tokenA = IERC20(tokenA_);
        tokenB = IERC20(tokenB_);
    }

    function addLiquidity(uint amountA, uint amountB) public {
        console.log("<<<<<<<< ADD LIQUIDITY >>>>>>>>>>");
        require(amountA > 0, "Pool: Invalid amount for token A");
        require(amountB > 0, "Pool: Invalid amount for token B");

        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);
        
        uint16 liquidityMinimum = 0;
        if (liquidity == 0)
            liquidityMinimum = 1000;

        uint256 userLiquidity = amountA * amountB;
        reserveA += amountA;
        reserveB += amountB;
        liquidity += userLiquidity;

        _mint(msg.sender, userLiquidity - liquidityMinimum);
        console.log("<<<<<<<<<<<< END ADD LIQUIDITY >>>>>>>>>>>");
    }

    function removeLiquidity(uint userDeposit) public {
        require(userDeposit > 0, "Pool: Insufficient deposit");
        require(userDeposit <= totalDeposit, "Pool: Invalid deposit amount");

        _burn(msg.sender, userDeposit);

        uint256 userShare = (userDeposit * 1e18) / totalDeposit;

        uint256 amountA = (reserveA * userShare) / 1e18;
        uint256 amountB = (reserveB * userShare) / 1e18;
        console.log("userShare = ", userShare);

        reserveA -= amountA;
        reserveB -= amountB;
        totalDeposit -= userDeposit;
        k = reserveA * reserveB;

        tokenA.transfer(msg.sender, amountA);
        tokenB.transfer(msg.sender, amountB);
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

        tokenIn.transferFrom(msg.sender, address(this), inputAmount);
        tokenOut.transfer(msg.sender, outputAmount);

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

    function swapWithInput(uint256 inputAmount, address inputToken) public {
        console.log("<<<<<<<<<<<< SWAP >>>>>>>>>>>>>");
        require(inputToken == address(tokenA) || inputToken == address(tokenB), "Pool: Invalid token address");
        require(inputAmount > 0, "Pool: Invalid input amount");
        (IERC20 tokenIn, IERC20 tokenOut, uint256 reserveIn, uint256 reserveOut) = 
            inputToken == address(tokenA)
            ? (tokenA, tokenB, reserveA, reserveB)
            : (tokenB, tokenA, reserveB, reserveA);
        
        uint256 effectiveInputAmount = inputAmount * 997 / 1000;
        require(effectiveInputAmount > 0, "Pool: Input too small after fees");

        uint256 numerator = effectiveInputAmount * reserveOut;
        uint256 denominator = reserveIn + effectiveInputAmount;
        uint256 outputAmount = numerator / denominator;

        console.log(outputAmount);
        require(outputAmount < reserveOut, "Pool: Insufficient liquidity in pool");

        tokenIn.transferFrom(msg.sender, address(this), inputAmount);
        tokenOut.transfer(msg.sender, outputAmount);

        reserveIn += inputAmount;
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

}
