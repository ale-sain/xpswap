// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/XpswapPool.sol";

contract nawakERC20 is XpswapERC20 {
    constructor(string memory name_, string memory ticker_) XpswapERC20() {
        name = name_;
        symbol = ticker_;
        _mint(msg.sender, 10000);
    }
}

contract XpswapPoolTest is Test {
    XpswapPool private xpswapPoolContract;
    nawakERC20 private tokenA;
    nawakERC20 private tokenB;

    // Set up the contract before tests
    function setUp() public {
        tokenA = new nawakERC20("Dai", "DAI");
        tokenB = new nawakERC20("Starknet", "STRK");
        xpswapPoolContract = new XpswapPool(address(tokenA), address(tokenB));
    }

    function test_balance() public {
        tokenA.approve(address(xpswapPoolContract), 100);
        tokenB.approve(address(xpswapPoolContract), 10000);
        xpswapPoolContract.addLiquidity(100, 10000);
        assertEq(xpswapPoolContract.balanceOf(address(this)), 200);
        assertEq(tokenA.balanceOf(address(xpswapPoolContract)), 100);
        assertEq(tokenB.balanceOf(address(xpswapPoolContract)), 10000);
    }

    
}
