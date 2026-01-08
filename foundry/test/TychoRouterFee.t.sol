// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@src/TychoRouter.sol";
import "./TychoRouterTestSetup.sol";

contract TychoRouterFeeTest is TychoRouterTestSetup {
    function testSetRouterFeeOnOutput() public {
        // Set router fee to 1% (100 bps)
        uint16 newFee = 100;
        vm.expectEmit(true, true, true, true);
        emit TychoRouter.RouterFeeOnOutputUpdated(0, newFee);
        tychoRouter.setRouterFeeOnOutput(newFee);

        assertEq(tychoRouter.getRouterFeeOnOutput(), newFee);
    }

    function testSetRouterFeeOnOutputUnauthorized() public {
        vm.startPrank(ALICE);
        vm.expectRevert();
        tychoRouter.setRouterFeeOnOutput(100);
        vm.stopPrank();
    }

    function testSingleSwapWithRouterFee() public {
        // Setup: Set 1% fee
        tychoRouter.setRouterFeeOnOutput(100); // 1%

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
            RestrictTransferFrom.TransferType.TransferFrom
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
            tychoRouter.balanceOf(tychoRouterAddr, uint256(uint160(DAI_ADDR)));
        assertGt(routerVaultBalance, 0);
        // Fee should be approximately 1% of total output
        uint256 totalOutput = aliceBalance + routerVaultBalance;
        uint256 expectedFee = totalOutput / 100;
        // Allow 1% tolerance for rounding
        assertApproxEqRel(routerVaultBalance, expectedFee, 0.01e18);
    }

    function testRouterFeeDeductedBeforeSlippageCheck() public {
        // Setup: Set a high router fee
        tychoRouter.setRouterFeeOnOutput(500); // 5%

        uint256 swapAmount = 1 ether;
        deal(WETH_ADDR, ALICE, swapAmount);

        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, swapAmount);

        bytes memory protocolData = encodeUniswapV2Swap(
            WETH_ADDR,
            WETH_DAI_POOL,
            tychoRouterAddr, // IMPORTANT: receiver must be router when fees are involved
            false,
            RestrictTransferFrom.TransferType.TransferFrom
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
        tychoRouter.setRouterFeeOnOutput(100); // 1%

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
            RestrictTransferFrom.TransferType.TransferFrom
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
            tychoRouter.balanceOf(tychoRouterAddr, uint256(uint160(WETH_ADDR)));
        assertGt(routerVaultBalance, 0);
    }

    function testZeroRouterFee() public {
        // Router fee starts at 0, should not deduct any fee
        assertEq(tychoRouter.getRouterFeeOnOutput(), 0);

        uint256 swapAmount = 1 ether;
        deal(WETH_ADDR, ALICE, swapAmount);

        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, swapAmount);

        bytes memory protocolData = encodeUniswapV2Swap(
            WETH_ADDR,
            WETH_DAI_POOL,
            tychoRouterAddr, // receiver must be router for consistent behavior
            false,
            RestrictTransferFrom.TransferType.TransferFrom
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
            tychoRouter.balanceOf(tychoRouterAddr, uint256(uint160(DAI_ADDR)));
        assertEq(routerVaultBalance, 0);
    }

    function testSetRouterFeeOnSolverFee() public {
        // Set router fee on solver fee to 10% (1000 bps)
        uint16 newFee = 1000;
        vm.expectEmit(true, true, true, true);
        emit TychoRouter.RouterFeeOnSolverFeeUpdated(0, newFee);
        tychoRouter.setRouterFeeOnSolverFee(newFee);

        assertEq(tychoRouter.getRouterFeeOnSolverFee(), newFee);
    }

    function testSetRouterFeeOnSolverFeeUnauthorized() public {
        vm.startPrank(ALICE);
        vm.expectRevert();
        tychoRouter.setRouterFeeOnSolverFee(1000);
        vm.stopPrank();
    }

    function testSingleSwapWithRouterFeeOnSolverFee() public {
        // Setup: Set 10% router fee on solver fee
        tychoRouter.setRouterFeeOnSolverFee(1000); // 10%

        uint256 swapAmount = 1 ether;
        deal(WETH_ADDR, ALICE, swapAmount);

        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, swapAmount);

        bytes memory protocolData = encodeUniswapV2Swap(
            WETH_ADDR,
            WETH_DAI_POOL,
            tychoRouterAddr,
            false,
            RestrictTransferFrom.TransferType.TransferFrom
        );

        bytes memory swap =
            encodeSingleSwap(address(usv2Executor), protocolData);

        uint256 minAmountOut = 1900 * 1e18;

        // Swap with 5% solution fee
        uint256 amountOut = tychoRouter.singleSwap(
            swapAmount,
            WETH_ADDR,
            DAI_ADDR,
            minAmountOut,
            false,
            false,
            ALICE,
            true,
            500, // 5% solution fee
            address(0x456), // solution fee receiver
            swap
        );

        vm.stopPrank();

        // Swap outputs ~2018 DAI
        // Solution fee: 5% = ~100.9 DAI
        // Remaining: ~1917 DAI
        // Router fee on solver fee: 10% of ~100.9 = ~10.09 DAI
        // Final to Alice: ~1907 DAI
        uint256 aliceBalance = IERC20(DAI_ADDR).balanceOf(ALICE);
        assertEq(aliceBalance, amountOut);
        assertGt(aliceBalance, 1900 * 1e18);
        assertLt(aliceBalance, 1910 * 1e18);

        // Verify router received its fee in vault
        uint256 routerVaultBalance =
            tychoRouter.balanceOf(tychoRouterAddr, uint256(uint160(DAI_ADDR)));
        assertGt(routerVaultBalance, 0);
    }

    function testSingleSwapWithBothRouterFees() public {
        // Setup: Set both router fees
        tychoRouter.setRouterFeeOnOutput(500); // 5% on output
        tychoRouter.setRouterFeeOnSolverFee(500); // 5% on solver fee

        uint256 swapAmount = 1 ether;
        deal(WETH_ADDR, ALICE, swapAmount);

        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, swapAmount);

        bytes memory protocolData = encodeUniswapV2Swap(
            WETH_ADDR,
            WETH_DAI_POOL,
            tychoRouterAddr,
            false,
            RestrictTransferFrom.TransferType.TransferFrom
        );

        bytes memory swap =
            encodeSingleSwap(address(usv2Executor), protocolData);

        uint256 minAmountOut = 1700 * 1e18;

        // Swap with 10% solution fee
        uint256 amountOut = tychoRouter.singleSwap(
            swapAmount,
            WETH_ADDR,
            DAI_ADDR,
            minAmountOut,
            false,
            false,
            ALICE,
            true,
            1000, // 10% solution fee
            address(0x456), // solution fee receiver
            swap
        );

        vm.stopPrank();

        // Swap outputs ~2018 DAI
        // Solution fee: 10% = ~201.8 DAI
        // Remaining: ~1816 DAI
        // Router fee on output: 5% of ~1816 = ~90.8 DAI
        // Remaining: ~1725 DAI
        // Router fee on solver fee: 5% of ~201.8 = ~10.09 DAI
        // Final to Alice: ~1715 DAI
        uint256 aliceBalance = IERC20(DAI_ADDR).balanceOf(ALICE);
        assertEq(aliceBalance, amountOut);
        assertGt(aliceBalance, 1700 * 1e18);
        assertLt(aliceBalance, 1720 * 1e18);

        // Verify router received both fees in vault
        uint256 routerVaultBalance =
            tychoRouter.balanceOf(tychoRouterAddr, uint256(uint160(DAI_ADDR)));
        assertGt(routerVaultBalance, 90 * 1e18); // Should have ~100.9 DAI in fees
    }
}
