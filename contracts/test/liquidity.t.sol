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

    address public user1;
    address public user2;
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
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Mint tokens to users
        tokenA.mint(user1, 1_000_000e18);
        tokenB.mint(user1, 1_000_000e18);
        tokenA.mint(user2, 1_000_000e18);
        tokenB.mint(user2, 1_000_000e18);

        // Approve pool to spend tokens
        vm.startPrank(user1);
        tokenA.approve(poolAddress, type(uint256).max);
        tokenB.approve(poolAddress, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        tokenA.approve(poolAddress, type(uint256).max);
        tokenB.approve(poolAddress, type(uint256).max);
        vm.stopPrank();
    }

    // ========== ADD LIQUIDITY TESTS ==========

    function testInitialLiquidity() public {
        vm.startPrank(user1);
        uint amountA = 1000e18;
        uint amountB = 1000e18;
        
        uint balanceABefore = tokenA.balanceOf(user1);
        uint balanceBBefore = tokenB.balanceOf(user1);
        
        pool.addLiquidity(amountA, amountB);
        
        assertEq(pool.reserveA(), amountA, "reserve A");
        assertEq(pool.reserveB(), amountB, "reserve B");
        assertEq(tokenA.balanceOf(user1), balanceABefore - amountA, "balance token A user 1");
        assertEq(tokenB.balanceOf(user1), balanceBBefore - amountB, "balance token B user 2");
        
        // Check LP tokens
        assertGt(pool.balanceOf(user1), 0, "balance token LP user 1");
        assertEq(pool.totalSupply(), pool.balanceOf(user1) + 1000, "min liquidity"); // Account for minimum liquidity
        vm.stopPrank();
    }

    function testAddLiquidityProportional() public {
        // First add initial liquidity
        vm.startPrank(user1);
        pool.addLiquidity(1000e18, 1000e18);
        vm.stopPrank();
        
        // Second user adds proportional liquidity
        vm.startPrank(user2);
        uint amountA = 500e18;
        uint amountB = 500e18;
        
        uint lpBefore = pool.totalSupply();
        pool.addLiquidity(amountA, amountB);
        
        // Check that LP tokens are minted proportionally
        assertEq(pool.balanceOf(user2), lpBefore / 2); // Subtract minimum liquidity
        vm.stopPrank();
    }

    function testAddLiquidityImbalanced() public {
        // First add initial liquidity
        vm.startPrank(user1);
        pool.addLiquidity(1000e18, 1000e18);
        vm.stopPrank();
        
        // Try to add imbalanced liquidity
        vm.startPrank(user2);
        uint amountA = 500e18;
        uint amountB = 600e18; // More of token B
        
        uint balanceBBefore = tokenB.balanceOf(user2);
        
        pool.addLiquidity(amountA, amountB);
        
        // Check that excess tokens were refunded
        assertEq(tokenB.balanceOf(user2), balanceBBefore - 500e18); // Only 500 should be taken
        vm.stopPrank();
    }

    function testFailAddLiquidityZeroAmount() public {
        vm.startPrank(user1);
        pool.addLiquidity(0, 1000e18);
        vm.stopPrank();
    }

    function testFailAddLiquidityInsufficientAllowance() public {
        vm.startPrank(user1);
        tokenA.approve(address(pool), 0);
        pool.addLiquidity(1000e18, 1000e18);
        vm.stopPrank();
    }

    // ========== REMOVE LIQUIDITY TESTS ==========

    function testRemoveLiquidity() public {
        // First add liquidity
        vm.startPrank(user1);
        pool.addLiquidity(1000e18, 1000e18);

        uint lpBalance = pool.balanceOf(user1);
        uint totalSupply = pool.totalSupply();
        uint balanceABefore = tokenA.balanceOf(user1);
        uint balanceBBefore = tokenB.balanceOf(user1);

        // Remove half of the user's liquidity
        pool.removeLiquidity(lpBalance / 2);

        // Calculate expected token amounts based on the adjusted proportion of liquidity removed
        uint tokenAWithdrawn = (1000e18 * (lpBalance / 2) * 1e18) / totalSupply / 1e18;
        uint tokenBWithdrawn = (1000e18 * (lpBalance / 2) * 1e18) / totalSupply / 1e18;

        // Check balances
        assertEq(pool.balanceOf(user1), lpBalance / 2, "Remaining LP balance of user1");
        assertEq(
            tokenA.balanceOf(user1),
            balanceABefore + tokenAWithdrawn,
            "Token A balance of user1 after removing liquidity"
        );
        assertEq(
            tokenB.balanceOf(user1),
            balanceBBefore + tokenBWithdrawn,
            "Token B balance of user1 after removing liquidity"
        );

        vm.stopPrank();
    }


    function testFailRemoveLiquidityZeroAmount() public {
        vm.startPrank(user1);
        pool.addLiquidity(1000e18, 1000e18);
        pool.removeLiquidity(0); // Should fail since removing 0 liquidity is invalid
        vm.stopPrank();
    }


    function testRemoveLiquidityInsufficientBalance() public {
        vm.startPrank(user1);
        pool.addLiquidity(1000e18, 1000e18);
        uint lpBalance = pool.balanceOf(user1);

        vm.expectRevert("Pool: Insufficient LP balance");
        pool.removeLiquidity(lpBalance + 1); // Should fail as the user doesn't own this much liquidity
        vm.stopPrank();
    }

    function testRemoveAllLiquidity() public {
        vm.startPrank(user1);
        pool.addLiquidity(1000e18, 1000e18);
        uint lpBalance = pool.balanceOf(user1);

        vm.expectRevert("Pool: Insufficient LP balance");
        pool.removeLiquidity(lpBalance + 500);
        vm.stopPrank();
    }
}