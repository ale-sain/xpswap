// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {XpswapPool} from "../src/XpswapPool.sol";
import {XpswapERC20} from "../src/XpswapERC20.sol";
import {IERC20} from "../interfaces/IERC20.sol";

// Mock contracts needed for testing
contract MockERC20 is XpswapERC20 {
    constructor() {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract XpswapPoolTest is Test {
    XpswapPool public pool;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address user = address(0x123);
    address otherUser = address(0x456);

    function setUp() public {
        tokenA = new MockERC20();
        tokenB = new MockERC20();
        pool = new XpswapPool(address(tokenA), address(tokenB));

        // Mint some tokens to users
        tokenA.mint(user, type(uint256).max / 2);
        tokenB.mint(user, 10000000 ether);
        tokenA.mint(otherUser, type(uint256).max / 2);
        tokenB.mint(otherUser, 10000000 ether);

        vm.startPrank(user);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(otherUser);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        // Add liquidity
        vm.prank(otherUser);
        pool.addLiquidity(1000 ether, 1000 ether);
    }

    // Test: Swap with valid input amount
    function testSwapWithValidInput() public {
        vm.startPrank(user);

        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 90 ether;

        uint256 initialBalanceA = tokenA.balanceOf(user);
        uint256 initialBalanceB = tokenB.balanceOf(user);

        pool.swapWithInput(inputAmount, minOutputAmount, address(tokenA));

        uint256 finalBalanceA = tokenA.balanceOf(user);
        uint256 finalBalanceB = tokenB.balanceOf(user);

        assertEq(finalBalanceA, initialBalanceA - inputAmount, "balance A final");
        assertGt(finalBalanceB, initialBalanceB, "balance B"); // Ensure the user received tokens

        vm.stopPrank();
    }

    // Test: Swap with invalid token address
    function testSwapWithInvalidToken() public {
        vm.startPrank(user);

        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 90 ether;
        
        // Trying to swap with a token address that is not in the pool
        vm.expectRevert("Pool: Invalid token address");
        pool.swapWithInput(inputAmount, minOutputAmount, address(0x999));

        vm.stopPrank();
    }

    // Test: Swap with zero input amount
    function testSwapWithZeroInput() public {
        vm.startPrank(user);

        uint256 inputAmount = 0;
        uint256 minOutputAmount = 90 ether;

        vm.expectRevert("Pool: Invalid input amount");
        pool.swapWithInput(inputAmount, minOutputAmount, address(tokenA));

        vm.stopPrank();
    }

    // Test: Division by zero or rounding errors in swap calculations
    function testSwapWithEdgeCases() public {
        vm.startPrank(user);

        uint256 inputAmount = 1 ether; // very small amount
        uint256 minOutputAmount = 0.98 ether;

        uint256 initialBalanceA = tokenA.balanceOf(user);
        uint256 initialBalanceB = tokenB.balanceOf(user);

        pool.swapWithInput(inputAmount, minOutputAmount, address(tokenA));

        uint256 finalBalanceA = tokenA.balanceOf(user);
        uint256 finalBalanceB = tokenB.balanceOf(user);

        assertEq(finalBalanceA, initialBalanceA - inputAmount);
        assertGt(finalBalanceB, initialBalanceB); // Ensure the user received tokens

        vm.stopPrank();
    }

    // Test: Swap with a large value (potential overflow case)
    function testSwapWithLargeValues() public {
        vm.startPrank(user);

        uint256 inputAmount = 100000 ether;
        uint256 minOutputAmount = 900 ether;

        uint256 initialBalanceA = tokenA.balanceOf(user);
        uint256 initialBalanceB = tokenB.balanceOf(user);

        pool.swapWithInput(inputAmount, minOutputAmount, address(tokenA));

        uint256 finalBalanceA = tokenA.balanceOf(user);
        uint256 finalBalanceB = tokenB.balanceOf(user);

        assertEq(finalBalanceA, initialBalanceA - inputAmount);
        assertGt(finalBalanceB, initialBalanceB); // Ensure the user received tokens

        vm.stopPrank();
    }

    // Test: Edge case with very large and very small amounts
    function testSwapWithExtremeValues() public {
        vm.startPrank(user);

        uint256 smallAmount = 1 ether;
        uint256 largeAmount = 1000000 ether;

        uint256 initialBalanceA = tokenA.balanceOf(user);
        uint256 initialBalanceB = tokenB.balanceOf(user);

        pool.swapWithInput(smallAmount, 0.98 ether, address(tokenA));
        pool.swapWithInput(largeAmount, 900 ether, address(tokenA));

        uint256 finalBalanceA = tokenA.balanceOf(user);
        uint256 finalBalanceB = tokenB.balanceOf(user);

        assertEq(finalBalanceA, initialBalanceA - smallAmount - largeAmount);
        assertGt(finalBalanceB, initialBalanceB); // Ensure the user received tokens

        vm.stopPrank();
    }

    // Test: Swap with fees correctly applied
    function testSwapWithFees() public {
        vm.startPrank(user);

        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 90 ether;

        uint256 initialBalanceA = tokenA.balanceOf(user);
        uint256 initialBalanceB = tokenB.balanceOf(user);

        pool.swapWithInput(inputAmount, minOutputAmount, address(tokenA));

        uint256 finalBalanceA = tokenA.balanceOf(user);
        uint256 finalBalanceB = tokenB.balanceOf(user);

        // Ensure the swap took place with fees applied correctly
        assertEq(finalBalanceA, initialBalanceA - inputAmount);
        assertGt(finalBalanceB, initialBalanceB); // Ensure the user received tokens

        vm.stopPrank();
    }

    // Test: Pool doesn't have enough reserves for a swap
    function testSwapWithInsufficientReserves() public {
        vm.startPrank(otherUser);
        
        uint256 inputAmount = 100000 ether;
        uint256 minOutputAmount = 90 ether;

        // Remove all liquidity to empty the pool
        pool.removeLiquidity(900 ether);

        // Trying to swap with an empty pool
        pool.swapWithInput(inputAmount, minOutputAmount, address(tokenA));

        vm.stopPrank();
    }
}
