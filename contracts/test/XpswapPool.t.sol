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
    XpswapPool private xpswapPoolContract;
    nawakERC20 private tokenA;
    nawakERC20 private tokenB;

    address private user1 = address(0x1);
    address private user2 = address(0x2);
    address private user3 = address(0x3);

    function setUp() public {
        tokenA = new nawakERC20("Dai", "DAI");
        tokenB = new nawakERC20("Starknet", "STRK");
        xpswapPoolContract = new XpswapPool(address(tokenA), address(tokenB));

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
        tokenA.approve(address(xpswapPoolContract), 100);
        vm.prank(user1);
        tokenB.approve(address(xpswapPoolContract), 1000);
        vm.prank(user1);
        xpswapPoolContract.addLiquidity(100, 1000);

        assertEq(xpswapPoolContract.balanceOf(user1), 200, "LP token balance incorrect");
        assertEq(tokenA.balanceOf(address(xpswapPoolContract)), 100, "Token A reserve incorrect");
        assertEq(tokenB.balanceOf(address(xpswapPoolContract)), 1000, "Token B reserve incorrect");
    }

    function test_removeLiquidity() public {
        test_addLiquidity();

        vm.prank(user1);
        xpswapPoolContract.removeLiquidity(100);

        assertEq(xpswapPoolContract.balanceOf(user1), 100, "Remaining LP token balance incorrect");
        assertEq(tokenA.balanceOf(address(xpswapPoolContract)), 50, "Token A reserve incorrect after removal");
        assertEq(tokenB.balanceOf(address(xpswapPoolContract)), 500, "Token B reserve incorrect after removal");
        assertEq(tokenA.balanceOf(user1), 950, "User1 Token A balance incorrect after removal");
        assertEq(tokenB.balanceOf(user1), 500, "User1 Token B balance incorrect after removal");
    }


    function test_addLiquidityFailsWithZeroAmounts() public {
        vm.prank(user1);
        tokenA.approve(address(xpswapPoolContract), 0);
        vm.prank(user1);
        tokenB.approve(address(xpswapPoolContract), 1000);

        vm.prank(user1);
        vm.expectRevert("Invalid amount for token A");
        xpswapPoolContract.addLiquidity(0, 1000);
    }


    function test_removeLiquidityFailsWithZeroDeposit() public {
        test_addLiquidity();

        vm.prank(user1);
        vm.expectRevert("Insufficient deposit");
        xpswapPoolContract.removeLiquidity(0);
    }


    function test_removeLiquidityFailsWithExcessiveAmount() public {
        test_addLiquidity();

        vm.prank(user1);
        vm.expectRevert("Invalid deposit amount");
        xpswapPoolContract.removeLiquidity(300); // Exceeds LP balance
    }

    function test_multipleUsersAddLiquidity() public {
        vm.prank(user1);
        tokenA.approve(address(xpswapPoolContract), 100);
        vm.prank(user1);
        tokenB.approve(address(xpswapPoolContract), 1000);
        vm.prank(user1);
        xpswapPoolContract.addLiquidity(100, 1000);

        vm.prank(user2);
        tokenA.approve(address(xpswapPoolContract), 50);
        vm.prank(user2);
        tokenB.approve(address(xpswapPoolContract), 500);
        vm.prank(user2);
        xpswapPoolContract.addLiquidity(50, 500);

        assertEq(xpswapPoolContract.balanceOf(user1), 200, "User1 LP token balance incorrect");
        assertEq(xpswapPoolContract.balanceOf(user2), 100, "User2 LP token balance incorrect");
        assertEq(tokenA.balanceOf(address(xpswapPoolContract)), 150, "Token A reserve incorrect");
        assertEq(tokenB.balanceOf(address(xpswapPoolContract)), 1500, "Token B reserve incorrect");
    }

    // function test_removeLiquidityOverflow() public {
    //     // Simule un utilisateur avec un très grand montant de liquidités ajoutées
    //     vm.prank(user3);
    //     tokenA.approve(address(xpswapPoolContract), type(uint256).max);
    //     vm.prank(user3);
    //     tokenB.approve(address(xpswapPoolContract), type(uint256).max);
        
    //     // Ajout de liquidités avec des valeurs maximales
    //     vm.prank(user3);
    //     xpswapPoolContract.addLiquidity(type(uint256).max / 2, type(uint256).max / 2);

    //     // Simule un overflow potentiel lors de removeLiquidity
    //     vm.expectRevert("Panic: Arithmetic overflow or underflow"); // Solidity lève ce message pour un overflow
    //     vm.prank(user3);
    //     xpswapPoolContract.removeLiquidity(type(uint256).max);
    // }



    // // Test edge case: Adding liquidity with a very large amount
    // function test_addLiquidityLargeAmounts() public {
    //     vm.prank(user3);
    //     tokenA.approve(address(xpswapPoolContract), type(uint256).max);
    //     vm.prank(user3);
    //     tokenB.approve(address(xpswapPoolContract), type(uint256).max);
    //     vm.prank(user3);
    //     xpswapPoolContract.addLiquidity(1e18, 1e18);

    //     assertEq(tokenA.balanceOf(address(xpswapPoolContract)), 1e18, "Token A reserve incorrect with large amount");
    //     assertEq(tokenB.balanceOf(address(xpswapPoolContract)), 1e18, "Token B reserve incorrect with large amount");
    // }
}
