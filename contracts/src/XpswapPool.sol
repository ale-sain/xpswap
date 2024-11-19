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
    uint public totalDeposit;
    uint public k;

    constructor(address tokenA_, address tokenB_) XpswapERC20() {
        tokenA = IERC20(tokenA_);
        tokenB = IERC20(tokenB_);
    }

    function addLiquidity(uint amountA, uint amountB) public {
        require(amountA > 0, "Invalid amount for token A");
        require(amountB > 0, "Invalid amount for token B");

        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);
        
        uint256 userDeposit = amountA * 2;

        reserveA += amountA;
        reserveB += amountB;
        totalDeposit += userDeposit;
        k = reserveA * reserveB;

        _mint(msg.sender, userDeposit);
    }

    function removeLiquidity(uint userDeposit) public {
        require(userDeposit > 0, "Insufficient deposit");
        require(userDeposit <= totalDeposit, "Invalid deposit amount");

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

    function swap(uint256 outputAmount, address outputToken) public {
        require(outputToken == address(tokenA) || outputToken == address(tokenB), "Invalid token address");

        (IERC20 tokenOut, IERC20 tokenIn, uint256 reserveOut, uint256 reserveIn) = 
            outputToken == address(tokenA)
            ? (tokenA, tokenB, reserveA, reserveB)
            : (tokenB, tokenA, reserveB, reserveA);

        require(outputAmount <= reserveOut, "Insufficient liquidity in pool");
        
        uint256 inputAmount = (outputAmount * reserveIn) / (reserveOut - outputAmount);

        tokenIn.transferFrom(msg.sender, address(this), inputAmount);
        reserveIn += inputAmount;
        
        tokenOut.transfer(msg.sender, outputAmount);
        reserveOut -= outputAmount;

        if (outputToken == address(tokenA)) {
            reserveA = reserveOut;
            reserveB = reserveIn;
        } else {
            reserveA = reserveIn;
            reserveB = reserveOut;
        }
    }

}
