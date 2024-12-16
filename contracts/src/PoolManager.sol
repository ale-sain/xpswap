// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "forge-std/console.sol";

contract PoolManager is ReentrancyGuard {
    address public owner;

    struct Debt {
        address token;
        uint256 amount;
        bytes32 poolId;
    }

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

    Debt[] public debts;

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
        require(fee < 1000, "Invalid fee");

        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);

        poolId = keccak256(abi.encodePacked(token0_, token1_, fee));
        require(pools[poolId].token0 == address(0), "Pool already exists");

        pools[poolId] = Pool({
            token0: token0_,
            token1: token1_,
            fee: fee,
            reserve0: 0,
            reserve1: 0,
            liquidity: 0
        });

        emit PoolCreated(poolId, token0_, token1_, fee);
    }

    function getPoolId(address token0, address token1, uint24 fee) public view returns (bytes32 poolId) {
        (address _token0, address _token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        poolId = keccak256(abi.encodePacked(_token0, _token1, fee));
    }

    function addLiquidity(bytes32 poolId, uint amount0, uint amount1, address to) external nonReentrant {
        // console.log("to = ", to);
        Pool memory pool = pools[poolId];
        uint24 minimumLiquidity = pool.liquidity == 0 ? 1000 : 0;
        
        require(to != address(0), "Invalid address");
        require(pool.token0 != address(0), "Pool does not exist");
        require(amount0 > minimumLiquidity, "Pool: Invalid amount for token A");
        require(amount1 > minimumLiquidity, "Pool: Invalid amount for token B");
        {
            if (pool.liquidity != 0) {
                uint ratioA = amount0 * pool.liquidity / pool.reserve0;
                uint ratioB = amount1 * pool.liquidity / pool.reserve1;
                if (ratioB < ratioA) {
                    amount0 = amount1 * pool.reserve0 / pool.reserve1;
                } else {
                    amount1 = amount0 * pool.reserve1 / pool.reserve0;
                }
            }
            // console.log("amount0: %s", amount0);
            // console.log("amount1: %s", amount1);
        }

        uint liquidityIn = Math.sqrt(amount0 * amount1);
        
        pool.reserve0 += amount0;
        pool.reserve1 += amount1;
        pool.liquidity += liquidityIn;
        liquidity[poolId][to] += liquidityIn - minimumLiquidity;
        
        pools[poolId] = pool;

        _safeTransferFrom(pool.token0, msg.sender, address(this), amount0);
        _safeTransferFrom(pool.token1, msg.sender, address(this), amount1);

        emit Mint(poolId, to, amount0, amount1);
    }

    function removeLiquidity(bytes32 poolId, uint liquidityOut, address to) external nonReentrant {
        // console.log("liquidityOut = ", liquidityOut);
        // console.log(liquidity[poolId][msg.sender]);
        // console.log("to = ", to);
        Pool memory pool = pools[poolId];

        require(to != address(0), "Invalid address");
        require(pools[poolId].token0 != address(0), "Pool does not exist");
        require(liquidity[poolId][msg.sender] >= liquidityOut, "Insufficient liquidity");

        uint amount0Out = (liquidityOut * pool.reserve0) / pool.liquidity;
        uint amount1Out = (liquidityOut * pool.reserve1) / pool.liquidity;

        require(amount0Out < pool.reserve0, "Pool: Insufficient liquidity in pool");
        require(amount1Out < pool.reserve1, "Pool: Insufficient liquidity in pool");
    
        pool.reserve0 -= amount0Out;
        pool.reserve1 -= amount1Out;
        pool.liquidity -= liquidityOut;
        liquidity[poolId][to] -= liquidityOut;
        
        pools[poolId] = pool;

        _safeTransfer(pool.token0, to, amount0Out);
        _safeTransfer(pool.token1, to, amount1Out);

        emit Burn(poolId, msg.sender, to, amount0Out, amount1Out);
    }

    function router() public {

    }
    
    function getAmountIn(bytes32 id, uint reserveIn, uint reserveOut, uint amountOut) public view returns (uint amountIn) {
        Pool memory _pool = pools[id];
        
        uint numerator = reserveIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * (1000 - _pool.fee);
        amountIn = numerator / denominator;
    }

    function getAmountOut(bytes32 id, uint reserveIn, uint reserveOut, uint amountIn) public view returns (uint amountOut) {
        Pool memory _pool = pools[id];
        uint amountInWithFee = amountIn * _pool.fee / 1000;

        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function reserveUpdate(bytes32 id, uint amount0, uint amount1) private {
        Pool storage pool = pools[id];
        
        pool.reserve0 += amount0;
        pool.reserve1 -= amount1;
    }

    function swapWithInput(Pool memory pool, uint amountIn, uint minAmountOut, bool zeroForOne) public {
        bytes32 id = getPoolId(pool.token0, pool.token1, pool.fee);
        Pool memory _pool = pools[id];
        (uint reserveIn, uint reserveOut) = zeroForOne ? (_pool.reserve0, _pool.reserve1) : (_pool.reserve1, _pool.reserve0);

        require(_pool.token0 != address(0), "Pool does not exist");
        require(amountIn * _pool.fee > 0, "Pool: Input too small after fees");
        
        uint amountOut = getAmountOut(id, amountIn, reserveIn, reserveOut);

        require(amountOut >= minAmountOut, "Pool: Insufficient output amount");
        require(amountOut < reserveOut, "Pool: Insufficient liquidity in pool");

        reserveUpdate(id, zeroForOne ? amountIn : amountOut, zeroForOne ? amountOut : amountIn);
    }

    function swapWithOutput(Pool memory pool, uint amountOut, uint maxAmoutIn, bool zeroForOne) public {
        bytes32 id = getPoolId(pool.token0, pool.token1, pool.fee);
        Pool memory _pool = pools[id];
        (uint reserveIn, uint reserveOut) = zeroForOne ? (_pool.reserve0, _pool.reserve1) : (_pool.reserve1, _pool.reserve0);

        require(_pool.token0 != address(0), "Pool does not exist");
        require(amountOut < reserveOut, "Insufficient liquidity in pool");
        
        uint amountIn = getAmountIn(id, amountOut, reserveIn, reserveOut);
        
        require(amountIn <= maxAmoutIn, "Insufficient input amount");

        reserveUpdate(id, zeroForOne ? amountIn : amountOut, zeroForOne ? amountOut : amountIn);
    }

    function takeAll(address token, uint amountOut, address to) public {
        require(token != address(0), "Invalid token address");
        require(amountOut > 0, "Invalid amount");
        require(IERC20(token).balanceOf(address(this)) >= amountOut, "Insufficient balance");

        _safeTransfer(token, to, amountOut);
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) public {
        uint256 amountOut = getAmountOut(amountIn, tokenIn, tokenOut);

        // 🔥 Au lieu de transférer maintenant, on enregistre la dette
        debts.push(Debt({
            token: tokenOut,
            amount: amountOut,
            pool: address(pool)
        }));
    }

    function settleAll() public {
        for (uint256 i = 0; i < debts.length; i++) {
            Debt memory debt = debts[i];
            if (debt.amount > 0) {
                require(IERC20(debt.token).balanceOf(msg.sender) >= debt.amount, "Insufficient user balance");
                _safeTransferFrom(debt.token, msg.sender, address(this), debt.amount);
            }
        }
        delete debts;
    }

    function settleAll(address token, address from) public {
        require(token != address(0), "Invalid token address");
        require(IERC20(token).balanceOf(from) > 0, "Insufficient balance");

        _safeTransferFrom(token, from, IERC20(token).balanceOf(address(this)));
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        // console.log("from: %s", from);
        // console.log("transfer to: %s", to);
        // console.log("amount: %s", amount);
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        // console.log("from: %s", from);
        // console.log("to: %s", to);
        // console.log("amount: %s", amount);
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
    }
}
