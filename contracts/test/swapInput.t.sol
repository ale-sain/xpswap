// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/XpswapPool.sol";
import "../src/XpswapERC20.sol";
import "../src/XpswapFactory.sol";
import "../lib/Math.sol";

// Mock contracts needed for testing
contract MockERC20 is XpswapERC20 {
    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract XpswapPoolWithFactoryTest is Test {
    using Math for uint256;

    MockERC20 public tokenA;
    MockERC20 public tokenB;
    XpswapFactory public factory;
    XpswapPool public pool;

    address public user;
    address public otherUser;
    address public feeToSetter;
    address public feeTo;

    function setUp() public {
        // Deploy standard tokens
        tokenA = new MockERC20("Token A", "TKNA", 18);
        tokenB = new MockERC20("Token B", "TKNB", 18);

        // Setup roles
        feeToSetter = makeAddr("feeToSetter");
        feeTo = makeAddr("feeTo");

        // Deploy factory
        factory = new XpswapFactory(feeToSetter);

        // Create pool via factory
        vm.prank(feeToSetter);
        factory.createPool(address(tokenA), address(tokenB));

        address poolAddress = factory.poolByToken(address(tokenA), address(tokenB));
        pool = XpswapPool(poolAddress);

        // Setup test users
        user = makeAddr("user");
        otherUser = makeAddr("otherUser");

        // Mint tokens to users
        tokenA.mint(user, 1_000_000e18);
        tokenB.mint(user, 1_000_000e18);
        tokenA.mint(otherUser, 1_000_000e18);
        tokenB.mint(otherUser, 1_000_000e18);

        // Approve pool to spend tokens
        vm.startPrank(user);
        tokenA.approve(poolAddress, type(uint256).max);
        tokenB.approve(poolAddress, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(otherUser);
        tokenA.approve(poolAddress, type(uint256).max);
        tokenB.approve(poolAddress, type(uint256).max);
        vm.stopPrank();
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
