// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "../lib/Math.sol";

import "../interfaces/IERC20.sol";
import "./XpswapERC20.sol";
import "./XpswapPool.sol";


contract XpswapFactory {

    mapping(address => mapping(address => address)) public pools;

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
        require(pools[tokenA][tokenB] == address(0), "Factory: Duplicate pools");

        bytes memory bytecode = type(XpswapPool).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(tokenA, tokenB));

        address pool;

        assembly {
            pool := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        XpswapPool(pool).initialize(tokenA, tokenB);

        pools[tokenA][tokenB] = pool;
        pools[tokenB][tokenA] = pool;

        emit PoolCreated(tokenA, tokenB, address(pools[tokenA][tokenB]));
    }
}