// SPDX-License-Identifier: MIT
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


contract TestPoolManager is Test {
    PoolManager poolManager;
    address token0;
    address token1;
    address otherToken0;
    address otherToken1;
    address user1;
    address user2;

    function setUp() public {
        token0 = address(new MockERC20("USDT", "USDT"));
        token1 = address(new MockERC20("DAI", "DAI"));
        otherToken0 = address(new MockERC20("USDC", "USDC"));
        otherToken1 = address(new MockERC20("USDT", "USDT"));

        poolManager = new PoolManager();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        MockERC20(token0).mint(user1, 20 * 1e18);
        MockERC20(token1).mint(user1, 20000 * 1e18);
        MockERC20(otherToken0).mint(user1, 20 * 1e18);
        MockERC20(otherToken1).mint(user1, 20000 * 1e18);

        vm.startPrank(user1);
        MockERC20(token0).approve(address(poolManager), type(uint256).max);
        MockERC20(token1).approve(address(poolManager), type(uint256).max);
        MockERC20(otherToken0).approve(address(poolManager), type(uint256).max);
        MockERC20(otherToken1).approve(address(poolManager), type(uint256).max);
        vm.stopPrank();

        MockERC20(token0).mint(user2, 10 * 1e18);
    }

    function testCreatePool() public {
        bytes32 poolId = poolManager.createPool(token0, token1);
        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);

        (address token0Pool, address token1Pool, , ) = poolManager.pools(poolId);
        assertEq(token0_, token0Pool);
        assertEq(token1_, token1Pool);
    }

    function testSimpleSetTransientValue() public {
        bytes32 key = keccak256(abi.encodePacked("testKey"));
        int delta = 10;

        (int before, int afterr) = poolManager._setTransientValue(key, delta);
        
        assertEq(before, 0);
        assertEq(afterr, delta);
    }

    function testMultiSetTransientValue() public {
        bytes32 key = keccak256(abi.encodePacked("testKey"));
        int delta = 10;
        int delta2 = -20;

        poolManager._setTransientValue(key, delta);
        (int before2, int afterr2) = poolManager._setTransientValue(key, delta2);
        
        assertEq(before2, 10);
        assertEq(afterr2, -10);
    }

    function testGetTransientVariable() public {
        bytes32 key = keccak256(abi.encodePacked("testKey"));
        int delta = 10;

        poolManager._setTransientValue(key, delta);
        
        int value = poolManager._getTransientVariable(key);
        assertEq(value, delta);
    }

    function testUpdatePoolTransientReserve() public {
        vm.startPrank(user1);
        
        bytes32 poolId = poolManager.createPool(token0, token1);
        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);
        
        int amount0 = 5;
        int amount1 = 10;
        int liquidity = 15;

        poolManager._updatePoolTransientReserve(poolId, amount0, amount1, liquidity);

        int updatedAmount0 = poolManager._getTransientVariable(keccak256(abi.encodePacked(poolId, token0_)));
        int updatedAmount1 = poolManager._getTransientVariable(keccak256(abi.encodePacked(poolId, token1_)));
        int updatedLiquidity = poolManager._getTransientVariable(keccak256(abi.encodePacked(poolId, address(user1))));
        
        assertEq(updatedAmount0, amount0);
        assertEq(updatedAmount1, amount1);
        assertEq(updatedLiquidity, liquidity);
        
        vm.stopPrank();
    }

    function testUpdateTokenTransientBalance() public {
        address token = address(0x123);
        int amount = 20;

        poolManager._updateTokenTransientBalance(token, amount);

        int updatedBalance = poolManager._getTransientVariable(keccak256(abi.encodePacked(token)));
        assertEq(updatedBalance, amount);
    }

    function testAddActiveDelta() public {
        vm.startPrank(user1);
        
        bytes32 poolId = poolManager.createPool(token0, token1);
        (address token0_,) = token0 < token1 ? (token0, token1) : (token1, token0);

        int amount0 = 5;
        int amount1 = 10;

        poolManager._updatePoolTransientReserve(poolId, amount0, amount1, 0);
        int addedDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(addedDelta, 1);
        
        poolManager._updateTokenTransientBalance(token0_, amount0);
        addedDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(addedDelta, 2);

        vm.stopPrank();
    }

    function testSingleUpdateContractState() public {
        vm.startPrank(user1);
    
        bytes32 poolId = poolManager.createPool(token0, token1);

        int amount0 = 5;
        int amount1 = 10;
        int liquidity = 15;

        poolManager._updatePoolTransientReserve(poolId, amount0, amount1, liquidity);
        assertEq(1, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        bytes32[] memory poolsId = new bytes32[](1);
        poolsId[0] = poolId;

        poolManager.updateContractState(poolsId);
        assertEq(0, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        (,, uint reserve0, uint reserve1) = poolManager.pools(poolId);
        assertEq(reserve0, uint(amount0));
        assertEq(reserve1, uint(amount1));

        vm.stopPrank();
    }

    function testMultiCancelledUpdateContractState() public {
        vm.startPrank(user1);
    
        bytes32 poolId = poolManager.createPool(token0, token1);

        int amount0 = 5;
        int amount1 = 10;
        int liquidity = 15;

        poolManager._updatePoolTransientReserve(poolId, amount0, amount1, liquidity);
        assertEq(1, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        poolManager._updatePoolTransientReserve(poolId, -amount0, -amount1, -liquidity);
        assertEq(0, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        bytes32[] memory poolsId = new bytes32[](1);
        poolsId[0] = poolId;

        poolManager.updateContractState(poolsId);
        assertEq(0, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        (,, uint reserve0, uint reserve1) = poolManager.pools(poolId);
        assertEq(reserve0, 0);
        assertEq(reserve1, 0);

        vm.stopPrank();
    }

    function testMultiPoolUpdateContractState() public {
        vm.startPrank(user1);
    
        bytes32 poolId = poolManager.createPool(token0, token1);
        bytes32 otherPoolId = poolManager.createPool(otherToken0, otherToken1);

        int amount0 = 5;
        int amount1 = 10;
        int liquidity = 15;

        poolManager._updatePoolTransientReserve(poolId, amount0, amount1, liquidity);
        assertEq(1, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        poolManager._updatePoolTransientReserve(poolId, amount0, amount1, liquidity);
        assertEq(1, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        poolManager._updatePoolTransientReserve(otherPoolId, amount0, amount1, liquidity);
        assertEq(2, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        bytes32[] memory poolsId = new bytes32[](2);
        poolsId[0] = poolId;
        poolsId[1] = otherPoolId;

        poolManager.updateContractState(poolsId);
        assertEq(0, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        (,, uint reserve0, uint reserve1) = poolManager.pools(poolId);
        assertEq(reserve0, uint(amount0 * 2), "Invalid reserve0");
        assertEq(reserve1, uint(amount1 * 2), "Invalid reserve1");

        (,, reserve0, reserve1) = poolManager.pools(otherPoolId);
        assertEq(reserve0, uint(amount0), "Invalid reserve0");
        assertEq(reserve1, uint(amount1), "Invalid reserve1");

        vm.stopPrank();
    }

    function testInvalidOrder() public {
        vm.startPrank(user1);

        address[] memory tokens = new address[](1);
        tokens[0] = token0;

        poolManager._updateTokenTransientBalance(token0, 10);
        int activeDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(activeDelta, 1);
        
        poolManager.updateContractBalance(tokens);
        activeDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(activeDelta, 0);

        vm.expectRevert("Invalid functions call order");
        poolManager._updateTokenTransientBalance(token0, -10);

        vm.stopPrank();
    }

    function testSingleUpdateContractBalance() public {
        vm.startPrank(user1);

        address[] memory tokens = new address[](1);
        tokens[0] = token0;

        poolManager._updateTokenTransientBalance(token0, 10);
        int activeDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(activeDelta, 1);
        
        poolManager.updateContractBalance(tokens);
        activeDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(activeDelta, 0);

        assertEq(MockERC20(token0).balanceOf(address(poolManager)), 10);

        vm.stopPrank();
    }

    function testMultiCancellingUpdateContractBalance() public {
        vm.startPrank(user1);

        address[] memory tokens = new address[](1);
        tokens[0] = token0;

        uint value = MockERC20(token0).balanceOf(user1);

        poolManager._updateTokenTransientBalance(token0, 10);
        int activeDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(activeDelta, 1);

        poolManager._updateTokenTransientBalance(token0,-10);
        activeDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(activeDelta, 0);
        
        poolManager.updateContractBalance(tokens);
        activeDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(activeDelta, 0);

        assertEq(MockERC20(token0).balanceOf(address(poolManager)), 0);
        assertEq(MockERC20(token0).balanceOf(user1), value);

        vm.stopPrank();
    }

    function testMultiUpdateContractBalance() public {
        vm.startPrank(user1);

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        uint value0 = MockERC20(token0).balanceOf(user1);
        uint value1 = MockERC20(token1).balanceOf(user1);

        poolManager._updateTokenTransientBalance(token0, 30);
        int activeDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(activeDelta, 1);

        poolManager._updateTokenTransientBalance(token0, -10);
        activeDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(activeDelta, 1);
        
        poolManager._updateTokenTransientBalance(token1, 50);
        activeDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(activeDelta, 2);

        poolManager.updateContractBalance(tokens);
        activeDelta = poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
        assertEq(activeDelta, 0);

        assertEq(MockERC20(token0).balanceOf(address(poolManager)), 20);
        assertEq(MockERC20(token0).balanceOf(user1), value0 - 20);

        assertEq(MockERC20(token1).balanceOf(address(poolManager)), 50);
        assertEq(MockERC20(token1).balanceOf(user1), value1 - 50);
    
        vm.stopPrank();
    }

    function testUpdateStateAndBalance() public {
        vm.startPrank(user1);

        bytes32 poolId = poolManager.createPool(token0, token1);
        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);

        int amount0 = 5;
        int amount1 = 10;
        int liquidity = 15;

        poolManager._updatePoolTransientReserve(poolId, amount0, amount1, liquidity);
        assertEq(1, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        poolManager._updateTokenTransientBalance(token0_, amount0);
        assertEq(2, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        poolManager._updateTokenTransientBalance(token1_, amount1);
        assertEq(3, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        bytes32[] memory poolsId = new bytes32[](1);
        poolsId[0] = poolId;

        poolManager.updateContractState(poolsId);
        assertEq(2, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        poolManager.updateContractBalance(tokens);
        assertEq(0, poolManager._getTransientVariable(keccak256(abi.encodePacked("activeDelta"))));

        (,, uint reserve0, uint reserve1) = poolManager.pools(poolId);
        assertEq(reserve0, uint(amount0), "Invalid reserve0");
        assertEq(reserve1, uint(amount1), "Invalid reserve1");    

        assertEq(MockERC20(token0_).balanceOf(address(poolManager)), uint(amount0), "Invalid balance of token0 in poolManager");
        assertEq(MockERC20(token1_).balanceOf(address(poolManager)), uint(amount1), "Invalid balance of token1 in poolManager");

        vm.stopPrank();
    }
}
