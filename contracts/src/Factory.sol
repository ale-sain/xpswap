// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "../lib/Math.sol";

import "../interfaces/IERC20.sol";
import "./XpswapERC20.sol";
import "./Pool.sol";


contract XpswapFactory {
    address[] public poolsArray;
    mapping(bytes32 => address) public pools;

    event PoolCreated(address tokenA, address tokenB, address pool, uint);

    constructor() {}

    function createPool(address tokenA, address tokenB, uint8 fee) public {
        require(tokenA != tokenB, "Factory: Duplicate tokens");
        require(tokenA != address(0), "Factory: Invalid token A address");
        require(tokenB != address(0), "Factory: Invalid token B address");
        
        (address _tokenA, address _tokenB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 poolId = keccak256(abi.encodePacked(tokenA, tokenB, fee));
        require(pools[poolId] == address(0), "Factory: Duplicated pools");

        address pool = address(new XpswapPool(_tokenA, _tokenB, fee));
        poolsArray.push(pool);

        emit PoolCreated(_tokenA, _tokenB, pool, poolsArray.length);
    }
}