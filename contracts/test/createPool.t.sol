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

contract createPoolTest is Test {
    struct Pool {
        address token0;
        address token1;
        uint24 fee;
        uint reserve0;
        uint reserve1;
        uint liquidity;
    }

    address user1;
    address user2;
    address poolManager;
    
    address token0;
    address token1;
    uint24 fee;

    Pool pool;

    function setUp() public {
        token0 = address(new MockERC20("USDT", "USDT"));
        token1 = address(new MockERC20("DAI", "DAI"));
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        fee = 3000;
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

    function _returnId() private view returns (bytes32) {
        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);
        return keccak256(abi.encodePacked(token0_, token1_, fee));
    }

    function testCreatePool() public {
        vm.startPrank(user1);

        bytes32 id = PoolManager(poolManager).createPool(token0, token1, fee);
        (pool.token0,,pool.fee,,,) = PoolManager(poolManager).pools(id);

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
        PoolManager(poolManager).createPool(token0, token1, fee);
        vm.startPrank(user1);

        vm.expectRevert("Pool already exists");
        PoolManager(poolManager).createPool(token0, token1, fee);

        vm.stopPrank();
    }
}