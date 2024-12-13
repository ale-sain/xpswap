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

    function addLiquidity(address tokenA, address tokenB, uint amountA, uint amountB, uint8 fee, address to) public {
        require(amountA > 0 && amountB > 0, "Router: Insufficient amount desired");
        require(tokenA != address(0) && tokenB != address(0) && tokenA != tokenB, "Router: Invalid token address");

        (address _tokenA, address _tokenB, uint _amountA, uint _amountB) = tokenA < tokenB ? (tokenA, tokenB, amountA, amountB) : (tokenB, tokenA, amountB, amountA);
        address pool = IFactory(factory).getPool(_tokenA, _tokenB);

        uint finalAmountA = _amountA;
        uint finalAmountB = _amountB;

        if (pool == address(0)) {
            IFactory(factory).createPool(_tokenA, _tokenB, fee);
        }
        else {
            (uint reserveA, uint reserveB) = IPool(pool).getReserves();
            uint liquidity = IPool(pool).totalSupply();

            uint ratioA = _amountA * liquidity / reserveA;
            uint ratioB = _amountB * liquidity / reserveB;
            if (ratioB < ratioA) {
                finalAmountA = _amountB * reserveA / reserveB;
            } else {
                finalAmountB = _amountA * reserveB / reserveA;
            }
        }

        require(finalAmountA > 0 && finalAmountB > 0, "Router: Invalid amount of token");

        _safeTransferFrom(_tokenA, msg.sender, pool, finalAmountA);
        _safeTransferFrom(_tokenB, msg.sender, pool, finalAmountB);
        IPool(pool).mint(to);
    }

    function removeLiquidity(address tokenA, address tokenB, address from, uint value) public {

    }
}