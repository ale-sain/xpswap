// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExchangeLogic {
    function exchangeLogic(bytes calldata data) external;
}

contract V4Router {
    address public immutable poolManager;

    constructor(address _poolManager) {
        require(_poolManager != address(0), "Invalid PoolManager address");
        poolManager = _poolManager;
    }

    function unlockAndExecute(uint256[] calldata actions, bytes[] calldata data) external payable {
        require(actions.length == data.length, "Mismatched actions and arguments length");

        // Débloquer le poolManager
        (bool success, bytes memory returnData) = poolManager.call(
            abi.encodeWithSignature("unlock(bytes)", abi.encodePacked(actions, data))
        );
        require(success, "Unlock failed");
    }

    function executeAction(uint256 action, bytes memory data) public {
        bytes4 selector;

        if (action == 1) {
            // addLiquidity(bytes32 poolId, uint amount0, uint amount1)
            selector = bytes4(keccak256("addLiquidity(bytes32,uint256,uint256)"));
        } else if (action == 2) {
            // removeLiquidity(bytes32 poolId, uint liquidity)
            selector = bytes4(keccak256("removeLiquidity(bytes32,uint256)"));
        } else if (action == 3) {
            // swapWithInput(bytes32 poolId, uint amountIn, uint minAmountOut, bool zeroForOne)
            selector = bytes4(keccak256("swapWithInput(bytes32,uint256,uint256,bool)"));
        } else if (action == 4) {
            // swapWithOutput(bytes32 poolId, uint amountOut, uint maxAmountIn, bool zeroForOne)
            selector = bytes4(keccak256("swapWithOutput(bytes32,uint256,uint256,bool)"));
        } else {
            revert("Unsupported action");
        }

        // Exécuter l'action sur le PoolManager
        (bool success, bytes memory returnData) = poolManager.call(abi.encodePacked(selector, data));
        require(success, "Action execution failed");
    }

    function batchExecute(uint256[] calldata actions, bytes[] calldata data) external payable {
        require(actions.length == data.length, "Mismatched actions and arguments length");

        for (uint256 i = 0; i < actions.length; i++) {
            executeAction(actions[i], data[i]);
        }
    }

    function getPoolManager() external view returns (address) {
        return poolManager;
    }
}
