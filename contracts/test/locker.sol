// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/PoolManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ICallback} from "../src/ICallback.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint amount) public {
        _mint(to, amount);
    }
}

contract createPoolTest is Test, ICallback {
    struct Pool {
        address token0;
        address token1;
        uint reserve0;
        uint reserve1;
    }

    address user1;
    address user2;
    address poolManager;
    
    address token0;
    address token1;
    uint24 fee;

    Pool pool;

    function setUp() public {
        token0 = address(new MockERC20("USDT", "USDT"));
        token1 = address(new MockERC20("DAI", "DAI"));
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        poolManager = address(new PoolManager());

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        MockERC20(token0).mint(user1, 20 * 1e18);
        MockERC20(token1).mint(user1, 20000 * 1e18);

        vm.startPrank(user1);
        MockERC20(token0).approve(poolManager, type(uint256).max);
        MockERC20(token1).approve(poolManager, type(uint256).max);
        vm.stopPrank();
        
        MockERC20(token0).mint(user2, 10 * 1e18);
    }

    function _returnId() private view returns (bytes32) {
        (address token0_, address token1_) = token0 < token1 ? (token0, token1) : (token1, token0);
        return keccak256(abi.encodePacked(token0_, token1_));
    }

    function testLocker() public {
        uint256[] memory actions = new uint256[](1);
        actions[0] = 1;
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(token0, token1);

        PoolManager(poolManager).unlock(actions, data);
    }

    function executeAll(uint256[] calldata actions, bytes[] calldata data) public {
        require(actions.length == data.length, "Mismatched actions and data length");

        vm.startPrank(user1);

        for (uint256 i = 0; i < actions.length; i++) {
            if (actions[i] == 1) {
                // Décodage des données pour la création d'une pool
                (address tokenA, address tokenB) = abi.decode(data[i], (address, address));
                bytes32 id = PoolManager(poolManager).createPool(tokenA, tokenB);

                // Vérification des valeurs de la pool
                (pool.token0,,,) = PoolManager(poolManager).pools(id);
                assertEq(id, _returnId(), "Wrong id");
                assertNotEq(pool.token0, address(0), "Pool inexistant");
            } else {
                // revert("Unknown action");
            }
        }

        vm.stopPrank();
    }
}