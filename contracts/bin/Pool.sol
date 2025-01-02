// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Pool {
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

    function createPool(address tokenA_, address tokenB_) public {
        require(tokenA_ != tokenB_, "Factory: Duplicate tokens");
        require(tokenA_ != address(0), "Factory: Invalid token A address");
        require(tokenB_ != address(0), "Factory: Invalid token B address");

        (address tokenA, address tokenB) = tokenA_ < tokenB_ ? (tokenA_, tokenB_) : (tokenB_, tokenA_);
        
        require(getPools[tokenA][tokenB] == address(0), "Factory: Duplicate aPools");

        address pool = address(new XpswapPool(tokenA, tokenB));

        getPools[tokenA][tokenB] = pool;
        getPools[tokenB][tokenA] = pool;

        allPools.push(pool);

        emit PoolCreated(tokenA, tokenB, address(getPools[tokenA][tokenB]), allPools.length);
    }

        modifier reentrancyGuard() {
        require(mutex == false, "Pool: Reentrance forbidden");
        mutex = true;
        _;
        mutex = false;
    }

    function getReserves() public view returns (uint112, uint112) {
        uint112 _reserveA = reserveA;
        uint112 _reserveB = reserveB;
        return (_reserveA, _reserveB);
    }

    function mint(address to) public reentrancyGuard {
        (uint112 _reserveA, uint112 _reserveB) = getReserves();

        uint112 amountA = uint112(tokenA.balanceOf(address(this))) - _reserveA;
        uint112 amountB = uint112(tokenB.balanceOf(address(this))) - _reserveB;

        require(amountA > 0, "Pool: Invalid amount for token A");
        require(amountB > 0, "Pool: Invalid amount for token B");
        
        uint liquidityIn = 0;
        uint liquidity = totalSupply;
        uint effectiveAmountA = amountA;
        uint effectiveAmountB = amountB;

        bool feeOn = _mintFee(_reserveA, _reserveB);
        
        if (liquidity == 0) {
            uint liquidityMinimum = 1000;
            liquidityIn = Math.sqrt(amountA * amountB) - liquidityMinimum;
            _mint(address(0), liquidityMinimum);
        }
        else {
            uint ratioA = amountA * liquidity / _reserveA;
            uint ratioB = amountB * liquidity / _reserveB;
            liquidityIn = Math.min(ratioA, ratioB);
            if (ratioB < ratioA) {
                effectiveAmountA = amountB * _reserveA / _reserveB;
                _safeTransfer(tokenA, to, amountA - effectiveAmountA);
            } else {
                effectiveAmountB = amountA * _reserveB / _reserveA;
                _safeTransfer(tokenB, to, amountB - effectiveAmountB);
            }
        }

        _reserveUpdate();
        if (feeOn) lastK = uint(reserveA) * uint(reserveB);
    
        require(liquidity > 0, "Pool: insufficient liquidity mint");
        _mint(to, liquidityIn);

        emit Mint(to, effectiveAmountA, effectiveAmountB);
    }

    function burn(address to) public reentrancyGuard {
        (uint112 _reserveA, uint112 _reserveB) = getReserves();
        uint _totalSupply = totalSupply;
        bool feeOn = _mintFee(_reserveA, _reserveB);
        uint liquidityOut = balanceOf[address(this)];

        require(liquidityOut > 0, "Pool: Invalid amount for token LP");
        require(liquidityOut <= _totalSupply, "Pool: Invalid liquidity amount");

        uint amountA = (_reserveA * liquidityOut) / _totalSupply;
        uint amountB = (_reserveB * liquidityOut) / _totalSupply;

        require(amountA < _reserveA, "Pool: Insufficient liquidity in pool");
        require(amountB < _reserveB, "Pool: Insufficient liquidity in pool");

        _safeTransfer(tokenA, to, amountA);
        _safeTransfer(tokenB, to, amountB);

        _reserveUpdate();
        if (feeOn) lastK = uint(reserveA) * uint(reserveB);
    
        _burn(address(this), liquidityOut);

        emit Burn(msg.sender, to, amountA, amountB);
    }

    function swap(uint amountAOut, uint amountBOut, address to) public reentrancyGuard {
        (uint _reserveA, uint _reserveB) = getReserves();
        uint8 _txFees = txFees;

        require(amountAOut > 0 || amountBOut > 0, "Pool: Invalid output amount");
        require(amountAOut < _reserveA && amountBOut < _reserveB, "Pool: Insufficient liquidity");

        if (amountAOut > 0 ) _safeTransfer(tokenA, to, amountAOut);
        if (amountBOut > 0 ) _safeTransfer(tokenB, to, amountBOut);
        
        uint balanceA = tokenA.balanceOf(address(this));
        uint balanceB = tokenB.balanceOf(address(this));

        uint amountAIn = amountBOut > 0 ? (balanceA - _reserveA) * (1000 - _txFees) / 1000 : 0;
        uint amountBIn = amountAOut > 0 ? (balanceB - _reserveB) * (1000 - _txFees) / 1000 : 0;
        require(amountAIn > 0 || amountBIn > 0, "Pool: Insufficient input amount");

        require((balanceA - amountAOut) * (balanceB - amountBOut) >= lastK , "Pool: invalid constant product k");

        _reserveUpdate();

        emit Swap(msg.sender, to, amountAIn, amountBIn, amountAOut, amountBOut);
    }

    function _reserveUpdate() private {
        uint balanceA = tokenA.balanceOf(address(this));
        uint balanceB = tokenB.balanceOf(address(this));
        reserveA = uint112(balanceA);
        reserveB = uint112(balanceB);
    }

    function _mintFee(uint112 _reserveA, uint112 _reserveB) private returns (bool) {
        address feeTo = IFactory(factory).feeTo();
        bool feeOn = feeTo != address(0);

        uint rootCurrK = Math.sqrt(_reserveA * _reserveB);
        uint rootLastK = Math.sqrt(lastK);

        if (feeOn) {
            if (rootCurrK > rootLastK) {
                uint numerator = (rootCurrK - rootLastK) * totalSupply;
                uint denominator = rootCurrK * 5 + rootLastK;
                uint feeOut = numerator / denominator;
                if (feeOut > 0) _mint(feeTo, feeOut);
            }
        }
        else
            lastK = 0;

        return feeOn;
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) private {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pool: Transfer failed');
    }

    

}