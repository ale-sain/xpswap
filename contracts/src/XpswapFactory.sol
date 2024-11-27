// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "../lib/Math.sol";

import "../interfaces/IERC20.sol";
import "./XpswapERC20.sol";
import "./XpswapPool.sol";


contract XpswapFactory {

    address[] public allPools;

    uint256 public poolCount;
    event PoolCreated(address tokenA, address tokenB, address pool);

    constructor() {
    }

    function createPool(address tokenA_, address tokenB_) public returns (address) {
        require(tokenA_ != tokenB_, "Factory: Duplicate tokens");
        require(tokenA_ != address(0), "Factory: Invalid token A address");
        require(tokenB_ != address(0), "Factory: Invalid token B address");
        bytes32 hash = 
        XpswapPool newPool = new XpswapPool(tokenA_, tokenB_);
        allPools.push(address(newPool));
        poolCount += 1;

        emit PoolCreated(tokenA_, tokenB_, address(newPool));

        return address(newPool);
    }
}