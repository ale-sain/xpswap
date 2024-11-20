// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/XpswapPool.sol";

contract nawakERC20 is XpswapERC20 {
    constructor(string memory name_, string memory ticker_) XpswapERC20() {
        name = name_;
        symbol = ticker_;
        _mint(msg.sender, type(uint256).max); // Mint 10,000 tokens with 18 decimals
    }
}

contract XpswapPoolTest is Test {
    XpswapPool private pool;
    nawakERC20 private tokenA;
    nawakERC20 private tokenB;

    address private user1 = address(0x1);
    address private user2 = address(0x2);
    address private user3 = address(0x3);

    function setUp() public {
        tokenA = new nawakERC20("Dai", "DAI");
        tokenB = new nawakERC20("Starknet", "STRK");
        pool = new XpswapPool(address(tokenA), address(tokenB));

        // Distribute initial tokens to user1 and user2
        tokenA.transfer(user1, 1000);
        tokenB.transfer(user1, 1000);
        tokenA.transfer(user2, 500);
        tokenB.transfer(user2, 500);

        // tokenA.transfer(user3, type(uint256).max);
        // tokenB.transfer(user3, type(uint256).max);
    }


    function test_addLiquidity() public {
        vm.prank(user1);
        tokenA.approve(address(pool), 100);
        vm.prank(user1);
        tokenB.approve(address(pool), 1000);
        vm.prank(user1);
        pool.addLiquidity(100, 1000);

        assertEq(pool.balanceOf(user1), 200, "LP token balance incorrect");
        assertEq(tokenA.balanceOf(address(pool)), 100, "Token A reserve incorrect");
        assertEq(tokenB.balanceOf(address(pool)), 1000, "Token B reserve incorrect");
    }

    function test_removeLiquidity() public {
        test_addLiquidity();

        vm.prank(user1);
        pool.removeLiquidity(100);

        assertEq(pool.balanceOf(user1), 100, "Remaining LP token balance incorrect");
        assertEq(tokenA.balanceOf(address(pool)), 50, "Token A reserve incorrect after removal");
        assertEq(tokenB.balanceOf(address(pool)), 500, "Token B reserve incorrect after removal");
        assertEq(tokenA.balanceOf(user1), 950, "User1 Token A balance incorrect after removal");
        assertEq(tokenB.balanceOf(user1), 500, "User1 Token B balance incorrect after removal");
    }


    function test_addLiquidityFailsWithZeroAmounts() public {
        vm.prank(user1);
        tokenA.approve(address(pool), 0);
        vm.prank(user1);
        tokenB.approve(address(pool), 1000);

        vm.prank(user1);
        vm.expectRevert("Invalid amount for token A");
        pool.addLiquidity(0, 1000);
    }


    function test_removeLiquidityFailsWithZeroDeposit() public {
        test_addLiquidity();

        vm.prank(user1);
        vm.expectRevert("Insufficient deposit");
        pool.removeLiquidity(0);
    }


    function test_removeLiquidityFailsWithExcessiveAmount() public {
        test_addLiquidity();

        vm.prank(user1);
        vm.expectRevert("Invalid deposit amount");
        pool.removeLiquidity(300); // Exceeds LP balance
    }

    function test_multipleUsersAddLiquidity() public {
        vm.prank(user1);
        tokenA.approve(address(pool), 100);
        vm.prank(user1);
        tokenB.approve(address(pool), 1000);
        vm.prank(user1);
        pool.addLiquidity(100, 1000);

        vm.prank(user2);
        tokenA.approve(address(pool), 50);
        vm.prank(user2);
        tokenB.approve(address(pool), 500);
        vm.prank(user2);
        pool.addLiquidity(50, 500);

        assertEq(pool.balanceOf(user1), 200, "User1 LP token balance incorrect");
        assertEq(pool.balanceOf(user2), 100, "User2 LP token balance incorrect");
        assertEq(tokenA.balanceOf(address(pool)), 150, "Token A reserve incorrect");
        assertEq(tokenB.balanceOf(address(pool)), 1500, "Token B reserve incorrect");
    }

    // function test_removeLiquidityOverflow() public {
    //     // Simule un utilisateur avec un très grand montant de liquidités ajoutées
    //     vm.prank(user3);
    //     tokenA.approve(address(pool), type(uint256).max);
    //     vm.prank(user3);
    //     tokenB.approve(address(pool), type(uint256).max);
        
    //     // Ajout de liquidités avec des valeurs maximales
    //     vm.prank(user3);
    //     pool.addLiquidity(type(uint256).max / 2, type(uint256).max / 2);

    //     // Simule un overflow potentiel lors de removeLiquidity
    //     vm.expectRevert("Panic: Arithmetic overflow or underflow"); // Solidity lève ce message pour un overflow
    //     vm.prank(user3);
    //     pool.removeLiquidity(type(uint256).max);
    // }



    // // Test edge case: Adding liquidity with a very large amount
    // function test_addLiquidityLargeAmounts() public {
    //     vm.prank(user3);
    //     tokenA.approve(address(pool), type(uint256).max);
    //     vm.prank(user3);
    //     tokenB.approve(address(pool), type(uint256).max);
    //     vm.prank(user3);
    //     pool.addLiquidity(1e18, 1e18);

    //     assertEq(tokenA.balanceOf(address(pool)), 1e18, "Token A reserve incorrect with large amount");
    //     assertEq(tokenB.balanceOf(address(pool)), 1e18, "Token B reserve incorrect with large amount");
    // }

    function testSwapTokenAForTokenB() public {
        test_addLiquidity();

        uint outputAmount = 5; // Amount of tokenA to receive
        uint inputAmount = (outputAmount * pool.reserveB()) / (pool.reserveA() - outputAmount);
        
        vm.prank(user2);
        tokenA.transfer(address(user1), 500); // remove all his token A token


        uint balanceB = tokenB.balanceOf(address(user2));

        vm.prank(user2);
        tokenB.approve(address(pool), inputAmount);

        vm.prank(user2);
        pool.swap(outputAmount, address(tokenA));

        assertEq(tokenA.balanceOf(address(user2)), outputAmount);
        assertEq(tokenB.balanceOf(address(user2)), balanceB - inputAmount);
        assertLt(pool.reserveA(), 1000); // Ensure tokenA reserve decreased
        assertGt(pool.reserveB(), 1000); // Ensure tokenB reserve increased
    }

    function testRevertOnInsufficientLiquidity() public {
        uint outputAmount = 2e18; // Exceeds pool reserve
        vm.expectRevert("Insufficient liquidity in pool");
        pool.swap(outputAmount, address(tokenB));
    }

    function testSwapFailsWithInsufficientApproval() public {
        test_addLiquidity();

        uint outputAmount = 10; // Amount of tokenA to receive
        uint inputAmount = (outputAmount * pool.reserveB()) / (pool.reserveA() - outputAmount);

        vm.prank(user2);
        tokenB.approve(address(pool), inputAmount - 1); // Approve less than required

        vm.prank(user2);
        vm.expectRevert("ERC20: Insufficient allowance");
        pool.swap(outputAmount, address(tokenA));
    }

    function testSwapFailsWithInsufficientBalance() public {
        test_addLiquidity();

        uint outputAmount = 10; // Amount of tokenA to receive
        uint inputAmount = (outputAmount * pool.reserveB()) / (pool.reserveA() - outputAmount);

        vm.prank(user2);
        tokenB.approve(address(pool), inputAmount);

        vm.prank(user2);
        tokenB.transfer(address(0xdead), 500); // Drain user2's balance

        vm.prank(user2);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        pool.swap(outputAmount, address(tokenA));
    }

    function testSwapFailsWithInvalidTokenAddress() public {
        test_addLiquidity();

        uint outputAmount = 10;

        vm.prank(user2);
        vm.expectRevert("Invalid token address");
        pool.swap(outputAmount, address(0x1234)); // Invalid token address
    }

    function testSwapFailsWithExcessiveOutputAmount() public {
        test_addLiquidity();

        uint outputAmount = pool.reserveA() + 1; // Exceeds available liquidity in tokenA

        vm.prank(user2);
        vm.expectRevert("Insufficient liquidity in pool");
        pool.swap(outputAmount, address(tokenA));
    }

    function testSwapFailsWhenOutputEqualsReserve() public {
        test_addLiquidity();

        uint outputAmount = pool.reserveA(); // Trying to empty all reserves

        vm.prank(user2);
        vm.expectRevert(); // Will revert due to division by zero in the inputAmount calculation
        pool.swap(outputAmount, address(tokenA));
    }

    function testSwapFailsWithZeroOutputAmount() public {
        test_addLiquidity();

        vm.prank(user2);
        vm.expectRevert(); // Likely no explicit error, but it should fail
        pool.swap(0, address(tokenA));
    }

}
