// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@src/TychoRouter.sol";
import "@src/TychoVault.sol";
import "./TychoRouterTestSetup.sol";

contract TychoVaultTest is TychoRouterTestSetup {
    function testDepositAndWithdrawFromVault() public {
        // Bob deposits 10 WETH into the vault
        uint256 depositAmount = 10 ether;
        deal(WETH_ADDR, BOB, depositAmount);

        vm.startPrank(BOB);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, depositAmount);
        tychoRouter.depositToVault(WETH_ADDR, depositAmount);

        // Check Bob's vault balance
        uint256 vaultBalance = tychoRouter.vaultBalanceOf(BOB, WETH_ADDR);
        assertEq(vaultBalance, depositAmount);
        assertEq(IERC20(WETH_ADDR).balanceOf(BOB), 0);

        // Bob withdraws 5 WETH
        uint256 withdrawAmount = 5 ether;
        tychoRouter.withdrawFromVault(WETH_ADDR, withdrawAmount);

        // Check balances after withdrawal
        vaultBalance = tychoRouter.vaultBalanceOf(BOB, WETH_ADDR);
        assertEq(vaultBalance, depositAmount - withdrawAmount);
        assertEq(IERC20(WETH_ADDR).balanceOf(BOB), withdrawAmount);

        vm.stopPrank();
    }

    function testVaultFundsIsolation() public {
        // Bob deposits 10 WETH into the vault
        uint256 bobDeposit = 10 ether;
        deal(WETH_ADDR, BOB, bobDeposit);

        vm.startPrank(BOB);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, bobDeposit);
        tychoRouter.depositToVault(WETH_ADDR, bobDeposit);
        vm.stopPrank();

        // Alice tries to do a swap for 1 WETH -> DAI
        uint256 aliceAmount = 1 ether;
        deal(WETH_ADDR, ALICE, aliceAmount);

        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, aliceAmount);

        bytes memory protocolData = encodeUniswapV2Swap(
            WETH_ADDR,
            WETH_DAI_POOL,
            ALICE,
            false,
            RestrictTransferFrom.TransferType.TransferFromSender
        );

        bytes memory swap =
            encodeSingleSwap(address(usv2Executor), protocolData);

        uint256 minAmountOut = 2000 * 1e18;
        tychoRouter.singleSwap(
            aliceAmount,
            WETH_ADDR,
            DAI_ADDR,
            minAmountOut,
            false,
            false,
            ALICE,
            true,
            swap
        );
        vm.stopPrank();

        // Bob's vault balance should remain unchanged
        uint256 bobVaultBalance = tychoRouter.vaultBalanceOf(BOB, WETH_ADDR);
        assertEq(bobVaultBalance, bobDeposit, "Bob's vault funds were accessed");

        // Alice should have received DAI
        uint256 aliceDAI = IERC20(DAI_ADDR).balanceOf(ALICE);
        assertGt(aliceDAI, minAmountOut, "Alice didn't receive DAI");

        // Bob should still be able to withdraw his funds
        vm.startPrank(BOB);
        tychoRouter.withdrawFromVault(WETH_ADDR, bobDeposit);
        assertEq(IERC20(WETH_ADDR).balanceOf(BOB), bobDeposit);
        vm.stopPrank();
    }

    function testSwapDoesNotAffectVaultFunds() public {
        // Bob deposits 10 WETH into the vault and immediately withdraws to empty the router
        uint256 depositAmount = 10 ether;
        deal(WETH_ADDR, BOB, depositAmount);

        vm.startPrank(BOB);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, depositAmount);
        tychoRouter.depositToVault(WETH_ADDR, depositAmount);

        uint256 initialVaultBalance = tychoRouter.vaultBalanceOf(BOB, WETH_ADDR);
        assertEq(initialVaultBalance, depositAmount);

        // Withdraw to get the tokens back out of the router
        tychoRouter.withdrawFromVault(WETH_ADDR, depositAmount);
        assertEq(tychoRouter.vaultBalanceOf(BOB, WETH_ADDR), 0);
        assertEq(IERC20(WETH_ADDR).balanceOf(BOB), depositAmount);

        vm.stopPrank();
    }

    function testLeftoversCreditedToVault() public {
        // Bob does a swap that leaves funds in the router
        uint256 swapAmount = 1 ether;
        deal(WETH_ADDR, BOB, swapAmount);

        vm.startPrank(BOB);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, swapAmount);

        // Send extra WETH directly to router (simulating dust/leftovers)
        uint256 dustAmount = 0.001 ether;
        deal(WETH_ADDR, tychoRouterAddr, dustAmount);

        bytes memory protocolData = encodeUniswapV2Swap(
            WETH_ADDR,
            WETH_DAI_POOL,
            BOB,
            false,
            RestrictTransferFrom.TransferType.TransferFromSender
        );

        bytes memory swap =
            encodeSingleSwap(address(usv2Executor), protocolData);

        uint256 minAmountOut = 2000 * 1e18;
        tychoRouter.singleSwap(
            swapAmount,
            WETH_ADDR,
            DAI_ADDR,
            minAmountOut,
            false,
            false,
            BOB,
            true,
            swap
        );

        // Check that leftovers (dust) were credited to Bob's vault
        // The vault should have the dust amount credited
        uint256 vaultBalance = tychoRouter.vaultBalanceOf(BOB, WETH_ADDR);
        assertEq(vaultBalance, dustAmount);

        vm.stopPrank();
    }

    function testInsufficientVaultBalanceForWithdraw() public {
        // Bob deposits 1 WETH into the vault
        uint256 depositAmount = 1 ether;
        deal(WETH_ADDR, BOB, depositAmount);

        vm.startPrank(BOB);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, depositAmount);
        tychoRouter.depositToVault(WETH_ADDR, depositAmount);

        // Bob tries to withdraw 2 WETH (more than he has)
        uint256 withdrawAmount = 2 ether;
        vm.expectRevert();
        tychoRouter.withdrawFromVault(WETH_ADDR, withdrawAmount);

        vm.stopPrank();
    }

    function testMultipleUsersVaultIsolation() public {
        // Bob deposits 10 WETH
        uint256 bobDeposit = 10 ether;
        deal(WETH_ADDR, BOB, bobDeposit);
        vm.startPrank(BOB);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, bobDeposit);
        tychoRouter.depositToVault(WETH_ADDR, bobDeposit);
        vm.stopPrank();

        // Alice deposits 5 WETH to a different token (DAI) to avoid interference
        uint256 aliceDeposit = 5000 * 1e18;
        deal(DAI_ADDR, ALICE, aliceDeposit);
        vm.startPrank(ALICE);
        IERC20(DAI_ADDR).approve(tychoRouterAddr, aliceDeposit);
        tychoRouter.depositToVault(DAI_ADDR, aliceDeposit);
        vm.stopPrank();

        // Check balances
        assertEq(tychoRouter.vaultBalanceOf(BOB, WETH_ADDR), bobDeposit);
        assertEq(tychoRouter.vaultBalanceOf(ALICE, DAI_ADDR), aliceDeposit);

        // Verify Alice cannot withdraw Bob's WETH
        vm.startPrank(ALICE);
        assertEq(tychoRouter.vaultBalanceOf(ALICE, WETH_ADDR), 0);
        vm.expectRevert();
        tychoRouter.withdrawFromVault(WETH_ADDR, 1 ether);
        vm.stopPrank();

        // Bob withdraws all his funds successfully
        vm.startPrank(BOB);
        tychoRouter.withdrawFromVault(WETH_ADDR, bobDeposit);
        assertEq(IERC20(WETH_ADDR).balanceOf(BOB), bobDeposit);
        assertEq(tychoRouter.vaultBalanceOf(BOB, WETH_ADDR), 0);
        vm.stopPrank();

        // Alice withdraws all her funds successfully
        vm.startPrank(ALICE);
        tychoRouter.withdrawFromVault(DAI_ADDR, aliceDeposit);
        assertEq(IERC20(DAI_ADDR).balanceOf(ALICE), aliceDeposit);
        assertEq(tychoRouter.vaultBalanceOf(ALICE, DAI_ADDR), 0);
        vm.stopPrank();
    }

    function testDepositNativeETH() public {
        // Bob deposits 5 ETH into the vault
        uint256 depositAmount = 5 ether;
        vm.deal(BOB, depositAmount);

        vm.startPrank(BOB);
        tychoRouter.depositToVault{value: depositAmount}(
            address(0), depositAmount
        );

        // Check Bob's vault balance for native ETH
        uint256 vaultBalance = tychoRouter.vaultBalanceOf(BOB, address(0));
        assertEq(vaultBalance, depositAmount);
        assertEq(BOB.balance, 0);

        // Bob withdraws 2 ETH
        uint256 withdrawAmount = 2 ether;
        tychoRouter.withdrawFromVault(address(0), withdrawAmount);

        // Check balances after withdrawal
        vaultBalance = tychoRouter.vaultBalanceOf(BOB, address(0));
        assertEq(vaultBalance, depositAmount - withdrawAmount);
        assertEq(BOB.balance, withdrawAmount);

        vm.stopPrank();
    }

    function testERC6909BalanceOf() public {
        // Bob deposits 10 WETH into the vault
        uint256 depositAmount = 10 ether;
        deal(WETH_ADDR, BOB, depositAmount);

        vm.startPrank(BOB);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, depositAmount);
        tychoRouter.depositToVault(WETH_ADDR, depositAmount);

        // Check using ERC6909 balanceOf
        uint256 tokenId = uint256(uint160(WETH_ADDR));
        uint256 balance = tychoRouter.balanceOf(BOB, tokenId);
        assertEq(balance, depositAmount);

        vm.stopPrank();
    }
}
