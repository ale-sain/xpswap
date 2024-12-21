// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.0;

// import "forge-std/Test.sol";
// import "../src/PoolManager.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// contract MockERC20 is ERC20 {
//     constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

//     function mint(address to, uint amount) public {
//         _mint(to, amount);
//     }
// }

// contract RemoveLiquidityTest is Test {
//     struct Pool {
//         address token0;
//         address token1;
//         uint24 fee;
//         uint reserve0;
//         uint reserve1;
//         uint liquidity;
//     }

//     address user1;
//     address user2;
//     address poolManager;
    
//     address token0;
//     address token1;
//     uint24 fee;

//     Pool pool;

//     function setUp() public {
//         token0 = address(new MockERC20("USDT", "USDT"));
//         token1 = address(new MockERC20("DAI", "DAI"));
//         (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

//         fee = 3000;
//         poolManager = address(new PoolManager());

//         user1 = makeAddr("user1");
//         user2 = makeAddr("user2");

//         MockERC20(token0).mint(user1, 20 * 1e18);
//         MockERC20(token1).mint(user1, 20000 * 1e18);

//         vm.startPrank(user1);
//         MockERC20(token0).approve(poolManager, type(uint256).max);
//         MockERC20(token1).approve(poolManager, type(uint256).max);
//         vm.stopPrank();
        
//         MockERC20(token0).mint(user2, 10 * 1e18);
//     }

//     function _returnId() private view returns (bytes32) {
//         (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);
//         return keccak256(abi.encodePacked(token0_, token1_, fee));
//     }

//     function testRemoveLiquidity() public {
//         vm.startPrank(user1);

//         bytes32 id = PoolManager(poolManager).createPool(token0, token1, fee);
//         PoolManager(poolManager).addLiquidity(id, 10 * 1e18, 10000 * 1e18, user1);

//         (,,, uint reserve0Before, uint reserve1Before, uint poolLiquidityBefore) = PoolManager(poolManager).pools(id);
//         uint userLiquidityPoolBefore = PoolManager(poolManager).liquidity(id, user1);

//         uint token0BeforeUser = MockERC20(token0).balanceOf(user1);
//         uint token1BeforeUser = MockERC20(token1).balanceOf(user1);
//         uint token0BeforePool = MockERC20(token0).balanceOf(poolManager);
//         uint token1BeforePool = MockERC20(token1).balanceOf(poolManager);

//         uint liquidityToRemove = userLiquidityPoolBefore / 2;
//         PoolManager(poolManager).removeLiquidity(id, liquidityToRemove, user1);

//         (,,,uint reserve0After, uint reserve1After, uint poolLiquidityAfter) = PoolManager(poolManager).pools(id);

//         uint amount0Out = (liquidityToRemove * reserve0Before) / poolLiquidityBefore;
//         uint amount1Out = (liquidityToRemove * reserve1Before) / poolLiquidityBefore;

//         assertEq(reserve0After, reserve0Before - amount0Out, "Invalid reserve0 after removal");
//         assertEq(reserve1After, reserve1Before - amount1Out, "Invalid reserve1 after removal");
//         assertEq(poolLiquidityAfter, poolLiquidityBefore - liquidityToRemove, "Invalid pool liquidity after removal");
//         assertEq(PoolManager(poolManager).liquidity(id, user1), userLiquidityPoolBefore - liquidityToRemove, "Invalid user liquidity after removal");
//         assertEq(MockERC20(token0).balanceOf(user1), token0BeforeUser + amount0Out, "Invalid amount of token0 for user after removal");
//         assertEq(MockERC20(token1).balanceOf(user1), token1BeforeUser + amount1Out, "Invalid amount of token1 for user after removal");
//         assertEq(MockERC20(token0).balanceOf(poolManager), token0BeforePool - amount0Out, "Invalid amount of token0 in pool after removal");
//         assertEq(MockERC20(token1).balanceOf(poolManager), token1BeforePool - amount1Out, "Invalid amount of token1 in pool after removal");

//         vm.stopPrank();
//     }

//     function testRemoveAllLiquidity() public {
//         vm.startPrank(user1);
        
