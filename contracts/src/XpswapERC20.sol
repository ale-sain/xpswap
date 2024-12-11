// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "../interfaces/IERC20.sol";
import {console} from "forge-std/console.sol";

contract XpswapERC20 is IERC20 {
    string public name = "Xpswap";
    string public symbol = "XP";
    uint8 public decimals = 18;
    
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor() {}

    function transfer(address to, uint256 value) public override virtual returns (bool) {
        return _transfer(msg.sender, to, value);
    }

    function approve(address spender, uint256 value) public override returns (bool) {
        return _approve(msg.sender, spender, value, true);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        
        return true;
    }

    function _mint(address to, uint256 value) internal returns (bool) {
        balanceOf[to] += value;
        totalSupply += value;

        emit Transfer(address(0), to, value);

        return true;
    }

    function _burn(address from, uint256 value) internal returns (bool) {
        require(from != address(0), "XpswapERC20: Invalid sender address");

        balanceOf[from] -= value;
        totalSupply -= value;

        emit Transfer(from, address(0), value);

        return true;
    }
    
    function _approve(address owner, address spender, uint256 value, bool emitEvent) private returns (bool) {
        require(owner != address(0), "Approve ERC20: Invalid approver address");
        require(spender != address(0), "Approve ERC20: Invalid spender address");

        allowance[owner][spender] = value;

        if (emitEvent) {
            emit Approval(owner, spender, value);
        }

        return true;
    }

    function _transfer(address from, address to, uint256 value) internal returns (bool) {
        require(from != address(0), "XpswapERC20: Invalid sender address");
        require(to != address(0), "XpswapERC20: Invalid receiver address");
        require(balanceOf[from] >= value, "XpswapERC20: transfer amount exceeds balance");

        balanceOf[from] -= value;
        balanceOf[to] += value;
        
        emit Transfer(from, to, value);

        return true;
    }

    function _spendAllowance(address owner, address spender, uint256 value) private {
        uint256 currentAllowance = allowance[owner][spender];
        if (currentAllowance < type(uint256).max) {
            require(allowance[owner][msg.sender] >= value, "XpswapERC20: transfer amount exceeds allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}
