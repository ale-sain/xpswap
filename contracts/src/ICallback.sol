// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICallback {
    function executeAll(uint256[] calldata actions, bytes[] calldata data) external;
}