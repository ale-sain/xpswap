// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/MockERC20.sol";


contract BasicTest is Test {
    address user1;
    address user2;
    
    address tokenA;
    address tokenB;

    address pool;

    function setUp() public {
        tokenA = address(MockERC20("USDT", "USDT", 18));
        tokenB = address(MockERC20("DAI", "DAI", 18));
        lps = new liquidityPools();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        tokenA.mint(user1, 100 * 1e18);
        tokenB.mint(user1, 100000 * 1e18);
        
        tokenA.mint(user2, 10 * 1e18);
    }

    function createPool() public {
        vm.startPrank(user1);

        poolManager.createPool(tokenA, tokenB);
        pool = poolManager.getPool(tokenA, tokenB);

        assertNotEq(pool, address(0), "Pool inexistant");
        // assertEq(pool.reserveA(), 500 ether - outputAmount, "Incorrect reserve for token A");
        vm.stopPrank();
    }

    function addLiquidity() public {
        createPool();
        vm.startPrank(user1);

        uint tokenAbefore = tokenA.balanceOf(user1);
        uint tokenBbefore = tokenB.balanceOf(user1);

        pool.addLiquidity

        vm.stopPrank();
    }
}