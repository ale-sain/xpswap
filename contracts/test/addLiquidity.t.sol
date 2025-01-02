// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/PoolManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint amount) public {
        _mint(to, amount);
    }
}

contract AddLiquidityTest is Test {
    address user1;
    address user2;
    address poolManager;

    address token0;
    address token1;
    uint24 fee;

    function setUp() public {
        token0 = address(new MockERC20("USDT", "USDT"));
        token1 = address(new MockERC20("DAI", "DAI"));
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        fee = 3000;
        poolManager = address(new PoolManager());

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Mint de tokens pour user1
        MockERC20(token0).mint(user1, 20 * 1e18);
        MockERC20(token1).mint(user1, 20000 * 1e18);

        vm.startPrank(user1);
        MockERC20(token0).approve(poolManager, type(uint256).max);
        MockERC20(token1).approve(poolManager, type(uint256).max);
        vm.stopPrank();

        // Mint de tokens pour user2
        MockERC20(token0).mint(user2, 10 * 1e18);
    }

    function _returnId() private view returns (bytes32) {
        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);
        return keccak256(abi.encodePacked(token0_, token1_));
    }

    function _calculateLiquidity(uint poolLiquidity, uint amount0, uint amount1, uint reserve0, uint reserve1) private pure returns (uint,uint) {
        if (poolLiquidity != 0) {
            uint ratioA = amount0 * poolLiquidity / reserve0;
            uint ratioB = amount1 * poolLiquidity / reserve1;
            if (ratioB < ratioA) {
                amount0 = amount1 * reserve0 / reserve1;
            } else {
                amount1 = amount0 * reserve1 / reserve0;
            }
        }
        return (amount0, amount1);
    }


    function testAddFirstLiquidity() public {
        vm.startPrank(user1);

        // Créer un pool
        bytes32 poolId = PoolManager(poolManager).createPool(token0, token1);
        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);

        uint amount0 = 5 * 1e18;
        uint amount1 = 10000 * 1e18;

        // Avant l'ajout de liquidité
        uint token0BeforeUser = MockERC20(token0).balanceOf(user1);
        uint token1BeforeUser = MockERC20(token1).balanceOf(user1);
        uint token0BeforePool = MockERC20(token0).balanceOf(poolManager);
        uint token1BeforePool = MockERC20(token1).balanceOf(poolManager);

        // Ajouter la liquidité
        (int transientReserve0, int transientReserve1, int transientLiquidity) = addLiquidityForTest(poolId, amount0, amount1);

        // Verifier les valeurs transientes
        assertEq(transientReserve0, int(amount0), "Invalid transient reserve0");
        assertEq(transientReserve1, int(amount1), "Invalid transient reserve1");
        assertEq(transientLiquidity, int(Math.sqrt(amount0 * amount1)) - 1000, "Invalid transient liquidity");

        assertEq(3, PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))), "Invalid transient variable");

        // Mettre à jour les valeurs du pool
        bytes32 [] memory poolIds = new bytes32[](1);
        poolIds[0] = poolId;

        address [] memory addresses = new address[](2);
        addresses[0] = token0_;
        addresses[1] = token1_;

        PoolManager(poolManager).updateContractState(poolIds);
        PoolManager(poolManager).updateContractBalance(addresses);

        // Check pool reserves
        (,,uint reserve0, uint reserve1) = PoolManager(poolManager).pools(poolId);
        assertEq(reserve0, uint(amount0), "Invalid reserve0 after first liquidity");
        assertEq(reserve1, uint(amount1), "Invalid reserve1 after first liquidity");

        // Check balance
        uint token0AfterUser = MockERC20(token0).balanceOf(user1);
        uint token1AfterUser = MockERC20(token1).balanceOf(user1);
        uint token0AfterPool = MockERC20(token0).balanceOf(poolManager);
        uint token1AfterPool = MockERC20(token1).balanceOf(poolManager);

        uint liquidity = Math.sqrt(amount0 * amount1);
        
        uint userLiquidityPoolAfter = PoolManager(poolManager).lp(poolId, user1);
        assertEq(userLiquidityPoolAfter, liquidity - 1000, "Invalid user liquidity after removal");

        // Vérifications des soldes
        assertEq(token0AfterUser, token0BeforeUser - amount0, "Invalid amount of token0 user");
        assertEq(token1AfterUser, token1BeforeUser - amount1, "Invalid amount of token1 user");
        assertEq(token0AfterPool, token0BeforePool + amount0, "Invalid amount of token0 pool");
        assertEq(token1AfterPool, token1BeforePool + amount1, "Invalid amount of token1 pool");

        // Vérification de la liquidité
        uint userLiquidityPool = PoolManager(poolManager).lp(poolId, user1);
        assertEq(userLiquidityPool, liquidity - 1000, "Invalid liquidity amount for user");
        
        assertEq(0, PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))), "Invalid transient variable");

        vm.stopPrank();
    }

    function testAddOtherLiquidity() public {
        vm.startPrank(user1);
        
        bytes32 poolId = PoolManager(poolManager).createPool(token0, token1);

        (int beforeReserve0, int beforeReserve1, int beforeLiquidity) = addLiquidityForTest(poolId, 1 * 1e18, 1000 * 1e18);

        uint amount0 = 5 * 1e18;
        uint amount1 = 10000 * 1e18;

        (int afterReserve0, int afterReserve1, int afterLiquidity) = addLiquidityForTest(poolId, amount0, amount1);
        
        (amount0, amount1) = _calculateLiquidity(uint(beforeLiquidity), amount0, amount1, uint(beforeReserve0), uint(beforeReserve1));
        uint liquidity = Math.sqrt(amount0 * amount1);

        assertEq(uint(afterLiquidity), uint(beforeLiquidity) + liquidity, "Invalid amout of pool liquidity");
        assertEq(uint(afterReserve0), uint(beforeReserve0) + amount0, "Invalid amout of token0 pool");
        assertEq(uint(afterReserve1), uint(beforeReserve1) + amount1, "Invalid amout of token1 pool");

        vm.stopPrank();
    }

    function testAddLiquidityWithLowAmounts() public {
        vm.startPrank(user1);

        bytes32 poolId = PoolManager(poolManager).createPool(token0, token1);

        uint amount0Low = 0;
        uint amount1Low = 1000;

        vm.expectRevert("Pool: Invalid amount for token A");
        PoolManager(poolManager).addLiquidity(poolId, amount0Low, 1000 * 1e18);
        
        vm.expectRevert("Pool: Invalid amount for token B");
        PoolManager(poolManager).addLiquidity(poolId, 1 * 1e18, amount1Low);

        vm.stopPrank();
    }

    function addLiquidityForTest(bytes32 poolId, uint amount0, uint amount1) public returns (int transientReserve0, int transientReserve1, int transientLiquidity) {
        PoolManager(poolManager).addLiquidity(poolId, amount0, amount1);
        (address token0_, address token1_,,) = PoolManager(poolManager).pools(poolId);

        transientReserve0 = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked(poolId, token0_)));
        transientReserve1 = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked(poolId, token1_)));
        transientLiquidity = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked(poolId, address(user1))));
    }

    function testAddLiquidityWithHighAmounts() public {
        vm.startPrank(user1);

        bytes32 poolId = PoolManager(poolManager).createPool(token0, token1);

        uint amount0High = 2 ** 128 - 1;
        uint amount1High = 2 ** 128 - 1;

        MockERC20(token0).mint(user1, amount0High);
        MockERC20(token1).mint(user1, amount1High);

        (int transientReserve0, int transientReserve1, int transientLiquidity) = addLiquidityForTest(poolId, amount0High, amount1High);

        assertEq(amount0High, uint(transientReserve0), "Invalid reserve0 after large liquidity");
        assertEq(amount1High, uint(transientReserve1), "Invalid reserve1 after large liquidity");
        assertEq(Math.sqrt(amount0High * amount1High) - 1000, uint(transientLiquidity),  "Invalid liquidity after large amount");

        vm.stopPrank();
    }

    function testAddLiquidityOverflow() public {
        vm.startPrank(user1);

        bytes32 poolId = PoolManager(poolManager).createPool(token0, token1);
        
        uint amount0Overflow = 2 ** 130;
        uint amount1Overflow = 2 ** 130;

        vm.expectRevert(); 
        PoolManager(poolManager).addLiquidity(poolId, amount0Overflow, amount1Overflow);

        vm.stopPrank();
    }

    function testAddLiquidityNonExistentPool() public {
        vm.startPrank(user1);
        
        bytes32 poolId = keccak256(abi.encodePacked(token0, token1, uint24(3000))); // ID d'une pool inexistante
        
        vm.expectRevert("Pool does not exist");
        PoolManager(poolManager).addLiquidity(poolId, 10 * 1e18, 1000 * 1e18);

        vm.stopPrank();
    }

    function testAddLiquidityToZeroAddress() public {
        vm.startPrank(user1);

        vm.expectRevert();
        PoolManager(poolManager).addLiquidity(0, 10 * 1e18, 1000 * 1e18);
        
        vm.stopPrank();
    }

    function testAddLiquidityTransferFromFails() public {
        vm.startPrank(user1);
        
        bytes32 poolId = PoolManager(poolManager).createPool(token0, token1);
        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);

        MockERC20(token0).approve(poolManager, 0);

        PoolManager(poolManager).addLiquidity(poolId, 10 * 1e18, 1000 * 1e18);

        bytes32 [] memory poolIds = new bytes32[](1);
        poolIds[0] = poolId;

        address [] memory addresses = new address[](2);
        addresses[0] = token0_;
        addresses[1] = token1_;

        PoolManager(poolManager).updateContractState(poolIds);

        vm.expectRevert("Pool: Transfer failed");
        PoolManager(poolManager).updateContractBalance(addresses);
        
        
        vm.stopPrank();
    }

}