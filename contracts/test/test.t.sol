// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/mocks/MockERC20.sol";
import "../src/PoolManager.sol";

contract TestERC20 is MockERC20 {
    function mint(address to, uint value) public {
        _mint(to, value);
    }
}

contract BasicTest is Test {
    struct Pool {
        address token0;
        address token1;
        uint24 fee;
    }

    address user1;
    address user2;
    address poolManager;
    
    address token0;
    address token1;
    uint24 fee;

    Pool pool;

    function setUp() public {
        token0 = address(new TestERC20());
        TestERC20(token0).initialize("USDT", "USDT", 18);
        
        token1 = address(new TestERC20());
        TestERC20(token1).initialize("DAI", "DAI", 18);

        fee = 3000;
        poolManager = address(new PoolManager());

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        TestERC20(token0).mint(user1, 20 * 1e18);
        TestERC20(token1).mint(user1, 20000 * 1e18);
        
        TestERC20(token0).mint(user2, 10 * 1e18);
    }


    function testCreatePool() public {
        vm.startPrank(user1);

        bytes32 id = PoolManager(poolManager).createPool(token0, token1, fee);
        (pool.token0,,pool.fee) = PoolManager(poolManager).pools(id);

        assertEq(id, _returnId(), "Wrong id");
        assertNotEq(pool.token0, address(0), "Pool inexistant");
        assertEq(pool.fee, fee, "Wrong fee");


        vm.stopPrank();
    }

    function testCreatePoolSameToken() public {
        vm.startPrank(user1);

        vm.expectRevert("Identical tokens");
        PoolManager(poolManager).createPool(token0, token0, fee);
        
        vm.stopPrank();
    }
    
    function testCreatePoolInvalidTokenAddress() public {
        vm.startPrank(user1);

        vm.expectRevert("Invalid token address");
        PoolManager(poolManager).createPool(token0, address(0), fee);
        
        vm.stopPrank();
    }

    function testCreatePoolAlreadyExistant() public {
        testCreatePool();
        vm.startPrank(user1);

        vm.expectRevert("Pool already exists");
        PoolManager(poolManager).createPool(token0, token1, fee);

        vm.stopPrank();
    }

    function testDeletePool() public {
        testCreatePool();
        vm.startPrank(user1);

        bytes32 id = _returnId();
        PoolManager(poolManager).deletePool(id);
        (pool.token0,,) = PoolManager(poolManager).pools(id);

        assertEq(pool.token0, address(0), "Pool not deleted");

        vm.stopPrank();
    }


    function testDeleteInexistantPool() public {
        vm.startPrank(user1);

        bytes32 id = _returnId();
        vm.expectRevert("Pool does not exist");
        PoolManager(poolManager).deletePool(id);
        (pool.token0,,) = PoolManager(poolManager).pools(id);

        vm.stopPrank();
    }

    function _returnId() private view returns (bytes32) {
        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);
        return keccak256(abi.encodePacked(token0_, token1_, fee));
    }

    function addLiquidity() public {
        testCreatePool();
        vm.startPrank(user1);

        uint token0BeforeUser = token0.balanceOf(user1);
        uint token1BeforeUser = token1.balanceOf(user1);
        uint token0BeforePool = token0.balanceOf(poolManager);
        uint token1BeforePool = token1.balanceOf(poolManager);
        
        poolManager.addLiquidity(pool, 10 * 1e18, 10000 * 1e18);

        uint token0AfterUser = token0.balanceOf(user1);
        uint token1AfterUser = token1.balanceOf(user1);
        uint token0AfterPool = token0.balanceOf(poolManager);
        uint token1AfterPool = token1.balanceOf(poolManager);

        assertEq(pool.reserveA(), 500 ether - outputAmount, "Incorrect reserve for token A");
        assertEq(pool.reserveA(), 500 ether - outputAmount, "Incorrect reserve for token A");

        vm.stopPrank();
    }
}