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

contract RemoveLiquidityTest is Test {
    address user1;
    address user2;
    address poolManager;
    
    address token0;
    address token1;

    function setUp() public {
        token0 = address(new MockERC20("USDT", "USDT"));
        token1 = address(new MockERC20("DAI", "DAI"));
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        poolManager = address(new PoolManager());

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        MockERC20(token0).mint(user1, 20 * 1e18);
        MockERC20(token1).mint(user1, 20000 * 1e18);

        vm.startPrank(user1);
        MockERC20(token0).approve(poolManager, type(uint256).max);
        MockERC20(token1).approve(poolManager, type(uint256).max);
        vm.stopPrank();
        
        MockERC20(token0).mint(user2, 10 * 1e18);
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _returnId() private view returns (bytes32) {
        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);
        return keccak256(abi.encodePacked(token0_, token1_));
    }

    function testRemoveLiquidity() public {
        vm.startPrank(user1);

        bytes32 poolId = PoolManager(poolManager).createPool(token0, token1);

        uint amount0 = 5000;
        uint amount1 = 10000;

        PoolManager(poolManager).addLiquidity(poolId, amount0, amount1);
        
        (int beforeReserve0, int beforeReserve1, int beforeLiqUser, int beforeActiveDelta) = _getPoolData(poolId, user1);
        assertEq(3, beforeActiveDelta, "Invalid activeDelta before removeLiquidity");
        uint beforeLiquidity = sqrt(uint(beforeReserve0 * beforeReserve1));

        uint liquidityToRemove = uint(beforeLiquidity) / 2;
        PoolManager(poolManager).removeLiquidity(poolId, liquidityToRemove);
        
        (int afterReserve0, int afterReserve1, int afterLiqUser, int afterActiveDelta) = _getPoolData(poolId, user1);
        assertEq(3, afterActiveDelta, "Invalid activeDelta after removeLiquidity");
        uint afterLiquidity = sqrt(uint(afterReserve0 * afterReserve1));

        uint amount0Out = (liquidityToRemove * uint(beforeReserve0)) / uint(beforeLiquidity);
        uint amount1Out = (liquidityToRemove * uint(beforeReserve1)) / uint(beforeLiquidity);

        assertEq(uint(afterReserve0), uint(beforeReserve0) - amount0Out, "Invalid reserve0 after removal");
        assertEq(uint(afterReserve1), uint(beforeReserve1) - amount1Out, "Invalid reserve1 after removal");
        assertEq(uint(afterLiqUser), uint(beforeLiqUser) - liquidityToRemove, "Invalid pool liquidity after removal");
        assertEq(uint(afterLiquidity), uint(beforeLiquidity) - liquidityToRemove, "Invalid user liquidity after removal");

        vm.stopPrank();
    }

    function testRemoveTooMuchLiquidity() public {
        vm.startPrank(user1);

        bytes32 poolId = PoolManager(poolManager).createPool(token0, token1);

        uint amount0 = 5000;
        uint amount1 = 10000;

        PoolManager(poolManager).addLiquidity(poolId, amount0, amount1);
        
        (int beforeReserve0, int beforeReserve1,,) = _getPoolData(poolId, user1);
        uint beforeLiquidity = sqrt(uint(beforeReserve0 * beforeReserve1));

        vm.expectRevert("Insufficient liquidity");
        PoolManager(poolManager).removeLiquidity(poolId, beforeLiquidity);

        vm.stopPrank();
    }

    function testRemoveJustEnoughLiquidity() public {
        vm.startPrank(user1);

        bytes32 poolId = PoolManager(poolManager).createPool(token0, token1);

        uint amount0 = 5000;
        uint amount1 = 10000;

        PoolManager(poolManager).addLiquidity(poolId, amount0, amount1);
        
        (int beforeReserve0, int beforeReserve1,,) = _getPoolData(poolId, user1);
        uint beforeLiquidity = sqrt(uint(beforeReserve0 * beforeReserve1));

        PoolManager(poolManager).removeLiquidity(poolId, beforeLiquidity - 1000);

        (int afterReserve0, int afterReserve1, int afterLiqUser,) = _getPoolData(poolId, user1);
        uint afterLiquidity = sqrt(uint(afterReserve0 * afterReserve1));

        assertEq(uint(afterLiqUser), 0, "Invalid pool liquidity after removal");
        assertEq(uint(afterLiquidity), 1000, "Invalid user liquidity after removal");

        vm.stopPrank();
    }

    function testRemoveLiquidityFromNonExistentPool() public {
        vm.startPrank(user1);
        bytes32 poolId = keccak256(abi.encodePacked(token0, token1, uint24(3000))); // ID d'une pool inexistante

        vm.expectRevert("Pool does not exist");
        PoolManager(poolManager).removeLiquidity(poolId, 1 * 1e18);

        vm.stopPrank();
    }

    // Fonction pour obtenir les données de réserve et de liquidité
    function _getPoolData(bytes32 poolId, address user) internal view returns (int reserve0, int reserve1, int liquidity, int activeDelta) {
        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);
        reserve0 = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked(poolId, token0_)));
        reserve1 = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked(poolId, token1_)));
        liquidity = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked(poolId, user)));
        activeDelta = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
    }
}
