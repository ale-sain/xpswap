// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/PoolManager.sol";
import "../lib/forge-std/src/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint amount) public {
        _mint(to, amount);
    }
}

contract PoolManagerTest is Test {
    address user1;
    address user2;
    address poolManager;
    
    address token0;
    address token1;
    address token2;

    function setUp() public {
        token0 = address(new MockERC20("USDT", "USDT"));
        token1 = address(new MockERC20("DAI", "DAI"));
        token2 = address(new MockERC20("ETH", "ETH"));

        poolManager = address(new PoolManager());

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        MockERC20(token0).mint(user1, 100000);
        MockERC20(token1).mint(user1, 100000);
        MockERC20(token2).mint(user1, 100000);

        vm.startPrank(user1);

        MockERC20(token0).approve(poolManager, type(uint256).max);
        MockERC20(token1).approve(poolManager, type(uint256).max);
        MockERC20(token2).approve(poolManager, type(uint256).max);
        
        (uint amount0_0, uint amount1_0) = (5000, 5000);
        bytes32 id_0 = PoolManager(poolManager).createPool(token0, token1);
        PoolManager(poolManager).addLiquidity(id_0, amount0_0, amount1_0);

        (uint amount0_1, uint amount1_1) = (5000, 5000);
        bytes32 id_1 = PoolManager(poolManager).createPool(token1, token2);
        PoolManager(poolManager).addLiquidity(id_1, amount0_1, amount1_1);
        
        bytes32 [] memory poolsId = new bytes32[](2);
        poolsId[0] = id_0;
        poolsId[1] = id_1;

        address[] memory tokens = new address[](3);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = token2;

        PoolManager(poolManager).updateContractState(poolsId);
        PoolManager(poolManager).updateContractBalance(tokens);

        vm.stopPrank();
        
        vm.startPrank(user2);

        MockERC20(token0).mint(user2, 2000);
        MockERC20(token1).mint(user2, 2000);
        MockERC20(token2).mint(user2, 2000);

        MockERC20(token0).approve(poolManager, type(uint256).max);
        MockERC20(token1).approve(poolManager, type(uint256).max);
        MockERC20(token2).approve(poolManager, type(uint256).max);

        vm.stopPrank();

    }

    function abs(int256 value) internal pure returns (uint256) {
        return value < 0 ? uint256(-value) : uint256(value);
    }

    function _getPoolData(bytes32 poolId, address user) internal view returns (int reserve0, int reserve1, int liquidity, int activeDelta) {
        (address token0_, address token1_,,) = PoolManager(poolManager).pools(poolId);

        reserve0 = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked(poolId, token0_)));
        reserve1 = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked(poolId, token1_)));
        liquidity = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked(poolId, user)));
        activeDelta = PoolManager(poolManager)._getTransientVariable(keccak256(abi.encodePacked("activeDelta")));
    }

    function testSwapInputMultiHop() public {
        vm.startPrank(user2);

        bytes32 poolId_0 = PoolManager(poolManager).getPoolId(address(token0), address(token1));
        (,, uint beforeReserve0_0, uint beforeReserve1_0) = PoolManager(poolManager).pools(poolId_0);

        uint amountIn_0 = 500;
        uint minAmountOut_0 = PoolManager(poolManager).getAmountOut(beforeReserve0_0, beforeReserve1_0, amountIn_0);

        // (address _token0, address _token1,,) = PoolManager(poolManager).pools(poolId_0);
        bool input_0 = true;
        bool zeroForOne = (token0 < token1) ? input_0 : !input_0;
        PoolManager(poolManager).swapWithInput(poolId_0, amountIn_0, minAmountOut_0, zeroForOne);

        bytes32 poolId_1 = PoolManager(poolManager).getPoolId(address(token1), address(token2));
        (,, uint beforeReserve0_1, uint beforeReserve1_1) = PoolManager(poolManager).pools(poolId_1);

        uint amountIn_1 = minAmountOut_0 ;
        uint minAmountOut_1 = PoolManager(poolManager).getAmountOut(beforeReserve0_1, beforeReserve1_1, amountIn_1);

        input_0 = true;
        zeroForOne = token1 < token2 ? input_0 : !input_0;
        PoolManager(poolManager).swapWithInput(poolId_1, amountIn_1, minAmountOut_1, zeroForOne);

        // Check updated reserves
        (int delta0_0, int delta1_0,,) = _getPoolData(poolId_0, user2);
        (int delta0_1, int delta1_1,,) = _getPoolData(poolId_1, user2);

        assertEq(abs(delta1_0), 500, "Reserve1_0 should increase");
        assertEq(abs(delta0_0), abs(delta0_1), "Reserve0_0 should == reserve0_1");
        assertEq(abs(delta0_0), amountIn_1, "Reserve0_0 should decrease");
        assertEq(abs(delta0_1), minAmountOut_0, "Reserve0_1 should increase");
        assertEq(abs(delta1_1), minAmountOut_1, "Reserve1_1 should decrease");

        vm.stopPrank();
    }

    function testSwapMultiPool() public {
        vm.startPrank(user2);

        bytes32 poolId = PoolManager(poolManager).getPoolId(address(token1), address(token2));
        (,, uint beforeReserve0, uint beforeReserve1) = PoolManager(poolManager).pools(poolId);

        uint amountIn_1 = 500;
        uint minAmountOut_1 = PoolManager(poolManager).getAmountOut(beforeReserve1, beforeReserve0, amountIn_1);

        PoolManager(poolManager).swapWithInput(poolId, amountIn_1, minAmountOut_1, true);

        (int delta0, int delta1,,) = _getPoolData(poolId, user2);
        beforeReserve0 = uint(int(beforeReserve0) + delta0);
        beforeReserve1 = uint(int(beforeReserve1) + delta1);

        uint amountIn_2 = 100;
        uint minAmountOut_2 = PoolManager(poolManager).getAmountOut(beforeReserve0, beforeReserve1, amountIn_2);

        PoolManager(poolManager).swapWithInput(poolId, amountIn_2, minAmountOut_2, true);

        (delta0, delta1,,) = _getPoolData(poolId, user2);
        assertEq(abs(delta1), minAmountOut_1 + minAmountOut_2, "Reserve0 should decrease");
        assertEq(abs(delta0), amountIn_1 + amountIn_2, "Reserve1 should increase");

        vm.stopPrank();
    }

    function testSwapWithInputInvalidPool() public {
        vm.startPrank(user2);

        bytes32 poolId_0 = PoolManager(poolManager).getPoolId(address(token0), address(token1));
        (,, uint beforeReserve0_0, uint beforeReserve1_0) = PoolManager(poolManager).pools(poolId_0);

        uint amountIn_0 = 500;
        uint minAmountOut_0 = PoolManager(poolManager).getAmountOut(beforeReserve0_0, beforeReserve1_0, amountIn_0);

        PoolManager(poolManager).swapWithInput(poolId_0, amountIn_0, minAmountOut_0, true);

        bytes32 poolId_1 = PoolManager(poolManager).getPoolId(address(token0), address(token2));
        (,, uint beforeReserve0_1, uint beforeReserve1_1) = PoolManager(poolManager).pools(poolId_1);

        uint amountIn_1 = minAmountOut_0 ;
        uint minAmountOut_1 = PoolManager(poolManager).getAmountOut(beforeReserve0_1, beforeReserve1_1, amountIn_1);

        vm.expectRevert("Pool does not exist");
        PoolManager(poolManager).swapWithInput(poolId_1, amountIn_1, minAmountOut_1, true);

        vm.stopPrank();
    }

    function testSwapOutputMultiHop() public {
        vm.startPrank(user2);

        bytes32 poolId_0 = PoolManager(poolManager).getPoolId(address(token0), address(token1));
        (,, uint beforeReserve0_0, uint beforeReserve1_0) = PoolManager(poolManager).pools(poolId_0);

        uint amountOut_0 = 500;
        uint maxAmountIn_0 = PoolManager(poolManager).getAmountIn(beforeReserve0_0, beforeReserve1_0, amountOut_0);

        // (address _token0, address _token1,,) = PoolManager(poolManager).pools(poolId_0);
        bool input_0 = true;
        bool zeroForOne = (token0 < token1) ? input_0 : !input_0;
        PoolManager(poolManager).swapWithOutput(poolId_0, amountOut_0, maxAmountIn_0, zeroForOne);

        bytes32 poolId_1 = PoolManager(poolManager).getPoolId(address(token1), address(token2));
        (,, uint beforeReserve0_1, uint beforeReserve1_1) = PoolManager(poolManager).pools(poolId_1);

        uint amountOut_1 = 200;
        uint maxAmountIn_1 = PoolManager(poolManager).getAmountIn(beforeReserve0_1, beforeReserve1_1, amountOut_1);

        input_0 = true;
        zeroForOne = token1 < token2 ? input_0 : !input_0;
        PoolManager(poolManager).swapWithOutput(poolId_1, amountOut_1, maxAmountIn_1, zeroForOne);

        // Check updated reserves
        (int delta0_0, int delta1_0,,) = _getPoolData(poolId_0, user2);
        (int delta0_1, int delta1_1,,) = _getPoolData(poolId_1, user2);

        assertEq(abs(delta1_0), maxAmountIn_0, "Reserve1_0 should increase");
        // assertEq(abs(delta0_0), abs(delta0_1), "Reserve0_0 should == reserve0_1");
        assertEq(abs(delta0_0), amountOut_0, "Reserve0_0 should decrease");
        assertEq(abs(delta0_1),  maxAmountIn_1, "Reserve0_1 should increase");
        assertEq(abs(delta1_1),amountOut_1,  "Reserve1_1 should decrease");

        vm.stopPrank();
    }

    function testSwapOutputMultiPoolWithInvalidOutputAmount() public {
        vm.startPrank(user2);

        bytes32 poolId_0 = PoolManager(poolManager).getPoolId(address(token0), address(token1));
        (,, uint beforeReserve0_0, uint beforeReserve1_0) = PoolManager(poolManager).pools(poolId_0);

        uint amountOut_0 = 500;
        uint maxAmountIn_0 = PoolManager(poolManager).getAmountIn(beforeReserve0_0, beforeReserve1_0, amountOut_0);

        // (address _token0, address _token1,,) = PoolManager(poolManager).pools(poolId_0);
        bool input_0 = true;
        bool zeroForOne = (token0 < token1) ? input_0 : !input_0;
        PoolManager(poolManager).swapWithOutput(poolId_0, amountOut_0, maxAmountIn_0, zeroForOne);

        uint amountOut_1 = 4500;

        vm.expectRevert("Insufficient liquidity in pool");
        PoolManager(poolManager).swapWithOutput(poolId_0, amountOut_1, 1, zeroForOne);

        vm.stopPrank();
    }

    function testSwapOutputMultiHopWithInvalidInputAmount() public {
        vm.startPrank(user2);

        bytes32 poolId_0 = PoolManager(poolManager).getPoolId(address(token0), address(token1));
        (,, uint beforeReserve0_0, uint beforeReserve1_0) = PoolManager(poolManager).pools(poolId_0);

        uint amountOut_0 = 500;
        uint maxAmountIn_0 = PoolManager(poolManager).getAmountIn(beforeReserve0_0, beforeReserve1_0, amountOut_0);

        // (address _token0, address _token1,,) = PoolManager(poolManager).pools(poolId_0);
        bool input_0 = true;
        bool zeroForOne = (token0 < token1) ? input_0 : !input_0;
        PoolManager(poolManager).swapWithOutput(poolId_0, amountOut_0, maxAmountIn_0, zeroForOne);

        bytes32 poolId_1 = PoolManager(poolManager).getPoolId(address(token1), address(token2));
        (,, uint beforeReserve0_1, uint beforeReserve1_1) = PoolManager(poolManager).pools(poolId_1);

        uint amountOut_1 = 200;
        uint maxAmountIn_1 = PoolManager(poolManager).getAmountIn(beforeReserve0_1, beforeReserve1_1, amountOut_1);

        vm.expectRevert("Insufficient input amount");
        PoolManager(poolManager).swapWithOutput(poolId_1, amountOut_1, maxAmountIn_1 - 10, zeroForOne);

        vm.stopPrank();
    }
    // function testSwapWithInputInvalidInputAmount() public {
    //     vm.startPrank(user2);

    //     bytes32 poolId = PoolManager(poolManager).getPoolId(address(token0), address(token1));

    //     vm.expectRevert("Pool: Invalid input amount");
    //     PoolManager(poolManager).swapWithInput(poolId, 0, 1993, true);

    //     vm.stopPrank();
    // }

    // function testSwapWithInputInsufficientOutputAmount() public {
    //     vm.startPrank(user2);

    //     bytes32 poolId = PoolManager(poolManager).getPoolId(address(token0), address(token1));

    //     vm.expectRevert("Pool: Insufficient output amount");
    //     PoolManager(poolManager).swapWithInput(poolId, 500, 2000, true);

    //     vm.stopPrank();
    // }
}
