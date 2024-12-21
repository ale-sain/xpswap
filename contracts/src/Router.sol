// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICallback {
    function executeAll(uint256[] calldata actions, bytes[] calldata data) external;
}

contract V4Router {
    address public immutable poolManager;

    enum Action {
        AddLiquidity,
        RemoveLiquidity,
        SwapWithInput,
        SwapWithOutput,
        UpdateContractState,
        UpdateContractBalance
    }

    constructor(address _poolManager) {
        require(_poolManager != address(0), "Invalid PoolManager address");
        poolManager = _poolManager;
    }

    function unlockAndExecuteAll(uint256[] calldata actions, bytes[] calldata data) external payable {
        require(actions.length == data.length, "Mismatched actions and arguments length");

        (bool success, ) = poolManager.call(abi.encodeWithSignature("unlock(uint256[],bytes[])", actions, data));
        require(success, "Unlock failed");
    }

    function executeAction(Action action, bytes memory data) public {
        bytes4 selector;

        if (action == Action.AddLiquidity) selector = bytes4(keccak256("addLiquidity(bytes32,uint256,uint256)"));
        else if (action == Action.RemoveLiquidity) selector = bytes4(keccak256("removeLiquidity(bytes32,uint256)"));
        else if (action == Action.SwapWithInput) selector = bytes4(keccak256("swapWithInput(bytes32,uint256,uint256,bool)"));
        else if (action == Action.SwapWithOutput) selector = bytes4(keccak256("swapWithOutput(bytes32,uint256,uint256,bool)"));
        else if (action == Action.UpdateContractState) selector = bytes4(keccak256("updateContractState(bytes32[])"));
        else if (action == Action.UpdateContractBalance) selector = bytes4(keccak256("updateContractBalance(address[])"));
        else revert("Unsupported action");

        (bool success, ) = poolManager.call(abi.encodePacked(selector, data));
        require(success, "Action execution failed");
    }

    function executeAll(uint256[] calldata actions, bytes[] calldata data) external payable {
        require(actions.length == data.length, "Mismatched actions and arguments length");

        for (uint256 i = 0; i < actions.length; i++) {
            executeAction(Action(actions[i]), data[i]);
        }
    }

    function getPoolManager() external view returns (address) {
        return poolManager;
    }
}
