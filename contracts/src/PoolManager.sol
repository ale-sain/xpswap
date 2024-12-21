// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "forge-std/console.sol";
import {ICallback} from "./Router.sol";

contract PoolManager is ReentrancyGuard {
    bool lock = true;
    address public owner;
    uint24 fee = 3;

    struct Pool {
        address token0;
        address token1;
        uint reserve0;
        uint reserve1;
    }

    mapping(bytes32 => Pool) public pools;
    mapping(bytes32 => mapping(address => uint)) public lp;

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

    // function unlock(uint256[] calldata actions, bytes[] calldata data) public {
    //     require(lock == true, "Contract already in use");
        
    //     lock = false;
    //     ICallback(msg.sender).executeAll(actions, data);
    //     lock = true;

    //     require(_getTransientVariable(keccak256(abi.encodePacked("activeDelta"))) == 0, "Unprocessed transactions");
    // }

    function createPool(address token0, address token1) external returns (bytes32 poolId) {
        require(token0 != token1, "Identical tokens");
        require(token0 != address(0) && token1 != address(0), "Invalid token address");

        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);

        poolId = keccak256(abi.encodePacked(token0_, token1_));
        require(pools[poolId].token0 == address(0), "Pool already exists");

        pools[poolId] = Pool({
            token0: token0_,
            token1: token1_,
            reserve0: 0,
            reserve1: 0
        });
    }

    function getPoolId(address token0, address token1) public pure returns (bytes32 poolId) {
        (address _token0, address _token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        poolId = keccak256(abi.encodePacked(_token0, _token1));
    }

    function _setTransientValue(bytes32 key, int delta) public returns (int beforeValue, int afterValue) {
        assembly {
            beforeValue := tload(key)
            afterValue := add(beforeValue, delta)
            tstore(key, afterValue)
        }
    }

    function _getTransientVariable(bytes32 key) public view returns (int256 value) {
        assembly {
            value := tload(key)
        }
    }

    function _updatePoolTransientReserve(bytes32 poolId, int amount0, int amount1, int liquidity) public {
        Pool memory pool = pools[poolId];

        if (liquidity != 0) _setTransientValue(keccak256(abi.encodePacked(poolId, msg.sender)), liquidity);
        (int before0, int after0) = _setTransientValue(keccak256(abi.encodePacked(poolId, pool.token0)), amount0);
        // console.log("AMOUNT 0 : before0: %s", before0);
        // console.log("AMOUNT 0 : after0: %s", after0);
        (int before1, int after1) = _setTransientValue(keccak256(abi.encodePacked(poolId, pool.token1)), amount1);
        // console.log("AMOUNT 1 : before1: %s", before1);
        // console.log("AMOUNT 1 : after1: %s", after1);
        
        if (before0 == 0 && before1 == 0) _setTransientValue(keccak256(abi.encodePacked("activeDelta")), 1);
        if (after0 == 0 && after1 == 0) _setTransientValue(keccak256(abi.encodePacked("activeDelta")), -1);

        require(_getTransientVariable(keccak256(abi.encodePacked("activeDelta"))) >= 0, "Invalid functions call order");
        console.log("Pool Transient : activeDelta: %s", _getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));
    }

    function _updateTokenTransientBalance(address token, int amount) public {
        (int before0, int after0) = _setTransientValue(keccak256(abi.encodePacked(token)), amount);

        if (before0 == 0) _setTransientValue(keccak256(abi.encodePacked("activeDelta")), 1);
        if (after0 == 0) _setTransientValue(keccak256(abi.encodePacked("activeDelta")), -1);

        require(_getTransientVariable(keccak256(abi.encodePacked("activeDelta"))) >= 0, "Invalid functions call order");
        console.log("Token Transient : activeDelta: %s", _getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));
    }

    function updateContractState(bytes32[] calldata poolsId) public {
        for (uint i = 0; i < poolsId.length; i++) {
            bytes32 poolId = poolsId[i];

            int amount0 = _getTransientVariable(keccak256(abi.encodePacked(poolId, pools[poolId].token0)));
            int amount1 = _getTransientVariable(keccak256(abi.encodePacked(poolId, pools[poolId].token1)));
            int liquidity = _getTransientVariable(keccak256(abi.encodePacked(poolId, msg.sender)));

            if (amount0 == 0 && amount1 == 0 && liquidity == 0) continue;

            Pool storage pool = pools[poolId];
            pool.reserve0 = uint(int(pool.reserve0) + amount0);
            pool.reserve1 = uint(int(pool.reserve1) + amount1);
            
            if (liquidity != 0) lp[poolId][msg.sender] = uint(int(lp[poolId][msg.sender]) + liquidity);

            _setTransientValue(keccak256(abi.encodePacked("activeDelta")), -1);
            require(_getTransientVariable(keccak256(abi.encodePacked("activeDelta"))) >= 0, "Invalid functions call order");
            console.log("Contract state : activeDelta: %s", _getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));
        }
    }

    function updateContractBalance(address[] calldata tokens) public {
        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            int amount = _getTransientVariable(keccak256(abi.encodePacked(token)));

            console.log("AMOUNT: %s", amount);

            if (amount == 0) {
                continue;
            }

            if (amount > 0) {
                _safeTransferFrom(token, msg.sender, address(this), uint(amount));
            } else {
                _safeTransfer(token, msg.sender, uint(amount));
            }

            _setTransientValue(keccak256(abi.encodePacked("activeDelta")), -1);
            require(_getTransientVariable(keccak256(abi.encodePacked("activeDelta"))) >= 0, "Invalid functions call order");
            console.log("Contract balance : activeDelta: %s", _getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));
        }
    }

    function addLiquidity(bytes32 poolId, uint amount0, uint amount1) external {
        Pool memory pool = pools[poolId];
        uint reserve0 = uint(int(pool.reserve0) + _getTransientVariable(keccak256(abi.encodePacked(poolId, pool.token0))));
        uint reserve1 = uint(int(pool.reserve1) + _getTransientVariable(keccak256(abi.encodePacked(poolId, pool.token1))));
        uint poolLiquidity = Math.sqrt(reserve0 * reserve1);
        console.log("Pool liquidity: %s", poolLiquidity);
        console.log("Reserve 0: %s", reserve0);
        console.log("Reserve 1: %s", reserve1);
        uint24 minimumLiquidity = poolLiquidity == 0 ? 1000 : 0;
        
        require(msg.sender != address(0), "Invalid address");
        require(pool.token0 != address(0), "Pool does not exist");
        require(amount0 > minimumLiquidity, "Pool: Invalid amount for token A");
        require(amount1 > minimumLiquidity, "Pool: Invalid amount for token B");

        {
            if (poolLiquidity != 0) {
                uint ratioA = amount0 * poolLiquidity / reserve0;
                uint ratioB = amount1 * poolLiquidity / reserve1;
                if (ratioB < ratioA) {
                    amount0 = amount1 * reserve0 / reserve1;
                } else {
                    amount1 = amount0 * reserve1 / reserve0;
                }
            }
        }
        
        _updatePoolTransientReserve(poolId, int(amount0), int(amount1), int(Math.sqrt(amount0 * amount1) - minimumLiquidity));
        _updateTokenTransientBalance(pool.token0, int(amount0));
        _updateTokenTransientBalance(pool.token1, int(amount1));
    }

    // function removeLiquidity(bytes32 poolId, uint liquidity) external {
    //     Pool memory pool = pools[poolId];
    //     uint reserve0 = uint(int(pool.reserve0) + _getTransientVariable(keccak256(abi.encodePacked(poolId, pool.token0))));
    //     uint reserve1 = uint(int(pool.reserve1) + _getTransientVariable(keccak256(abi.encodePacked(poolId, pool.token1))));
    //     uint poolLiquidity = Math.sqrt(reserve0 * reserve1);

    //     require(msg.sender != address(0), "Invalid address");
    //     require(pools[poolId].token0 != address(0), "Pool does not exist");
    //     require(liquidity <= pool[poolId][msg.sender], "Insufficient liquidity");

    //     uint amount0 = (liquidity * pool.reserve0) / poolLiquidity;
    //     uint amount1 = (liquidity * pool.reserve1) / poolLiquidity;

    //     require(amount0 < pool.reserve0, "Pool: Insufficient liquidity in pool");
    //     require(amount1 < pool.reserve1, "Pool: Insufficient liquidity in pool");

    //     _updatePoolTransientReserve(poolId, -int256(amount0), -int256(amount1), -int256(liquidity));
    //     _updateTokenTransientBalance(pool.token0, -int256(amount0));
    //     _updateTokenTransientBalance(pool.token1, -int256(amount1));
    // }

    // function getAmountIn(bytes32 id, uint reserveIn, uint reserveOut, uint amountOut) public view returns (uint amountIn) {
    //     Pool memory _pool = pools[id];
        
    //     uint numerator = reserveIn * amountOut * 1000;
    //     uint denominator = (reserveOut - amountOut) * (1000 - fee);
    //     amountIn = numerator / denominator;
    // }

    // function getAmountOut(bytes32 id, uint reserveIn, uint reserveOut, uint amountIn) public view returns (uint amountOut) {
    //     Pool memory _pool = pools[id];
    //     uint amountInWithFee = amountIn * fee / 1000;

    //     uint numerator = amountInWithFee * reserveOut;
    //     uint denominator = reserveIn + amountInWithFee;
    //     amountOut = numerator / denominator;
    // }

    // function swapWithInput(Pool memory pool, uint amountIn, uint minAmountOut, bool zeroForOne) public {
    //     bytes32 poolId = getPoolId(pool.token0, pool.token1);
    //     uint reserve0 = pool.reserve0 + _getTransientVariable(keccak256(abi.encodePacked(poolId, pool.token0)));
    //     uint reserve1 = pool.reserve1 + _getTransientVariable(keccak256(abi.encodePacked(poolId, pool.token1)));
    //     Pool memory _pool = pools[poolId];

    //     (uint reserveIn, uint reserveOut) = zeroForOne ? (reserve0, reserve1) : (reserve1, reserve0);

    //     require(_pool.token0 != address(0), "Pool does not exist");
    //     require(amountIn * fee > 0, "Pool: Input too small after fees");
        
    //     uint amountOut = getAmountOut(poolId, amountIn, reserveIn, reserveOut);

    //     require(amountOut >= minAmountOut, "Pool: Insufficient output amount");
    //     require(amountOut < reserveOut, "Pool: Insufficient liquidity in pool");

    //     _updatePoolTransientReserve(poolId, zeroForOne ? amountIn : amountOut, zeroForOne ? -int(amountOut) : -int(amountIn), 0);
    //     _updateTokenTransientBalance(zeroForOne ? pool.token0 : pool.token1, int(amountIn));
    //     _updateTokenTransientBalance(zeroForOne ? pool.token1 : pool.token0, -int(amountOut));
    // }

    // function swapWithOutput(Pool memory pool, uint amountOut, uint maxAmoutIn, bool zeroForOne) public {
    //     bytes32 poolId = getPoolId(pool.token0, pool.token1);
    //     uint reserve0 = pool.reserve0 + _getTransientVariable(keccak256(abi.encodePacked(poolId, pool.token0)));
    //     uint reserve1 = pool.reserve1 + _getTransientVariable(keccak256(abi.encodePacked(poolId, pool.token1)));
    //     Pool memory _pool = pools[poolId];

    //     (uint reserveIn, uint reserveOut) = zeroForOne ? (reserve0, reserve1) : (reserve1, reserve0);

    //     require(_pool.token0 != address(0), "Pool does not exist");
    //     require(amountOut < reserveOut, "Insufficient liquidity in pool");
        
    //     uint amountIn = getAmountIn(poolId, amountOut, reserveIn, reserveOut);
        
    //     require(amountIn <= maxAmoutIn, "Insufficient input amount");

    //     _updatePoolTransientReserve(poolId, zeroForOne ? amountIn : amountOut, zeroForOne ? -int(amountOut) : -int(amountIn), 0);
    //     _updateTokenTransientBalance(zeroForOne ? pool.token0 : pool.token1, int(amountIn));
    //     _updateTokenTransientBalance(zeroForOne ? pool.token1 : pool.token0, -int(amountOut));
    // }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) public {
        // console.log("from: %s", from);
        // console.log("transfer to: %s", to);
        // console.log("amount: %s", amount);
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
    }

    function _safeTransfer(address token, address to, uint256 amount) public {
        // console.log("from: %s", from);
        // console.log("to: %s", to);
        // console.log("amount: %s", amount);
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
    }
}
