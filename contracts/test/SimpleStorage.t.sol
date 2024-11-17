// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/SimpleStorage.sol";

contract SimpleStorageTest is Test {
    SimpleStorage private storageContract;

    // Set up the contract before tests
    function setUp() public {
        storageContract = new SimpleStorage();
    }

    // Test the default value of storedNumber
    function testDefaultStoredNumber() public view {
        uint256 number = storageContract.get();
        assertEq(number, 0, "Default value should be 0");
    }

    // Test the set function
    function testSetNumber() public {
        storageContract.set(42);
        uint256 number = storageContract.get();
        assertEq(number, 42, "Stored number should be 42");
    }
}
