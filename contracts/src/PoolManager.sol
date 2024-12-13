// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PoolManager {
    
    address public owner;
    struct Pool {
        address token0;
        address token1;
        uint24 fee;
        uint reserve0;
        uint reserve1;
    }

    mapping(bytes32 => Pool) public pools;

    event Mint(bytes32 poolId, address indexed to, uint amountAIn, uint amountBIn);
    event Burn(bytes32 poolId, address indexed from, address indexed to, uint amountAOut, uint amountBOut);
    event PoolCreated(bytes32 poolId, address indexed token0, address indexed token1, uint24 fee);
    event Swap(
        address indexed from,
        address indexed to,
        uint amountAIn,
        uint amountBIn, 
        uint amountAOut,
        uint amountBOut
    );

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
            fee: fee,
            reserve0: 0,
            reserve1: 0
        });

        emit PoolCreated(poolId, token0_, token1_, fee);
    }

    function addLiquidity(bytes32 poolId, uint amount0, uint amount1) external {
        require(pools[poolId].token0 != address(0), "Pool does not exist");
        Pool storage pool = pools[poolId];

        IERC20(pool.token0).transferFrom(msg.sender, address(this), amount0);
        IERC20(pool.token1).transferFrom(msg.sender, address(this), amount1);

        pool.reserve0 += amount0;
        pool.reserve1 += amount1;
        liquidity[poolId][msg.sender] += amount0 * amount1; // Liquidity is represented as the product of amounts

        emit LiquidityAdded(msg.sender, poolId, amount0, amount1);
    }

    function removeLiquidity(bytes32 poolId, uint liquidityAmount) external {
        require(pools[poolId].token0 != address(0), "Pool does not exist");
        require(liquidity[poolId][msg.sender] >= liquidityAmount, "Insufficient liquidity");
        
        Pool storage pool = pools[poolId];

        uint totalLiquidity = pool.reserve0 * pool.reserve1;
        require(totalLiquidity > 0, "No liquidity available");

        uint amount0 = (liquidityAmount * pool.reserve0) / totalLiquidity;
        uint amount1 = (liquidityAmount * pool.reserve1) / totalLiquidity;

        pool.reserve0 -= amount0;
        pool.reserve1 -= amount1;
        liquidity[poolId][msg.sender] -= liquidityAmount; // Reduce user's liquidity share

        IERC20(pool.token0).transfer(msg.sender, amount0);
        IERC20(pool.token1).transfer(msg.sender, amount1);

        emit LiquidityRemoved(msg.sender, poolId, amount0, amount1);
    }
}
}