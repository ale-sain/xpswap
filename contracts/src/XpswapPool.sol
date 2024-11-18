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
    uint public reserveTotal;

    constructor(address tokenA_, address tokenB_) XpswapERC20() {
        tokenA = IERC20(tokenA_);
        tokenB = IERC20(tokenB_);
    }

    function addLiquidity(uint amountA, uint amountB) public {
        require(tokenA.transferFrom(msg.sender, address(this), amountA), "Transfer failed");
        require(tokenB.transferFrom(msg.sender, address(this), amountB), "Transfer failed");
        uint amountTotal = amountA * 2;

        reserveA += amountA;
        reserveB += amountB;
        reserveTotal += amountTotal;

        _mint(msg.sender, amountTotal);
    }

}
