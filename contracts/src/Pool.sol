// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/ICallee.sol";
import "../interfaces/IFactory.sol";
import "./XpswapERC20.sol";

import "../lib/Math.sol";
import "../lib/UQ112x112.sol";

import "forge-std/console.sol";

contract XpswapPool is XpswapERC20 {
    address public factory;
    address public tokenA;
    address public tokenB;

    uint public reserveA;
    uint public reserveB;
    uint8 private fee;
    uint24 private minimumLiquidity = 1000;
    
    bool private mutex = false;

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

    constructor(address tokenA_, address tokenB_, uint8 fee_) {
        factory = msg.sender;
        tokenA = tokenA_;
        tokenB = tokenB_;
        fee = fee_;
    }

    modifier reentrancyGuard() {
        require(mutex == false, "Pool: Reentrance forbidden");
        mutex = true;
        _;
        mutex = false;
    }

    function mint(address to) public reentrancyGuard {
        uint liquidityIn = 0;
        uint liquidity = totalSupply;
        uint amountA = uint(IERC20(tokenA).balanceOf(address(this))) - reserveA;
        uint amountB = uint(IERC20(tokenB).balanceOf(address(this))) - reserveB;

        require(amountA > 0, "Pool: Invalid amount for token A");
        require(amountB > 0, "Pool: Invalid amount for token B");
        
        if (liquidity == 0) {
            liquidityIn = Math.sqrt(amountA * amountB) - minimumLiquidity;
            _mint(address(0), minimumLiquidity);
        }

        _reserveUpdate();
        _mint(to, liquidityIn);

        emit Mint(to, amountA, amountB);
    }

    function burn(address to) public reentrancyGuard {
        uint liquidityOut = balanceOf[address(this)];
        uint _totalSupply = totalSupply;
        uint _reserveA = reserveA;
        uint _reserveB = reserveB;

        require(liquidityOut > 0, "Pool: Invalid amount for token LP");
        require(liquidityOut <= _totalSupply - minimumLiquidity, "Pool: Invalid liquidity amount");

        uint amountA = (_reserveA * liquidityOut) / _totalSupply;
        uint amountB = (_reserveB * liquidityOut) / _totalSupply;

        require(amountA < _reserveA, "Pool: Insufficient liquidity in pool");
        require(amountB < _reserveB, "Pool: Insufficient liquidity in pool");

        _safeTransfer(tokenA, to, amountA);
        _safeTransfer(tokenB, to, amountB);
        _reserveUpdate();
        _burn(address(this), liquidityOut);

        emit Burn(msg.sender, to, amountA, amountB);
    }

    function swap(uint amountAOut, uint amountBOut, address to) public reentrancyGuard {
        uint _reserveA = reserveA;
        uint _reserveB = reserveB;
        uint8 _fee = fee;

        require(amountAOut > 0 || amountBOut > 0, "Pool: Invalid output amount");
        require(amountAOut < _reserveA && amountBOut < _reserveB, "Pool: Insufficient liquidity");

        if (amountAOut > 0 ) _safeTransfer(tokenA, to, amountAOut);
        if (amountBOut > 0 ) _safeTransfer(tokenB, to, amountBOut);
        
        uint balanceA = IERC20(tokenA).balanceOf(address(this));
        uint balanceB = IERC20(tokenB).balanceOf(address(this));

        uint amountAIn = amountBOut > 0 ? (balanceA - _reserveA) * (1000 - _fee) / 1000 : 0;
        uint amountBIn = amountAOut > 0 ? (balanceB - _reserveB) * (1000 - _fee) / 1000 : 0;
        require(amountAIn > 0 || amountBIn > 0, "Pool: Insufficient input amount");

        // require((balanceA - amountAOut) * (balanceB - amountBOut) >= lastK , "Pool: invalid constant product k");

        _reserveUpdate();

        emit Swap(msg.sender, to, amountAIn, amountBIn, amountAOut, amountBOut);
    }

    function _reserveUpdate() private {
        reserveA = IERC20(tokenA).balanceOf(address(this));
        reserveB = IERC20(tokenB).balanceOf(address(this));
    }


    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
    }

}
