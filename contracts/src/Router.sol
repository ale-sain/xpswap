// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IRouter.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IPool.sol";
import "../XpswapPool.sol";

contract Router is IRouter {
    address public factory;
    address public WETH;

    constructor() {
        factory = msg.sender;
    }

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    function findPool(address factory, address tokenA, address tokenB) internal pure returns (address pool) {
        (address tA, address tB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        pool = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(tA, tB)),
                hex'tocomputeoffchainoncesmartcontractsfinishedddddddddddddddddddddd'
            ))));
    }

    function _safeTransferFrom(IERC20 token, address from, address to, uint256 amount) private {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
    }

    function _addLiquidity(address tokenA,address tokenB,uint amountADesired,uint amountBDesired,uint amountAMin,uint amountBMin) private returns (uint amountA, uint amountB) {
        require(amountADesired > 0 && amountBDesired > 0, "Router: Insufficient amount desired");
        require(tokenA != address(0) && tokenB != address(0) && tokenA != tokenB, "Router: Invalid token address");

        address pool = findPool(factory, tokenA, tokenB);
        amountA = amountADesired;
        amountB = amountBDesired;

        if (pool == address(0)) {
            IFactory(factory).createPool(tokenA, tokenB);
        }
        else {
            (uint reserveA, uint reserveB) = IPool(pool).getReserves();
            uint liquidity = IPool(pool).totalSupply();

            uint ratioA = amountA * liquidity / reserveA;
            uint ratioB = amountB * liquidity / reserveB;
            if (ratioB < ratioA) {
                amountA = amountB * reserveA / reserveB;
            } else {
                amountB = amountA * reserveB / reserveA;
            }
        }
        require(amountA > 0 && amountB > 0, "Router: Invalid amount of token");
        require(amountA >= amountAMin && amountB >= amountBMin, "Router: Invalid minimum amount of token");
    }

    function addLiquidity(address tokenA,address tokenB,uint amountADesired,uint amountBDesired,uint amountAMin,uint amountBMin,address to,uint deadline) external override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pool = findPool(factory, tokenA, tokenB);
        _safeTransferFrom(tokenA, msg.sender, pool, amountA);
        _safeTransferFrom(tokenB, msg.sender, pool, amountB);
        liquidity = IPool(pool).mint(to);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    // function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}