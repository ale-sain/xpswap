// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PoolManager {
    
    struct Pool {
        address token0;
        address token1;
        uint24 fee;
    }

    mapping(bytes32 => Pool) public pools;
    address public owner;

    event PoolCreated(address indexed token0, address indexed token1, uint24 fee, bytes32 poolId);
    event PoolDeleted(address indexed token0, address indexed token1, uint24 fee, bytes32 poolId);

    constructor() {}

    function createPool(address token0, address token1, uint24 fee) external returns (bytes32 poolId) {
        require(token0 != token1, "Identical tokens");
        require(token0 != address(0) && token1 != address(0), "Invalid token address");

        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);

        poolId = keccak256(abi.encodePacked(token0_, token1_, fee));
        require(pools[poolId].token0 == address(0), "Pool already exists");

        pools[poolId] = Pool({
            token0: token0_,
            token1: token1_,
            fee: fee
        });

        emit PoolCreated(token0, token1, fee, poolId);
    }

    function deletePool(bytes32 poolId) external {
        require(pools[poolId].token0 != address(0), "Pool does not exist");
        
        (address token0, address token1, uint24 fee) = (pools[poolId].token0, pools[poolId].token1, pools[poolId].fee);
        delete pools[poolId];
        
        emit PoolDeleted(token0, token1, fee, poolId);
    }
}