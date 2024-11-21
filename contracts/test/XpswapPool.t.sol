// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/XpswapPool.sol";

contract nawakERC20 is XpswapERC20 {
    constructor(string memory name_, string memory ticker_) XpswapERC20() {
        name = name_;
        symbol = ticker_;
        _mint(msg.sender, type(uint256).max); // Mint 10,000 tokens with 18 decimals
    }
}

contract XpswapPoolTest is Test {
    XpswapPool private pool;
    nawakERC20 private tokenA;
    nawakERC20 private tokenB;

    address private user1 = address(0x1);
    address private user2 = address(0x2);
    address private user3 = address(0x3);

    function setUp() public {
        tokenA = new nawakERC20("Dai", "DAI");
        tokenB = new nawakERC20("Starknet", "STRK");
        pool = new XpswapPool(address(tokenA), address(tokenB));

        // Distribute initial tokens to user1 and user2
        tokenA.transfer(user1, 1000);
        tokenB.transfer(user1, 1000);
        tokenA.transfer(user2, 1e18);
        tokenB.transfer(user2, 1e18);
    }


    function test_addLiquidity() public {
        vm.prank(user1);
        tokenA.approve(address(pool), 100);
        vm.prank(user1);
        tokenB.approve(address(pool), 1000);
        vm.prank(user1);
        pool.addLiquidity(100, 1000);

        assertEq(pool.balanceOf(user1), 200, "LP token balance incorrect");
        assertEq(tokenA.balanceOf(address(pool)), 100, "Token A reserve incorrect");
        assertEq(tokenB.balanceOf(address(pool)), 1000, "Token B reserve incorrect");
    }

    function test_removeLiquidity() public {
        test_addLiquidity();

        vm.prank(user1);
        pool.removeLiquidity(100);

        assertEq(pool.balanceOf(user1), 100, "Remaining LP token balance incorrect");
        assertEq(tokenA.balanceOf(address(pool)), 50, "Token A reserve incorrect after removal");
        assertEq(tokenB.balanceOf(address(pool)), 500, "Token B reserve incorrect after removal");
        assertEq(tokenA.balanceOf(user1), 950, "User1 Token A balance incorrect after removal");
        assertEq(tokenB.balanceOf(user1), 500, "User1 Token B balance incorrect after removal");
    }


    function test_addLiquidityFailsWithZeroAmounts() public {
        vm.prank(user1);
        tokenA.approve(address(pool), 0);
        vm.prank(user1);
        tokenB.approve(address(pool), 1000);

        vm.prank(user1);
        vm.expectRevert("Pool: Invalid amount for token A");
        pool.addLiquidity(0, 1000);
    }


    function test_removeLiquidityFailsWithZeroDeposit() public {
        test_addLiquidity();

        vm.prank(user1);
        vm.expectRevert("Pool: Insufficient deposit");
        pool.removeLiquidity(0);
    }


    function test_removeLiquidityFailsWithExcessiveAmount() public {
        test_addLiquidity();

        vm.prank(user1);
        vm.expectRevert("Pool: Invalid deposit amount");
        pool.removeLiquidity(300); // Exceeds LP balance
    }

    function test_multipleUsersAddLiquidity() public {
        vm.prank(user1);
        tokenA.approve(address(pool), 100);
        vm.prank(user1);
        tokenB.approve(address(pool), 1000);
        vm.prank(user1);
        pool.addLiquidity(100, 1000);

        vm.prank(user2);
        tokenA.approve(address(pool), 50);
        vm.prank(user2);
        tokenB.approve(address(pool), 500);
        vm.prank(user2);
        pool.addLiquidity(50, 500);

        assertEq(pool.balanceOf(user1), 200, "User1 LP token balance incorrect");
        assertEq(pool.balanceOf(user2), 100, "User2 LP token balance incorrect");
        assertEq(tokenA.balanceOf(address(pool)), 150, "Token A reserve incorrect");
        assertEq(tokenB.balanceOf(address(pool)), 1500, "Token B reserve incorrect");
    }

    function testSwapTokenBForTokenAWithFees() public {
        test_addLiquidity();

        uint256 outputAmount = 50; // Montant de Token A à recevoir
        uint256 reserveIn = pool.reserveB();
        uint256 reserveOut = pool.reserveA();

        uint256 fee = 3; // Frais de 0,3 % avec une base de 1000

        // Calcul du montant d'entrée en tenant compte des frais
        uint256 numerator = outputAmount * reserveIn * 1000;
        uint256 denominator = (reserveOut - outputAmount) * (1000 - fee);
        uint256 inputAmount = numerator / denominator;

        vm.prank(user2);
        tokenB.approve(address(pool), inputAmount);

        uint256 balanceABefore = tokenA.balanceOf(user2);
        uint256 balanceBBefore = tokenB.balanceOf(user2);

        vm.prank(user2);
        pool.swapWithOutput(outputAmount, address(tokenA));

        uint256 balanceAAfter = tokenA.balanceOf(user2);
        uint256 balanceBAfter = tokenB.balanceOf(user2);

        assertEq(balanceAAfter, balanceABefore + outputAmount, "Solde de token A incorrect apres le swap");
        assertEq(balanceBAfter, balanceBBefore - inputAmount, "Solde de token B incorrect apres le swap");
    }

    // Nouveau test : Vérification de l'invariant après un swap avec frais
    function testInvariantAfterSwapWithFees() public {
        test_addLiquidity();

        uint256 outputAmount = 50;
        uint256 reserveIn = pool.reserveB();
        uint256 reserveOut = pool.reserveA();

        uint256 fee = 3;

        uint256 numerator = outputAmount * reserveIn * 1000;
        uint256 denominator = (reserveOut - outputAmount) * (1000 - fee);
        uint256 inputAmount = numerator / denominator;

        uint256 kBefore = reserveIn * reserveOut;

        vm.prank(user2);
        tokenB.approve(address(pool), inputAmount);

        vm.prank(user2);
        pool.swapWithOutput(outputAmount, address(tokenA));

        uint256 reserveInAfter = pool.reserveB();
        uint256 reserveOutAfter = pool.reserveA();
        uint256 kAfter = reserveInAfter * reserveOutAfter;

        // En tenant compte des frais, k peut légèrement augmenter
        assertTrue(kAfter >= kBefore, "Invariant du rpoduit constant non maintenu apres le swap avec frais");
    }

    // Nouveau test : Vérification que les frais sont correctement appliqués
    function testFeesAreAppliedCorrectly() public {
        test_addLiquidity();

        uint256 outputAmount = 50;
        uint256 reserveIn = pool.reserveB();
        uint256 reserveOut = pool.reserveA();

        uint256 fee = 3;

        uint256 numeratorWithFees = outputAmount * reserveIn * 1000;
        uint256 denominatorWithFees = (reserveOut - outputAmount) * (1000 - fee);
        uint256 inputAmountWithFees = numeratorWithFees / denominatorWithFees;

        uint256 numeratorNoFees = outputAmount * reserveIn;
        uint256 denominatorNoFees = (reserveOut - outputAmount);
        uint256 inputAmountNoFees = numeratorNoFees / denominatorNoFees;

        // Le montant d'entrée avec frais doit être supérieur à celui sans frais
        assertTrue(inputAmountWithFees > inputAmountNoFees, "Frais pas correctement appliques");

        vm.prank(user2);
        tokenB.approve(address(pool), inputAmountWithFees);

        vm.prank(user2);
        pool.swapWithOutput(outputAmount, address(tokenA));
    }

    // Modification du test existant pour intégrer les frais
    function testSwapTokenAForTokenBWithFees() public {
        test_addLiquidity();

        uint256 outputAmount = 100; // Montant de Token B à recevoir
        uint256 reserveIn = pool.reserveA();
        uint256 reserveOut = pool.reserveB();

        uint256 fee = 3;

        uint256 numerator = outputAmount * reserveIn * 1000;
        uint256 denominator = (reserveOut - outputAmount) * (1000 - fee);
        uint256 inputAmount = numerator / denominator;

        vm.prank(user2);
        tokenA.approve(address(pool), inputAmount);

        uint256 balanceABefore = tokenA.balanceOf(user2);
        uint256 balanceBBefore = tokenB.balanceOf(user2);

        vm.prank(user2);
        pool.swapWithOutput(outputAmount, address(tokenB));

        uint256 balanceAAfter = tokenA.balanceOf(user2);
        uint256 balanceBAfter = tokenB.balanceOf(user2);

        assertEq(balanceAAfter, balanceABefore - inputAmount, "Solde token A incorrect apres le swap");
        assertEq(balanceBAfter, balanceBBefore + outputAmount, "Solde token B incorrect apres le swap");
    }

    // Nouveau test : Échec du swap en raison d'un montant d'entrée insuffisant (sans tenir compte des frais)
    function testSwapFailsWithInsufficientInputDueToFees() public {
        test_addLiquidity();

        uint256 outputAmount = 50;
        uint256 reserveIn = pool.reserveB();
        uint256 reserveOut = pool.reserveA();

        // Calcul incorrect du montant d'entrée sans inclure les frais
        uint256 inputAmountIncorrect = (outputAmount * reserveIn) / (reserveOut - outputAmount);

        vm.prank(user2);
        tokenB.approve(address(pool), inputAmountIncorrect);

        vm.prank(user2);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        pool.swapWithOutput(outputAmount, address(tokenA));
    }

    // Vous pouvez ajouter d'autres tests pour couvrir différents scénarios en intégrant les frais

    // Test : Swap avec un montant de sortie égal à la réserve (devrait échouer)
    function testSwapFailsWhenOutputEqualsReserveWithFees() public {
        test_addLiquidity();

        uint256 outputAmount = pool.reserveA(); // Tente de vider toutes les réserves

        vm.prank(user2);
        vm.expectRevert(); // Échec attendu en raison d'une division par zéro dans le calcul
        pool.swapWithOutput(outputAmount, address(tokenA));
    }

    // Test : Swap avec un montant de sortie trop élevé (devrait échouer)
    function testSwapFailsWithExcessiveOutputAmountWithFees() public {
        test_addLiquidity();

        uint256 outputAmount = pool.reserveA() + 1; // Dépasse la liquidité disponible

        vm.prank(user2);
        vm.expectRevert("Pool: Insufficient liquidity in pool");
        pool.swapWithOutput(outputAmount, address(tokenA));
    }

    function testSwap0Tokens() public {
        test_addLiquidity();

        uint256 outputAmount = 0; // Montant de Token A à recevoir

        vm.prank(user2);
        vm.expectRevert("Pool: Invalid output amount");
        pool.swapWithOutput(outputAmount, address(tokenA));
    }
    
    function testSwapTooMuchTokens() public {
        test_addLiquidity();

        uint256 outputAmount = type(uint256).max; // Montant de Token A à recevoir

        vm.prank(user2);
        vm.expectRevert("Pool: Insufficient liquidity in pool");
        pool.swapWithOutput(outputAmount, address(tokenA));
    }

        function testSwapWithInputTokenAForTokenB() public {
        test_addLiquidity();

        uint256 inputAmount = 100; // Montant de Token A fourni
        uint256 reserveIn = pool.reserveA();
        uint256 reserveOut = pool.reserveB();
        uint256 fee = 3;

        // Calcul manuel du montant de sortie attendu avec frais
        uint256 effectiveInputAmount = (inputAmount * (1000 - fee)) / 1000;
        uint256 expectedOutputAmount = (effectiveInputAmount * reserveOut) / (reserveIn + effectiveInputAmount);

        vm.prank(user1);
        tokenA.approve(address(pool), inputAmount);

        uint256 balanceBBefore = tokenB.balanceOf(user1);

        vm.prank(user1);
        pool.swapWithInput(inputAmount, address(tokenA));

        uint256 balanceBAfter = tokenB.balanceOf(user1);
        uint256 outputAmount = balanceBAfter - balanceBBefore;

        // Vérifications
        assertEq(outputAmount, expectedOutputAmount, "Montant de token b INCORRECT APRES SWAP");
        assertEq(pool.reserveA(), reserveIn + inputAmount, "Reserve de token A incorrecte");
        assertEq(pool.reserveB(), reserveOut - outputAmount, "reserve token B incorrecte");
    }

    function testSwapWithInputFailsWithZeroInput() public {
        test_addLiquidity();

        uint256 inputAmount = 0; // Montant invalide

        vm.prank(user1);
        tokenA.approve(address(pool), inputAmount);

        vm.prank(user1);
        vm.expectRevert("Pool: Invalid input amount");
        pool.swapWithInput(inputAmount, address(tokenA));
    }

    function testInvariantAfterSwapWithInput() public {
        test_addLiquidity();

        uint256 inputAmount = 100;
        uint256 reserveIn = pool.reserveA();
        uint256 reserveOut = pool.reserveB();

        uint256 kBefore = reserveIn * reserveOut;

        vm.prank(user1);
        tokenA.approve(address(pool), inputAmount);

        vm.prank(user1);
        pool.swapWithInput(inputAmount, address(tokenA));

        uint256 reserveInAfter = pool.reserveA();
        uint256 reserveOutAfter = pool.reserveB();
        uint256 kAfter = reserveInAfter * reserveOutAfter;

        // k doit augmenter légèrement en raison des frais
        assertTrue(kAfter >= kBefore, "Invariant de k nn respecte apres swap");
    }

    function testSwapWithInputFailsIfInsufficientLiquidity() public {
        test_addLiquidity();

        uint256 inputAmount = 1e18; // Montant très élevé pour vider les réserves

        vm.prank(user2);
        tokenA.approve(address(pool), inputAmount);

        vm.prank(user2);
        vm.expectRevert("Pool: Insufficient liquidity in pool");
        pool.swapWithInput(inputAmount, address(tokenA));
    }

    function testSwapWithInputTokenBForTokenA() public {
        test_addLiquidity();

        uint256 inputAmount = 200; // Montant de Token B fourni
        uint256 reserveIn = pool.reserveB();
        uint256 reserveOut = pool.reserveA();
        uint256 fee = 3;

        // Calcul manuel du montant de sortie attendu avec frais
        uint256 effectiveInputAmount = (inputAmount * (1000 - fee)) / 1000;
        uint256 expectedOutputAmount = (effectiveInputAmount * reserveOut) / (reserveIn + effectiveInputAmount);

        vm.prank(user1);
        tokenB.approve(address(pool), inputAmount);

        uint256 balanceABefore = tokenA.balanceOf(user1);

        vm.prank(user1);
        pool.swapWithInput(inputAmount, address(tokenB));

        uint256 balanceAAfter = tokenA.balanceOf(user1);
        uint256 outputAmount = balanceAAfter - balanceABefore;

        // Vérifications
        assertEq(outputAmount, expectedOutputAmount, "Montant tok a incorrect apres swap");
        assertEq(pool.reserveB(), reserveIn + inputAmount, "reserve token b incorrecte");
        assertEq(pool.reserveA(), reserveOut - outputAmount, "reserve token a incorrecte");
    }

}
