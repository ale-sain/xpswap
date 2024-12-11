// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IXpswapERC20.sol";

// Can you transform following code into an corresponding interface?
interface IPool is IXpswapERC20 {
    function tokenA() external view returns (IERC20);
    function tokenB() external view returns (IERC20);
    function reserveA() external view returns (uint112);
    function reserveB() external view returns (uint112);
    function priceACumulativeLast() external view returns (IERC20);
    function priceBCumulativeLast() external view returns (IERC20);

    event Mint(address indexed to, uint amountAIn, uint amountBIn);
    event Burn(address indexed from, address indexed to, uint amountAOut, uint amountBOut);
    event Swap(
        address indexed from,
        address indexed to,
        uint amountAIn,
        uint amountBIn, 
        uint amountAOut,
        uint amountBOut
    );
    event Sync(uint reserveA, uint reserveB);

    function initialize(address tokenA_, address tokenB_) external; 
    function getReserves() external view returns (uint112, uint112);

    function mint(address to) external;
    function burn(address to) external;
    function swap(uint amountAOut, uint amountBOut, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;
}