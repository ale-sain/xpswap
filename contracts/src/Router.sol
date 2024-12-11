// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IFactory.sol";
import "../interfaces/IPool.sol";

contract Router {
    address public factory;
    address public WETH;

    constructor() {
        factory = msg.sender;
    }


    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
    }

    function _addLiquidity(address tokenA,address tokenB,uint amountADesired,uint amountBDesired,uint amountAMin,uint amountBMin) private returns (uint amountA, uint amountB) {
        require(amountADesired > 0 && amountBDesired > 0, "Router: Insufficient amount desired");
        require(tokenA != address(0) && tokenB != address(0) && tokenA != tokenB, "Router: Invalid token address");

        address pool = IFactory(factory).getPool(tokenA, tokenB);
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

    function addLiquidity(address tokenA,address tokenB,uint amountADesired,uint amountBDesired,uint amountAMin,uint amountBMin,address to,uint deadline) external override returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pool = IFactory(factory).getPool(tokenA, tokenB);
        _safeTransferFrom(tokenA, msg.sender, pool, amountA);
        _safeTransferFrom(tokenB, msg.sender, pool, amountB);
        liquidity = IPool(pool).mint(to);
    }
}