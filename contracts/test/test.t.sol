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

contract BasicTest is Test {
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

    function _calculateLiquidity(bytes32 id, uint amount0, uint amount1) private view returns (uint,uint) {
        (,,,uint reserve0, uint reserve1, uint poolLiquidity) = PoolManager(poolManager).pools(id);
        
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
        testCreatePool();
        vm.startPrank(user1);

        vm.expectRevert("Pool already exists");
        PoolManager(poolManager).createPool(token0, token1, fee);

        vm.stopPrank();
    }

    function testAddFirstLiquidity() public {
        testCreatePool();
        vm.startPrank(user1);

        uint amount0 = 10 * 1e18;
        uint amount1 = 10000 * 1e18;
        bytes32 id = _returnId();

        (,,,,,pool.liquidity) = PoolManager(poolManager).pools(id);
        uint poolLiquidityBefore = pool.liquidity;
        uint token0BeforeUser = MockERC20(token0).balanceOf(user1);
        uint token1BeforeUser = MockERC20(token1).balanceOf(user1);
        uint token0BeforePool = MockERC20(token0).balanceOf(poolManager);
        uint token1BeforePool = MockERC20(token1).balanceOf(poolManager);

        PoolManager(poolManager).addLiquidity(id, amount0, amount1, address(this));
        uint liquidity = Math.sqrt(amount0 * amount1);

        (,,,,,pool.liquidity) = PoolManager(poolManager).pools(id);
        uint userLiquidityPool = PoolManager(poolManager).liquidity(id, address(this));

        assertEq(pool.liquidity, poolLiquidityBefore + liquidity, "Invalid amout of pool liquidity");
        assertEq(MockERC20(token0).balanceOf(user1), token0BeforeUser - amount0, "Invalid amout of token0 user");
        assertEq(MockERC20(token1).balanceOf(user1), token1BeforeUser - amount1, "Invalid amout of token1 user");
        assertEq(MockERC20(token0).balanceOf(poolManager), token0BeforePool + amount0, "Invalid amout of token0 pool");
        assertEq(MockERC20(token1).balanceOf(poolManager), token1BeforePool + amount1, "Invalid amout of token1 pool");
        assertEq(userLiquidityPool, liquidity - 1000, "Invalid amount pool liquidity owned by user");

        vm.stopPrank();
    }


    function testAddOtherLiquidity() public {
        testCreatePool();
        vm.startPrank(user1);
        bytes32 id = _returnId();
        PoolManager(poolManager).addLiquidity(id, 1 * 1e18, 1000 * 1e18, address(this));

        uint amount0 = 5 * 1e18;
        uint amount1 = 10000 * 1e18;

        (,,,,,pool.liquidity) = PoolManager(poolManager).pools(id);
        uint poolLiquidityBefore = pool.liquidity;
        uint userLiquidityPoolBefore = PoolManager(poolManager).liquidity(id, address(this));
        uint token0BeforeUser = MockERC20(token0).balanceOf(user1);
        uint token1BeforeUser = MockERC20(token1).balanceOf(user1);
        uint token0BeforePool = MockERC20(token0).balanceOf(poolManager);
        uint token1BeforePool = MockERC20(token1).balanceOf(poolManager);

        PoolManager(poolManager).addLiquidity(id, amount0, amount1, address(this));
        (amount0, amount1) = _calculateLiquidity(id, amount0, amount1);
        uint liquidity = Math.sqrt(amount0 * amount1);

        (,,,,,pool.liquidity) = PoolManager(poolManager).pools(id);
        uint userLiquidityPoolAfter = PoolManager(poolManager).liquidity(id, address(this));

        assertEq(pool.liquidity, poolLiquidityBefore + liquidity, "Invalid amout of pool liquidity");
        assertEq(MockERC20(token0).balanceOf(user1), token0BeforeUser - amount0, "Invalid amout of token0 user");
        assertEq(MockERC20(token1).balanceOf(user1), token1BeforeUser - amount1, "Invalid amout of token1 user");
        assertEq(MockERC20(token0).balanceOf(poolManager), token0BeforePool + amount0, "Invalid amout of token0 pool");
        assertEq(MockERC20(token1).balanceOf(poolManager), token1BeforePool + amount1, "Invalid amout of token1 pool");
        assertEq(userLiquidityPoolAfter, userLiquidityPoolBefore + liquidity, "Invalid amount pool liquidity owned by user");

        vm.stopPrank();
    }
}