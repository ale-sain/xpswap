// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "../lib/Math.sol";

import "../interfaces/IERC20.sol";
import "./XpswapERC20.sol";
import "./XpswapPool.sol";


contract XpswapFactory {

    mapping(bytes32 => address) public pools;

    event PoolCreated(address tokenA, address tokenB, address pool);

    constructor() {
    }

    function addressSort(address tokenA_, address tokenB_) private pure returns (address, address) {
        return tokenA_ < tokenB_ ? (tokenA_, tokenB_) : (tokenB_, tokenA_);
    }

    function createPool(address tokenA_, address tokenB_) public {
        require(tokenA_ != tokenB_, "Factory: Duplicate tokens");
        require(tokenA_ != address(0), "Factory: Invalid token A address");
        require(tokenB_ != address(0), "Factory: Invalid token B address");
        
        (address tokenA, address tokenB) = addressSort(tokenA_, tokenB_);
        bytes32 hashPool = keccak256(abi.encodePacked(tokenA, tokenB));

        require(pools[hashPool] == address(0), "Factory: Duplicate pools");

        pools[hashPool] = address(new XpswapPool(tokenA, tokenB));

        emit PoolCreated(tokenA, tokenB, address(pools[hashPool]));
    }
}