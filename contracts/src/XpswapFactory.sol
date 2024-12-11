// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "../lib/Math.sol";

import "../interfaces/IERC20.sol";
import "./XpswapERC20.sol";
import "./XpswapPool.sol";


contract XpswapFactory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPools;
    address[] public allPools;

    event PoolCreated(address tokenA, address tokenB, address pool, uint);

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }
    
    function allPoolsLength() external view returns (uint) {
        return allPools.length;
    }

    function createPool(address tokenA_, address tokenB_) public {
        require(tokenA_ != tokenB_, "Factory: Duplicate tokens");
        require(tokenA_ != address(0), "Factory: Invalid token A address");
        require(tokenB_ != address(0), "Factory: Invalid token B address");

        (address tokenA, address tokenB) = tokenA_ < tokenB_ ? (tokenA_, tokenB_) : (tokenB_, tokenA_);
        
        require(getPools[tokenA][tokenB] == address(0), "Factory: Duplicate aPools");

        bytes memory bytecode = type(XpswapPool).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(tokenA, tokenB));

        address pool;

        assembly {
            pool := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        XpswapPool(pool).initialize(tokenA, tokenB);

        getPools[tokenA][tokenB] = pool;
        getPools[tokenB][tokenA] = pool;

        allPools.push(pool);

        emit PoolCreated(tokenA, tokenB, address(getPools[tokenA][tokenB]));
    }

    function setFeeTo(address _feeTo) public {
        require(msg.sender == feeToSetter, "Factory: FeeToSetter only");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'Factory: FeeToSetter only');
        feeToSetter = _feeToSetter;
    }
}