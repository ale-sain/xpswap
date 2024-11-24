// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/XpswapPool.sol";
import "../src/XpswapERC20.sol";

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

contract NonStandardERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    // Non-standard transfer that doesn't return bool
    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    // Non-standard transferFrom that doesn't return bool
    function transferFrom(address from, address to, uint256 amount) external {
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        require(balanceOf[from] >= amount, "Insufficient balance");
        
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    // Non-standard approve that doesn't return bool
    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }
}

contract XpswapPoolTest is Test {
    XpswapPool public pool;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    NonStandardERC20 public nonStandardToken;
    
    address public user1;
    address public user2;
    
    function setUp() public {
        // Deploy standard tokens
        tokenA = new MockERC20("Token A", "TKNA", 18);
        tokenB = new MockERC20("Token B", "TKNB", 18);
        
        // Deploy non-standard token
        nonStandardToken = new NonStandardERC20("Non Standard", "NST", 18);
        
        // Deploy pool
        pool = new XpswapPool(address(tokenA), address(tokenB));
        
        // Setup test users
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Mint tokens to users
        tokenA.mint(user1, 1000000e18);
        tokenB.mint(user1, 1000000e18);
        tokenA.mint(user2, 1000000e18);
        tokenB.mint(user2, 1000000e18);
        
        // Approve pool to spend tokens
        vm.startPrank(user1);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
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
        
        assertEq(pool.reserveA(), amountA);
        assertEq(pool.reserveB(), amountB);
        assertEq(tokenA.balanceOf(user1), balanceABefore - amountA);
        assertEq(tokenB.balanceOf(user1), balanceBBefore - amountB);
        
        // Check LP tokens
        assertGt(pool.balanceOf(user1), 0);
        assertEq(pool.totalSupply(), pool.balanceOf(user1) + 1000); // Account for minimum liquidity
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
        assertEq(pool.balanceOf(user2), (lpBefore - 1000) / 2); // Subtract minimum liquidity
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
        
        uint balanceABefore = tokenA.balanceOf(user2);
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

    function testAddLiquidityWithNonStandardToken() public {
        // Deploy new pool with non-standard token
        XpswapPool nonStandardPool = new XpswapPool(
            address(nonStandardToken),
            address(tokenB)
        );
        
        // Setup non-standard token
        nonStandardToken.mint(user1, 1000000e18);
        
        vm.startPrank(user1);
        nonStandardToken.approve(address(nonStandardPool), type(uint256).max);
        tokenB.approve(address(nonStandardPool), type(uint256).max);
        
        // Should work despite non-standard return values
        nonStandardPool.addLiquidity(1000e18, 1000e18);
        
        assertEq(nonStandardPool.reserveA(), 1000e18);
        assertEq(nonStandardPool.reserveB(), 1000e18);
        vm.stopPrank();
    }

    // ========== REMOVE LIQUIDITY TESTS ==========

    function testRemoveLiquidity() public {
        // First add liquidity
        vm.startPrank(user1);
        pool.addLiquidity(1000e18, 1000e18);
        
        uint lpBalance = pool.balanceOf(user1);
        uint balanceABefore = tokenA.balanceOf(user1);
        uint balanceBBefore = tokenB.balanceOf(user1);
        
        // Remove half of liquidity
        pool.removeLiquidity(lpBalance / 2);
        
        // Check balances
        assertEq(pool.balanceOf(user1), lpBalance / 2);
        assertEq(tokenA.balanceOf(user1), balanceABefore + 500e18);
        assertEq(tokenB.balanceOf(user1), balanceBBefore + 500e18);
        vm.stopPrank();
    }

    function testFailRemoveLiquidityZeroAmount() public {
        vm.startPrank(user1);
        pool.addLiquidity(1000e18, 1000e18);
        pool.removeLiquidity(0);
        vm.stopPrank();
    }

    function testFailRemoveLiquidityInsufficientBalance() public {
        vm.startPrank(user1);
        pool.addLiquidity(1000e18, 1000e18);
        uint lpBalance = pool.balanceOf(user1);
        pool.removeLiquidity(lpBalance + 1);
        vm.stopPrank();
    }

    function testRemoveLiquidityWithNonStandardToken() public {
        // Deploy new pool with non-standard token
        XpswapPool nonStandardPool = new XpswapPool(
            address(nonStandardToken),
            address(tokenB)
        );
        
        vm.startPrank(user1);
        nonStandardToken.mint(user1, 1000000e18);
        nonStandardToken.approve(address(nonStandardPool), type(uint256).max);
        tokenB.approve(address(nonStandardPool), type(uint256).max);
        
        // Add liquidity first
        nonStandardPool.addLiquidity(1000e18, 1000e18);
        uint lpBalance = nonStandardPool.balanceOf(user1);
        
        // Remove liquidity should work despite non-standard returns
        nonStandardPool.removeLiquidity(lpBalance / 2);
        
        assertEq(nonStandardPool.balanceOf(user1), lpBalance / 2);
        vm.stopPrank();
    }

    function testFailRemoveAllLiquidity() public {
        vm.startPrank(user1);
        pool.addLiquidity(1000e18, 1000e18);
        uint lpBalance = pool.balanceOf(user1);
        // This should fail as it would remove all liquidity including the minimum
        pool.removeLiquidity(lpBalance + 1000);
        vm.stopPrank();
    }
}