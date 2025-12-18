// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@src/TychoRouter.sol";
import "./TychoRouterTestSetup.sol";

contract TychoRouterFeeTest is TychoRouterTestSetup {
    function testSetRouterFee() public {
        // Set router fee to 1% (100 bps)
        uint16 newFee = 100;
        vm.expectEmit(true, true, true, true);
        emit TychoRouter.RouterFeeUpdated(0, newFee);
        tychoRouter.setRouterFee(newFee);

        assertEq(tychoRouter.getRouterFee(), newFee);
    }

    function testSetRouterFeeUnauthorized() public {
        vm.startPrank(ALICE);
        vm.expectRevert();
        tychoRouter.setRouterFee(100);
        vm.stopPrank();
    }

    function testSingleSwapWithRouterFee() public {
        // Setup: Set 1% fee
        tychoRouter.setRouterFee(100); // 1%

        // Alice swaps 1 WETH for DAI
        uint256 swapAmount = 1 ether;
        deal(WETH_ADDR, ALICE, swapAmount);

        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, swapAmount);

        bytes memory protocolData = encodeUniswapV2Swap(
            WETH_ADDR,
            WETH_DAI_POOL,
            tychoRouterAddr, // IMPORTANT: receiver must be router when fees are involved
            false,
            RestrictTransferFrom.TransferType.TransferFromSender
        );

        bytes memory swap =
            encodeSingleSwap(address(usv2Executor), protocolData);

        // The swap will output ~2018 DAI, minus 1% fee = ~1998 DAI
        uint256 minAmountOut = 1990 * 1e18; // Set min slightly below expected

        uint256 amountOut = tychoRouter.singleSwap(
            swapAmount,
            WETH_ADDR,
            DAI_ADDR,
            minAmountOut,
            false,
            false,
            ALICE,
            true,
            0,
            address(0),
            swap
        );

        vm.stopPrank();

        // Verify Alice received the amount after fee (should be around 1998 DAI)
        uint256 aliceBalance = IERC20(DAI_ADDR).balanceOf(ALICE);
        assertEq(aliceBalance, amountOut);
        assertGt(aliceBalance, minAmountOut);
        assertLt(aliceBalance, 2000 * 1e18); // Should be less than 2000 due to 1% fee

        // Verify router received the fee in its vault (should be ~1% of output)
        uint256 routerVaultBalance =
            tychoRouter.vaultBalanceOf(tychoRouterAddr, DAI_ADDR);
        assertGt(routerVaultBalance, 0);
        // Fee should be approximately 1% of total output
        uint256 totalOutput = aliceBalance + routerVaultBalance;
        uint256 expectedFee = totalOutput / 100;
        // Allow 1% tolerance for rounding
        assertApproxEqRel(routerVaultBalance, expectedFee, 0.01e18);
    }

    function testRouterFeeDeductedBeforeSlippageCheck() public {
        // Setup: Set a high router fee
        tychoRouter.setRouterFee(500); // 5%

        uint256 swapAmount = 1 ether;
        deal(WETH_ADDR, ALICE, swapAmount);

        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, swapAmount);

        bytes memory protocolData = encodeUniswapV2Swap(
            WETH_ADDR,
            WETH_DAI_POOL,
            tychoRouterAddr, // IMPORTANT: receiver must be router when fees are involved
            false,
            RestrictTransferFrom.TransferType.TransferFromSender
        );

        bytes memory swap =
            encodeSingleSwap(address(usv2Executor), protocolData);

        // With 5% fee, expect around 1918 DAI (95% of 2018)
        uint256 minAmountOut = 1900 * 1e18;

        // This should succeed (minAmountOut is after-fee amount)
        uint256 amountOut = tychoRouter.singleSwap(
            swapAmount,
            WETH_ADDR,
            DAI_ADDR,
            minAmountOut,
            false,
            false,
            ALICE,
            true,
            0,
            address(0),
            swap
        );

        // Verify amountOut is less than what the swap would output without fee
        assertGt(amountOut, minAmountOut);
        assertLt(amountOut, 2000 * 1e18); // Should be < 2000 DAI due to 5% fee

        vm.stopPrank();

        // Now test that setting minAmountOut too high causes revert
        // This confirms fee is deducted before slippage check
        deal(WETH_ADDR, ALICE, swapAmount);
        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, swapAmount);

        vm.expectRevert();
        tychoRouter.singleSwap(
            swapAmount,
            WETH_ADDR,
            DAI_ADDR,
            2010 * 1e18, // minAmountOut that's impossible with 5% fee
            false,
            false,
            ALICE,
            true,
            0,
            address(0),
            swap
        );

        vm.stopPrank();
    }

    function testRouterFeeWithUnwrapETH() public {
        // Setup: Set 1% fee
        tychoRouter.setRouterFee(100); // 1%

        // Alice swaps DAI for WETH and unwraps to ETH
        uint256 swapAmount = 2000 * 1e18;
        deal(DAI_ADDR, ALICE, swapAmount);

        vm.startPrank(ALICE);
        IERC20(DAI_ADDR).approve(tychoRouterAddr, swapAmount);

        bytes memory protocolData = encodeUniswapV2Swap(
            DAI_ADDR,
            WETH_DAI_POOL,
            tychoRouterAddr,
            true,
            RestrictTransferFrom.TransferType.TransferFromSender
        );

        bytes memory swap =
            encodeSingleSwap(address(usv2Executor), protocolData);

        uint256 aliceBalanceBefore = ALICE.balance;
        uint256 minAmountOut = 0.9 ether;

        uint256 amountOut = tychoRouter.singleSwap(
            swapAmount,
            DAI_ADDR,
            address(0), // ETH
            minAmountOut,
            false,
            true, // unwrapEth
            ALICE,
            true,
            0,
            address(0),
            swap
        );

        vm.stopPrank();

        // Verify Alice received ETH after fee
        uint256 aliceBalanceAfter = ALICE.balance;
        assertEq(aliceBalanceAfter - aliceBalanceBefore, amountOut);

        // Verify router received WETH fee in its vault (fee is in WETH before unwrap)
        uint256 routerVaultBalance =
            tychoRouter.vaultBalanceOf(tychoRouterAddr, WETH_ADDR);
        assertGt(routerVaultBalance, 0);
    }

    function testZeroRouterFee() public {
        // Router fee starts at 0, should not deduct any fee
        assertEq(tychoRouter.getRouterFee(), 0);

        uint256 swapAmount = 1 ether;
        deal(WETH_ADDR, ALICE, swapAmount);

        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, swapAmount);

        bytes memory protocolData = encodeUniswapV2Swap(
            WETH_ADDR,
            WETH_DAI_POOL,
            tychoRouterAddr, // receiver must be router for consistent behavior
            false,
            RestrictTransferFrom.TransferType.TransferFromSender
        );

        bytes memory swap =
            encodeSingleSwap(address(usv2Executor), protocolData);

        uint256 expectedOutput = 2018817438608734439722;
        uint256 minAmountOut = expectedOutput;

        uint256 amountOut = tychoRouter.singleSwap(
            swapAmount,
            WETH_ADDR,
            DAI_ADDR,
            minAmountOut,
            false,
            false,
            ALICE,
            true,
            0,
            address(0),
            swap
        );

        vm.stopPrank();

        // Verify Alice received full amount (no fee)
        assertEq(IERC20(DAI_ADDR).balanceOf(ALICE), expectedOutput);
        assertEq(amountOut, expectedOutput);

        // Verify router vault has no fees
        uint256 routerVaultBalance =
            tychoRouter.vaultBalanceOf(tychoRouterAddr, DAI_ADDR);
        assertEq(routerVaultBalance, 0);
    }
}
