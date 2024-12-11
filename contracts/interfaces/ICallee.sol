// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IUniswapV2Callee {
    function xpswapCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}