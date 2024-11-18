// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "forge-std/console.sol";


contract XpswapERC20 is IERC20 {
    string public name = "Xpswap";
    string public symbol = "XP";
    uint8 public decimals = 18;
    
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor() {}

    function transfer(address to, uint256 value) public override returns (bool) {
        return _transfer(msg.sender, to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        require(allowance[from][msg.sender] >= value, "Not enough token approved");
        
        _transfer(from, to, value);
        allowance[from][msg.sender] -= value;
        
        return true;
    }

    function approve(address spender, uint256 value) public override returns (bool) {
        allowance[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);

        return true;
    }

    function _mint(address to, uint256 value) internal returns (bool) {
        require(to != address(0), "Invalid receiver address");

        balanceOf[to] += value;
        totalSupply += value;

        emit Transfer(address(0), to, value);

        return true;
    }

    function _burn(address from, uint256 value) internal returns (bool) {
        require(from != address(0), "Invalid sender address");

        _transfer(from, address(0), value);

        totalSupply -= value;
        return true;
    }

function _transfer(address from, address to, uint256 value) private returns (bool) {
    console.log("Transfer called");
    console.log("From:", from);
    console.log("To:", to);
    console.log("Value:", value);
    console.log("Balance of sender (from):", balanceOf[from]);

    require(balanceOf[from] >= value, "Not enough token");

    balanceOf[from] -= value;
    balanceOf[to] += value;

    emit Transfer(from, to, value);
    return true;
}
}
