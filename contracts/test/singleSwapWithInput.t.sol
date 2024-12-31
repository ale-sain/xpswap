// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/PoolManager.sol";
import "../lib/forge-std/src/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint amount) public {
        _mint(to, amount);
    }
}

contract PoolManagerTest is Test {
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

        MockERC20(token0).mint(user1, 5000);
        MockERC20(token1).mint(user1, 10000);

        vm.startPrank(user1);

        MockERC20(token0).approve(poolManager, type(uint256).max);
        MockERC20(token1).approve(poolManager, type(uint256).max);
        
        bytes32 id = PoolManager(poolManager).createPool(token0, token1);
        (uint amount0, uint amount1) = token0 < token1 ? (2000, 10000) : (10000, 2000);
        PoolManager(poolManager).addLiquidity(id, amount0, amount1);
        
        bytes32 [] memory poolsId = new bytes32[](1);
        poolsId[0] = id;

        address[] memory tokens = new address[](2);
        (address _token0 , address _token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        tokens[0] = _token0;
        tokens[1] = _token1;

        PoolManager(poolManager).updateContractState(poolsId);
        PoolManager(poolManager).updateContractBalance(tokens);

        vm.stopPrank();
        
        vm.startPrank(user2);

        MockERC20(token0).mint(user2, 2000);
        MockERC20(token1).mint(user2, 2000);
        MockERC20(token0).approve(poolManager, type(uint256).max);
        MockERC20(token1).approve(poolManager, type(uint256).max);

        vm.stopPrank();

    }

    function abs(int256 value) internal pure returns (uint256) {
        return value < 0 ? uint256(-value) : uint256(value);
    }

    function _getPoolData(bytes32 poolId, address user) internal view returns (int reserve0, int reserve1, int liquidity, int activeDelta) {
        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);
        reserve0 = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked(poolId, token0_)));
        reserve1 = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked(poolId, token1_)));
        liquidity = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked(poolId, user)));
        activeDelta = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
    }

    function testSwapWithInputZeroForOne() public {
        vm.startPrank(user2);

        bytes32 poolId = PoolManager(poolManager).getPoolId(address(token0), address(token1));
        (,, uint beforeReserve0, uint beforeReserve1) = PoolManager(poolManager).pools(poolId);

        uint amountIn = 500;
        uint minAmountOut = PoolManager(poolManager).getAmountOut(beforeReserve0, beforeReserve1, amountIn);

        // Execute swap
        PoolManager(poolManager).swapWithInput(poolId, amountIn, minAmountOut, true);

        // Check updated reserves
        (int delta0, int delta1,,) = _getPoolData(poolId, user2);

        assertEq(abs(delta0), 500, "Reserve0 should increase");
        assertEq(abs(delta1), minAmountOut, "Reserve1 should decrease");

        vm.stopPrank();
    }

    function testSwapWithInputOneForZero() public {
        vm.startPrank(user2);

        bytes32 poolId = PoolManager(poolManager).getPoolId(address(token0), address(token1));
        (,, uint beforeReserve0, uint beforeReserve1) = PoolManager(poolManager).pools(poolId);

        uint amountIn = 500;
        uint minAmountOut = PoolManager(poolManager).getAmountOut(beforeReserve1, beforeReserve0, amountIn);

        PoolManager(poolManager).swapWithInput(poolId, amountIn, minAmountOut, false);

        (int delta0, int delta1,,) = _getPoolData(poolId, user2);

        assertEq(abs(delta0), minAmountOut, "Reserve0 should decrease");
        assertEq(abs(delta1), 500, "Reserve1 should increase");

        vm.stopPrank();
    }

    function testSwapWithInputInvalidPool() public {
        vm.startPrank(user2);

        bytes32 poolId = PoolManager(poolManager).getPoolId(address(token0), address(token0));

        vm.expectRevert("Pool does not exist");
        PoolManager(poolManager).swapWithInput(poolId, 500, 1993, true);

        vm.stopPrank();
    }

    function testSwapWithInputInvalidInputAmount() public {
        vm.startPrank(user2);

        bytes32 poolId = PoolManager(poolManager).getPoolId(address(token0), address(token1));

        vm.expectRevert("Pool: Invalid input amount");
        PoolManager(poolManager).swapWithInput(poolId, 0, 1993, true);

        vm.stopPrank();
    }

    function testSwapWithInputInsufficientOutputAmount() public {
        vm.startPrank(user2);

        bytes32 poolId = PoolManager(poolManager).getPoolId(address(token0), address(token1));

        vm.expectRevert("Pool: Insufficient output amount");
        PoolManager(poolManager).swapWithInput(poolId, 500, 2000, true);

        vm.stopPrank();
    }
}