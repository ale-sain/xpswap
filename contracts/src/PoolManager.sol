// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "forge-std/console.sol";
import {ICallback} from "./ICallback.sol";

contract PoolManager is ReentrancyGuard {
    bool private lock = true;
    uint24 public fee = 3;

    struct Pool {
        address token0;
        address token1;
        uint reserve0;
        uint reserve1;
    }

    mapping(bytes32 => Pool) public pools;
    mapping(bytes32 => mapping(address => uint)) public lp;

    constructor() {}

    function unlock(uint256[] calldata actions, bytes[] calldata data) public {
        // console.log("Wants to unlock");
        require(lock == true, "Contract already in unlocked");
        
        // console.log("Unlocking...");
        lock = false;
        ICallback(msg.sender).executeAll(actions, data);
        lock = true;

        // console.log("Done and going to check");
        require(_getTransientVariable(_getTransientKey(abi.encodePacked("activeDelta"))) == 0, "Unprocessed transactions");
        // console.log("Checked");
    }

    modifier onlyUnlocked() {
        require(lock == false, "Contract locked");
        _;
    }

    function abs(int256 value) internal pure returns (uint256) {
        return value < 0 ? uint256(-value) : uint256(value);
    }

    function createPool(address token0, address token1) external onlyUnlocked returns (bytes32 poolId) {
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

        // console.log("Pool created : token0_: %s, token1_ : %s", token0_, token1_);
        // console.log("token0 < token1? ", token0 < token1);
    }

    function getPoolId(address token0, address token1) public pure returns (bytes32 poolId) {
        (address _token0, address _token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        poolId = keccak256(abi.encodePacked(_token0, _token1));
        // if (!pools[poolId])
        //     return 0;
    }

    function _setTransientValue(bytes32 key, int value) private returns (int beforeValue, int afterValue) {
        assembly {
            beforeValue := tload(key)
            afterValue := add(beforeValue, value)
            tstore(key, afterValue)
        }
    }

    function _getTransientKey(bytes memory variableId) private view returns (bytes32 key) {
        key = keccak256(
            abi.encodePacked(
                variableId,
                block.timestamp,
                blockhash(block.number - 1)
            )
        );
    }

    function _getTransientVariable(bytes32 key) private view returns (int256 value) {
        assembly {
            value := tload(key)
        }
    }

    function _updatePoolTransientReserve(bytes32 poolId, int amount0, int amount1, int liquidity) private {
        Pool memory pool = pools[poolId];

        if (liquidity != 0) _setTransientValue(_getTransientKey(abi.encodePacked(poolId, msg.sender)), liquidity);
        
        (int before0, int after0) = _setTransientValue(_getTransientKey(abi.encodePacked(poolId, pool.token0)), amount0);
        (int before1, int after1) = _setTransientValue(_getTransientKey(abi.encodePacked(poolId, pool.token1)), amount1);
        
        if (before0 == 0 && before1 == 0) _setTransientValue(_getTransientKey(abi.encodePacked("activeDelta")), 1);
        if (after0 == 0 && after1 == 0) _setTransientValue(_getTransientKey(abi.encodePacked("activeDelta")), -1);

        require(_getTransientVariable(_getTransientKey(abi.encodePacked("activeDelta"))) >= 0, "Invalid functions call order");
    }

    function _updateTokenTransientBalance(address token, int amount) private {
        (int before0, int after0) = _setTransientValue(_getTransientKey(abi.encodePacked(token)), amount);

        if (before0 == 0) _setTransientValue(_getTransientKey(abi.encodePacked("activeDelta")), 1);
        if (after0 == 0) _setTransientValue(_getTransientKey(abi.encodePacked("activeDelta")), -1);

        require(_getTransientVariable(_getTransientKey(abi.encodePacked("activeDelta"))) >= 0, "Invalid functions call order");
    }

    function updateContractState(address sender, bytes32[] calldata poolsId) public onlyUnlocked {
        for (uint i = 0; i < poolsId.length; i++) {
            bytes32 poolId = poolsId[i];

            int amount0 = _getTransientVariable(_getTransientKey(abi.encodePacked(poolId, pools[poolId].token0)));
            int amount1 = _getTransientVariable(_getTransientKey(abi.encodePacked(poolId, pools[poolId].token1)));
            int liquidity = _getTransientVariable(_getTransientKey(abi.encodePacked(poolId, sender)));

            if (amount0 == 0 && amount1 == 0 && liquidity == 0) continue;

            Pool storage pool = pools[poolId];
            pool.reserve0 = uint(int(pool.reserve0) + amount0);
            pool.reserve1 = uint(int(pool.reserve1) + amount1);
            
            if (liquidity != 0) lp[poolId][sender] = uint(int(lp[poolId][sender]) + liquidity);

            _setTransientValue(_getTransientKey(abi.encodePacked("activeDelta")), -1);
            require(_getTransientVariable(_getTransientKey(abi.encodePacked("activeDelta"))) >= 0, "Invalid functions call order");
            // console.log("Contract state : activeDelta: %s", _getTransientVariable(_getTransientKey(abi.encodePacked("activeDelta"))));
        }
    }

    function updateContractBalance(address sender, address[] calldata tokens) public onlyUnlocked {
        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            int amount = _getTransientVariable(_getTransientKey(abi.encodePacked(token)));

            if (amount == 0) {
                continue;
            }

            if (amount > 0) {
                _safeTransferFrom(token, sender, address(this), abs(amount));
                console.log("Transfer from %s to %s, amount: %s", sender, address(this), abs(amount));
                console.log("Contract balance : %s", IERC20(token).balanceOf(address(this)));
            } else {
                _safeTransfer(token, sender, abs(amount));
                console.log("Transfer to %s from %s, amount: %s", sender, address(this), abs(amount));
            }

            _setTransientValue(_getTransientKey(abi.encodePacked("activeDelta")), -1);
            require(_getTransientVariable(_getTransientKey(abi.encodePacked("activeDelta"))) >= 0, "Invalid functions call order");
            // console.log("Contract balance : activeDelta: %s", _getTransientVariable(_getTransientKey(abi.encodePacked("activeDelta"))));
        }
    }

    function addLiquidity(address sender, bytes32 poolId, uint amount0, uint amount1) external onlyUnlocked {
        Pool memory pool = pools[poolId];
        uint reserve0 = uint(int(pool.reserve0) + _getTransientVariable(_getTransientKey(abi.encodePacked(poolId, pool.token0))));
        uint reserve1 = uint(int(pool.reserve1) + _getTransientVariable(_getTransientKey(abi.encodePacked(poolId, pool.token1))));
        uint poolLiquidity = Math.sqrt(reserve0 * reserve1);
        // console.log("Add Liquidity Pool liquidity: %s", poolLiquidity);
        // console.log("Reserve 0: %s", reserve0);
        // console.log("Reserve 1: %s", reserve1);
        uint24 minimumLiquidity = poolLiquidity == 0 ? 1000 : 0;
        
        require(sender != address(0), "Invalid address");
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

    function removeLiquidity(address sender, bytes32 poolId, uint liquidity) external onlyUnlocked {
        Pool memory pool = pools[poolId];
        uint reserve0 = uint(int(pool.reserve0) + _getTransientVariable(_getTransientKey(abi.encodePacked(poolId, pool.token0))));
        uint reserve1 = uint(int(pool.reserve1) + _getTransientVariable(_getTransientKey(abi.encodePacked(poolId, pool.token1))));
        uint userLiquidity = uint(int(lp[poolId][sender]) + _getTransientVariable(_getTransientKey(abi.encodePacked(poolId, sender))));
        uint poolLiquidity = Math.sqrt(reserve0 * reserve1);
        // console.log("Remove Liquidity Pool liquidity: %s", poolLiquidity);
        // console.log("Reserve 0: %s", reserve0);
        // console.log("Reserve 1: %s", reserve1);
        // console.log("To remove: %s", liquidity);
        // console.log("User liquidity: %s", userLiquidity);

        require(liquidity > 0, "Invalid liquidity amount"); 
        require(pools[poolId].token0 != address(0), "Pool does not exist");
        require(liquidity <= userLiquidity, "Insufficient liquidity");

        uint amount0 = (liquidity * reserve0) / poolLiquidity;
        uint amount1 = (liquidity * reserve1) / poolLiquidity;

        // console.log("Amount 0: %s", amount0);
        // console.log("Amount 1: %s", amount1);

        require(amount0 < reserve0, "Pool: Insufficient liquidity in pool");
        require(amount1 < reserve1, "Pool: Insufficient liquidity in pool");

        _updatePoolTransientReserve(poolId, -int(amount0), -int(amount1), -int(liquidity));
        _updateTokenTransientBalance(pool.token0, -int(amount0));
        _updateTokenTransientBalance(pool.token1, -int(amount1));
    }

    function getAmountIn(uint reserveIn, uint reserveOut, uint amountOut) public view returns (uint amountIn) {
        uint numerator = reserveIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * (1000 - fee);
        amountIn = numerator / denominator;
    }

    function getAmountOut(uint reserveIn, uint reserveOut, uint amountIn) public view returns (uint amountOut) {
        uint amountInWithFee = amountIn * (1000 - fee) / 1000;

        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function swapWithInput(bytes32 poolId, uint amountIn, uint minAmountOut, bool zeroForOne) public onlyUnlocked {
        Pool memory pool = pools[poolId];
        uint reserve0 = uint(int(pool.reserve0) + _getTransientVariable(_getTransientKey(abi.encodePacked(poolId, pool.token0))));
        uint reserve1 = uint(int(pool.reserve1) + _getTransientVariable(_getTransientKey(abi.encodePacked(poolId, pool.token1))));

        // console.log("minAmountOut: %s", minAmountOut);
        (uint reserveIn, uint reserveOut) = zeroForOne ? (reserve0, reserve1) : (reserve1, reserve0);

        require(pool.token0 != address(0), "Pool does not exist");
        require(amountIn * (1000 - fee) / 1000 > 0, "Pool: Invalid input amount");
        
        uint amountOut = getAmountOut(reserveIn, reserveOut, amountIn);

        // console.log("Amount In: %s", amountIn);
        // console.log("Token In: %s", zeroForOne ? pool.token0 : pool.token1);

        // console.log("Amount Out: %s", amountOut);
        // console.log("Token Out: %s", zeroForOne ? pool.token1 : pool.token0);

        // console.log("Reserve In: %s", reserveIn);
        // console.log("Reserve Out: %s", reserveOut);
        
        require(amountOut >= minAmountOut, "Pool: Insufficient output amount");
        require(amountOut < reserveOut, "Pool: Insufficient liquidity in pool");

        _updatePoolTransientReserve(poolId, zeroForOne ? int(amountIn) : -int(amountOut), zeroForOne ? -int(amountOut) : int(amountIn), 0);
        _updateTokenTransientBalance(zeroForOne ? pool.token0 : pool.token1, int(amountIn));
        _updateTokenTransientBalance(zeroForOne ? pool.token1 : pool.token0, -int(amountOut));
    }

    function swapWithOutput(bytes32 poolId, uint amountOut, uint maxAmountIn, bool zeroForOne) public onlyUnlocked {
        Pool memory pool = pools[poolId];
        uint reserve0 = uint(int(pool.reserve0) + _getTransientVariable(_getTransientKey(abi.encodePacked(poolId, pool.token0))));
        uint reserve1 = uint(int(pool.reserve1) + _getTransientVariable(_getTransientKey(abi.encodePacked(poolId, pool.token1))));

        (uint reserveIn, uint reserveOut) = zeroForOne ? (reserve0, reserve1) : (reserve1, reserve0);

        require(pool.token0 != address(0), "Pool does not exist");
        require(amountOut < reserveOut, "Insufficient liquidity in pool");
        
        uint amountIn = getAmountIn(reserveIn, reserveOut, amountOut);

        // console.log("Amount In: %s", amountIn);
        // console.log("maxAmountIn: %s", maxAmountIn);
        // console.log("Token In: %s", zeroForOne ? pool.token0 : pool.token1);

        // console.log("Amount Out: %s", amountOut);
        // console.log("Token Out: %s", zeroForOne ? pool.token1 : pool.token0);

        // console.log("Reserve In: %s", reserveIn);
        // console.log("Reserve Out: %s", reserveOut);
    
        
        require(amountIn <= maxAmountIn, "Insufficient input amount");

        _updatePoolTransientReserve(poolId, zeroForOne ? int(amountIn) : -int(amountOut), zeroForOne ? -int(amountOut) : int(amountIn), 0);
        _updateTokenTransientBalance(zeroForOne ? pool.token0 : pool.token1, int(amountIn));
        _updateTokenTransientBalance(zeroForOne ? pool.token1 : pool.token0, -int(amountOut));
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
