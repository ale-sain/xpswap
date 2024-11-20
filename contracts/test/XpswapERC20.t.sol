// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/XpswapERC20.sol";

contract testERC20 is XpswapERC20 {
    constructor() XpswapERC20() {
        _mint(msg.sender, 1000);
    }
}

contract XpswapERC20Test is Test {
    XpswapERC20 private token;

    address private alice = address(0x1);
    address private bob = address(0x2);
    address private carol = address(0x3);

    function setUp() public {
        vm.prank(alice);
        token = new testERC20();
    }

    function testInitialSupply() public view {
        assertEq(token.totalSupply(), 1000, "Initial supply should be 0");
    }

    function testMint() public view {
        assertEq(token.totalSupply(), 1000, "Total supply mismatch");
        assertEq(token.balanceOf(alice), 1000, "Balance mismatch for Alice");
    }

    function testTransfer() public {
        vm.prank(alice);
        uint256 transferAmount = 500;
        token.transfer(bob, transferAmount);

        assertEq(token.balanceOf(alice), 1000 - transferAmount, "Incorrect balance for Alice after transfer");
        assertEq(token.balanceOf(bob), transferAmount, "Incorrect balance for Bob after transfer");
    }

    function testApproveAndAllowance() public {
        vm.prank(alice);
        uint256 allowanceAmount = 300;
        token.approve(bob, allowanceAmount);

        assertEq(token.allowance(alice, bob), allowanceAmount, "Allowance mismatch");
    }

    function testTransferFrom() public {
        vm.prank(alice);
        uint256 allowanceAmount = 300;
        uint256 transferAmount = 200;
        token.approve(bob, allowanceAmount);

        vm.prank(bob);
        token.transferFrom(alice, carol, transferAmount);

        assertEq(token.balanceOf(alice), 1000 - transferAmount, "Incorrect balance for Alice after transferFrom");
        assertEq(token.balanceOf(carol), transferAmount, "Incorrect balance for Carol after transferFrom");
        assertEq(token.allowance(alice, bob), allowanceAmount - transferAmount, "Allowance not updated correctly");
    }

    function testTransferFromWithInfiniteAllowance() public {
        vm.prank(alice);
        uint256 transferAmount = 500;
        token.approve(bob, type(uint256).max); // Infinite allowance

        vm.prank(bob);
        token.transferFrom(alice, carol, transferAmount);

        assertEq(token.balanceOf(alice), 1000 - transferAmount, "Incorrect balance for Alice after transferFrom");
        assertEq(token.balanceOf(carol), transferAmount, "Incorrect balance for Carol after transferFrom");
        assertEq(token.allowance(alice, bob), type(uint256).max, "Infinite allowance should not decrement");
    }

    function testTransferFailsWhenInsufficientBalance() public {
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        token.transfer(bob, 2000);
    }

    function testTransferFromFailsWhenAllowanceIsLow() public {
        uint256 allowanceAmount = 200;
        uint256 transferAmount = 300;

        vm.prank(alice);
        token.approve(bob, allowanceAmount);

        vm.prank(bob);
        vm.expectRevert("ERC20: Insufficient allowance");
        token.transferFrom(alice, carol, transferAmount);
    }
}