//         bytes32 id = PoolManager(poolManager).createPool(token0, token1, fee);
//         PoolManager(poolManager).addLiquidity(id, 10 * 1e18, 10000 * 1e18, user1);

//         (,,, uint reserve0Before, uint reserve1Before, uint poolLiquidityBefore) = PoolManager(poolManager).pools(id);
//         uint userLiquidityPoolBefore = PoolManager(poolManager).liquidity(id, user1);

//         uint token0BeforeUser = MockERC20(token0).balanceOf(user1);
//         uint token1BeforeUser = MockERC20(token1).balanceOf(user1);
//         uint token0BeforePool = MockERC20(token0).balanceOf(poolManager);
//         uint token1BeforePool = MockERC20(token1).balanceOf(poolManager);

//         uint liquidityToRemove = userLiquidityPoolBefore; // Retire 50% de la liquidité de l'utilisateur

//         PoolManager(poolManager).removeLiquidity(id, liquidityToRemove, user1);

//         (,,,uint reserve0After, uint reserve1After, uint poolLiquidityAfter) = PoolManager(poolManager).pools(id);

//         uint amount0Out = (liquidityToRemove * reserve0Before) / poolLiquidityBefore;
//         uint amount1Out = (liquidityToRemove * reserve1Before) / poolLiquidityBefore;

//         assertEq(reserve0After, reserve0Before - amount0Out, "Invalid reserve0 after removal");
//         assertEq(reserve1After, reserve1Before - amount1Out, "Invalid reserve1 after removal");
//         assertEq(poolLiquidityAfter, poolLiquidityBefore - liquidityToRemove, "Invalid pool liquidity after removal");
//         assertEq(PoolManager(poolManager).liquidity(id, user1), userLiquidityPoolBefore - liquidityToRemove, "Invalid user liquidity after removal");
//         assertEq(MockERC20(token0).balanceOf(user1), token0BeforeUser + amount0Out, "Invalid amount of token0 for user after removal");
//         assertEq(MockERC20(token1).balanceOf(user1), token1BeforeUser + amount1Out, "Invalid amount of token1 for user after removal");
//         assertEq(MockERC20(token0).balanceOf(poolManager), token0BeforePool - amount0Out, "Invalid amount of token0 in pool after removal");
//         assertEq(MockERC20(token1).balanceOf(poolManager), token1BeforePool - amount1Out, "Invalid amount of token1 in pool after removal");
//         assertEq(poolLiquidityAfter, 1000, "Invalid pool liquidity after removal");
//         vm.stopPrank();
//     }

//     function testRemoveTooMuchLiquidity() public {
//         vm.startPrank(user1);
        
//         bytes32 id = PoolManager(poolManager).createPool(token0, token1, fee);
//         PoolManager(poolManager).addLiquidity(id, 10 * 1e18, 10000 * 1e18, user1);

//         uint liquidityToRemove = PoolManager(poolManager).liquidity(id, user1);

//         vm.expectRevert("Insufficient liquidity");
//         PoolManager(poolManager).removeLiquidity(id, liquidityToRemove + 1000, user1);

//         vm.stopPrank();
//     }

//     function testRemoveLiquidityToZeroAddress() public {
//         vm.startPrank(user1);
        
//         bytes32 id = PoolManager(poolManager).createPool(token0, token1, fee);
//         PoolManager(poolManager).addLiquidity(id, 10 * 1e18, 10000 * 1e18, user1);


//         PoolManager(poolManager).addLiquidity(id, 10 * 1e18, 10000 * 1e18, user1);

//         vm.expectRevert("Invalid address");
//         PoolManager(poolManager).removeLiquidity(id, 1 * 1e18, address(0));
        
//         vm.stopPrank();
//     }

//     function testRemoveLiquidityFromNonExistentPool() public {
//         vm.startPrank(user1);
//         bytes32 id = keccak256(abi.encodePacked(token0, token1, uint24(3000))); // ID d'une pool inexistante

//         vm.expectRevert("Pool does not exist");
//         PoolManager(poolManager).removeLiquidity(id, 1 * 1e18, user1);
//         vm.stopPrank();
//     }
// }