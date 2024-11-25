// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/XpswapPool.sol";
import "../src/XpswapERC20.sol";
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

pragma solidity ^0.8.0;

contract FeeOnTransferToken {
    using Math for uint256;
    string public name = "Fee Token";
    string public symbol = "FEE";
    uint8 public decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint256 public feePercentage; // Fee in basis points (e.g., 100 = 1%)
    address public feeRecipient;

    constructor(uint256 _feePercentage, address _feeRecipient) {
        require(_feePercentage <= 1000, "Fee too high"); // Maximum 10%
        feePercentage = _feePercentage;
        feeRecipient = _feeRecipient;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 fee = (amount * feePercentage) / 10000;
        uint256 amountAfterFee = amount - fee;

        require(balanceOf[msg.sender] >= amount, "Insufficient balance");

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amountAfterFee;
        balanceOf[feeRecipient] += fee;

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 fee = (amount * feePercentage) / 10000;
        uint256 amountAfterFee = amount - fee;

        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amountAfterFee;
        balanceOf[feeRecipient] += fee;

        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
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
    using Math for uint256;
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

    function testAddLiquidityWithFeeToken() public {
        // Deploy fee-on-transfer token et pool avec le token
        FeeOnTransferToken feeToken = new FeeOnTransferToken(300, address(this)); // 3% fee
        XpswapPool feePool = new XpswapPool(address(feeToken), address(tokenB));

        // Mint et approbation des tokens
        vm.startPrank(user1);
        feeToken.mint(user1, 1000000e18);
        tokenB.mint(user1, 1000000e18);

        feeToken.approve(address(feePool), type(uint256).max);
        tokenB.approve(address(feePool), type(uint256).max);

        // Ajout de liquidité
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;

        feePool.addLiquidity(amountA, amountB);

        // Vérification des balances après l'ajout de liquidité
        uint256 lpBalance = feePool.balanceOf(user1);
        uint256 feeTokenAfter = feeToken.balanceOf(user1);

        // Calculs attendus
        uint256 feeOnA = (amountA * 3) / 100; // 3% de frais sur token A
        uint256 netAmountA = amountA - feeOnA; // Montant net de token A ajouté au pool
        uint256 netAmountB = amountB; // Pas de frais pour token B

        // LP tokens totaux attendus
        uint256 totalLpMinted = (netAmountA * netAmountB).sqrt();

        // LP tokens attribués à l'utilisateur (après soustraction de 1 000 pour la pool)
        uint256 expectedUserLp = totalLpMinted - 1000;

        // Assertions
        assertEq(feeTokenAfter, 1000000e18 - amountA, "Fee token balance user1 after liquidity addition");
        assertEq(
            feeToken.balanceOf(address(feePool)),
            netAmountA,
            "Fee token balance pool after liquidity addition"
        );
        assertEq(
            lpBalance,
            expectedUserLp,
            "LP tokens balance for user1 after liquidity addition"
        );

        vm.stopPrank();
    }

    function testRemoveLiquidityWithFeeToken() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken(300, address(this)); // 3% fee
        XpswapPool feePool = new XpswapPool(address(feeToken), address(tokenB));
        vm.startPrank(user1);
        feeToken.mint(user1, 1000000e18);

        feeToken.approve(address(feePool), type(uint256).max);
        tokenB.approve(address(feePool), type(uint256).max);

        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;

        uint quantB = tokenB.balanceOf(user1);
        assertEq(quantB, 1000000e18 , "Token B a");

        feePool.addLiquidity(amountA, amountB);

        uint tokenRec = feeToken.balanceOf(address(feePool));
        // Vérification des balances après l'ajout de liquidité
        uint256 lpBalance = feePool.balanceOf(user1);

        quantB = tokenB.balanceOf(user1);
        assertEq(quantB, 1000000e18 - 1000e18, "Token B b");

        //<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
        
        uint totalSupply = feePool.totalSupply();
        uint tokenAWithdrawn = (tokenRec * (lpBalance / 2) * 1e18) / totalSupply / 1e18;
        uint tokenBWithdrawn = (1000e18 * (lpBalance / 2) * 1e18) / totalSupply / 1e18;

        // Retirer la moitié de la liquidité
        feePool.removeLiquidity(lpBalance / 2);

        // Vérification des balances après le retrait de liquidité
        uint256 tokenARemoved = feeToken.balanceOf(user1);
        uint256 tokenBRemoved = tokenB.balanceOf(user1);
        
        assertEq(tokenBRemoved, 1000000e18 - 1000e18 + tokenBWithdrawn, "Token B balance after liquidity removal");

        // Vérifier les LP tokens restants
        uint256 remainingLpBalance = feePool.balanceOf(user1);
        assertEq(remainingLpBalance, lpBalance / 2, "Remaining LP balance of user1");

        assertEq(tokenARemoved, 1000000e18 - 1000e18 + (tokenAWithdrawn - (3 * tokenAWithdrawn / 100)), "Fee token balance after removal (accounting for transfer fees)");
        vm.stopPrank();
    }
}