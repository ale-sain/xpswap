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

    function testSwapWithOutput_ValidSwap() public {
        // User swaps for 50 tokens of tokenA
        uint256 outputAmount = 50 ether;
        uint256 initialBalanceA = tokenA.balanceOf(user);
        uint256 initialBalanceB = tokenB.balanceOf(user);

        vm.prank(user);
        pool.swapWithOutput(outputAmount, address(tokenA));

        // Check balances
        assertEq(tokenA.balanceOf(user), initialBalanceA + outputAmount, "Incorrect output token balance");
        assertTrue(tokenB.balanceOf(user) < initialBalanceB, "Input token balance should decrease");

        // Check reserves
        assertEq(pool.reserveA(), 500 ether - outputAmount, "Incorrect reserve for token A");
        assertTrue(pool.reserveB() > 500 ether, "Incorrect reserve for token B");
    }

    function testSwapWithOutput_ExceedsLiquidity() public {
        uint256 outputAmount = 600 ether; // Exceeds reserve of tokenA

        vm.expectRevert("Pool: Insufficient liquidity in pool");
        vm.prank(user);
        pool.swapWithOutput(outputAmount, address(tokenA));
    }

    function testSwapWithOutput_InvalidToken() public {
        address invalidToken = address(0xdead);

        vm.expectRevert("Pool: Invalid token address");
        vm.prank(user);
        pool.swapWithOutput(10 ether, invalidToken);
    }

    function testSwapWithOutput_CorrectFees() public {
        uint256 outputAmount = 100 ether;

        // Calculate expected input with fees
        uint256 reserveA = pool.reserveA();
        uint256 reserveB = pool.reserveB();
        uint256 numerator = outputAmount * reserveB * 1000;
        uint256 denominator = (reserveA - outputAmount) * (1000 - 3);
        uint256 expectedInput = numerator / denominator;

        vm.prank(user);
        pool.swapWithOutput(outputAmount, address(tokenA));

        // Check reserves
        assertEq(pool.reserveB(), reserveB + expectedInput, "Incorrect input reserve after fees");
        assertEq(pool.reserveA(), reserveA - outputAmount, "Incorrect output reserve");
    }

    function testSwapWithOutput_InsufficientInputProvided() public {
        uint256 outputAmount = 100 ether;

        // Set allowance less than required input
        vm.prank(user);
        tokenB.approve(address(pool), 1 ether);

        vm.expectRevert("Pool: Transfer failed");
        vm.prank(user);
        pool.swapWithOutput(outputAmount, address(tokenA));
    }

    function testSwapWithOutput_ExtremeValues() public {
        // Extreme values for outputAmount
        uint256 smallOutputAmount = 1 wei; // Smallest possible output
        uint256 largeOutputAmount = 10 ether; // Close to reserve size

        // Get reserves
        uint256 reserveA = pool.reserveA();
        uint256 reserveB = pool.reserveB();

        // Small output amount test
        {
            // Calculate expected input for small output
            uint256 smallNumerator = smallOutputAmount * reserveB * 1000;
            uint256 smallDenominator = (reserveA - smallOutputAmount) * (1000 - 3);
            uint256 expectedSmallInput = smallNumerator / smallDenominator;

            uint256 initialReserveB = reserveB;
            uint256 initialReserveA = reserveA;

            vm.prank(user);
            pool.swapWithOutput(smallOutputAmount, address(tokenA));

            // Check small output reserve updates
            assertEq(pool.reserveB(), initialReserveB + expectedSmallInput, "Incorrect input reserve for small output");
            assertEq(pool.reserveA(), initialReserveA - smallOutputAmount, "Incorrect output reserve for small output");
        }

        // Large output amount test
        {
            // Calculate expected input for large output
            uint256 largeNumerator = largeOutputAmount * reserveB * 1000;
            uint256 largeDenominator = (reserveA - largeOutputAmount) * (1000 - 3);
            uint256 expectedLargeInput = largeNumerator / largeDenominator;

            uint256 initialReserveB = reserveB;
            uint256 initialReserveA = reserveA;

            vm.prank(user);
            pool.swapWithOutput(largeOutputAmount, address(tokenA));

            // Check large output reserve updates
            assertEq(pool.reserveB() - 1 wei, initialReserveB + expectedLargeInput, "Incorrect input reserve for large output");
            assertEq(pool.reserveA() + 1 wei, initialReserveA - largeOutputAmount, "Incorrect output reserve for large output");
        }
    }

}
