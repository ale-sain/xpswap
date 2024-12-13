// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PoolManager {
    uint24 minimumLiquidity = 1000;

    address public owner;
    struct Pool {
        address token0;
        address token1;
        uint24 fee;
        uint reserve0;
        uint reserve1;
        uint liquidity;
    }

    mapping(bytes32 => Pool) public pools;
    mapping(bytes32 => mapping(address => uint)) public liquidity;


    event Mint(bytes32 poolId, address indexed to, uint amount0In, uint amount1In);
    event Burn(bytes32 poolId, address indexed from, address indexed to, uint amount0Out, uint amount1Out);
    event PoolCreated(bytes32 poolId, address indexed token0, address indexed token1, uint24 fee);
    event Swap(
        address indexed from,
        address indexed to,
        uint amount0In,
        uint amount1In, 
        uint amount0Out,
        uint amount1Out
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

    function addLiquidity(bytes32 poolId, uint amount0, uint amount1, address to) external {
        Pool memory pool = pools[poolId];
        
        require(pool.token0 != address(0), "Pool does not exist");
        require(amount0 > 0, "Pool: Invalid amount for token A");
        require(amount1 > 0, "Pool: Invalid amount for token B");

        uint finalAmount0 = amount0;
        uint finalAmount1 = amount1;

        if (pool.liquidity != 0) {
            uint ratioA = amount0 * pool.liquidity / pool.reserve0;
            uint ratioB = amount1 * pool.liquidity / pool.reserve1;
            if (ratioB < ratioA) {
                finalAmount0 = amount1 * pool.reserve0 / pool.reserve1;
            } else {
                finalAmount1 = amount0 * pool.reserve1 / pool.reserve0;
            }
        }

        _safeTransferFrom(pool.token0, msg.sender, address(this), finalAmount0);
        _safeTransferFrom(pool.token1, msg.sender, address(this), finalAmount1);

        uint liquidityIn = 0;
        uint newLiquidity = Math.sqrt(finalAmount0 * finalAmount1);
        
        if (pool.liquidity == 0) 
            liquidityIn = newLiquidity - minimumLiquidity;
        else 
            liquidityIn = newLiquidity;

        pool.reserve0 += finalAmount0;
        pool.reserve1 += finalAmount1;
        pool.liquidity += newLiquidity;
        liquidity[pool][to] += liquidityIn;
        
        pools[poolId] = pool;

        emit Mint(poolId, to, finalAmount0, finalAmount1);
    }

    function removeLiquidity(bytes32 poolId, uint liquidityOut, address to) external {
        Pool memory pool = pools[poolId];

        require(pools[poolId].token0 != address(0), "Pool does not exist");
        require(liquidity[poolId][msg.sender] >= liquidityOut, "Insufficient liquidity");
        require(liquidityOut <= liquidity, "Pool: Invalid liquidity amount");

        uint amount0Out = (liquidityOut * pool.reserve0) / pool.liquidity;
        uint amount1Out = (liquidityOut * pool.reserve1) / pool.liquidity;

        require(amount0Out < pool.reserve0, "Pool: Insufficient liquidity in pool");
        require(amount1Out < pool.reserve1, "Pool: Insufficient liquidity in pool");
    
        pool.reserve0 -= amount0Out;
        pool.reserve1 -= amount1Out;
        liquidity[poolId][to] -= liquidityOut; // Reduce user's liquidity share
        pools[poolId] = pool;

        _safeTransfer(pool.token0, to, amount0Out);
        _safeTransfer(pool.token1, to, amount1Out);

        emit Burn(poolId, msg.sender, to, amount0Out, amount1Out);
    }
}
