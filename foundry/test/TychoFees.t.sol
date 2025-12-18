// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@src/TychoRouter.sol";
import "./TychoRouterTestSetup.sol";

contract TychoFeesTest is TychoRouterTestSetup {
    address constant FEE_SETTER = address(0xFEE);

    function setUp() public override {
        super.setUp();

        // Grant FEE_SETTER_ROLE
        vm.startPrank(ADMIN);
        tychoRouter.grantRole(tychoRouter.FEE_SETTER_ROLE(), FEE_SETTER);
        vm.stopPrank();
    }

    function testSetFeePercentage() public {
        // Fee setter sets 1% fee for Bob (100 basis points)
        uint256 feePercentage = 100; // 1%

        vm.startPrank(FEE_SETTER);
        tychoRouter.setFeePercentage(BOB, feePercentage);
        vm.stopPrank();

        // Verify fee was set
        uint256 actualFee = tychoRouter.getFeePercentage(BOB);
        assertEq(actualFee, feePercentage);
    }

    function testSwapWithFee() public {
        // Set 1% fee for Bob
        vm.startPrank(FEE_SETTER);
        tychoRouter.setFeePercentage(BOB, 100); // 1%
        vm.stopPrank();

        // Bob does a swap: 1 WETH -> DAI
        uint256 amountIn = 1 ether;
        deal(WETH_ADDR, BOB, amountIn);

        vm.startPrank(BOB);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, amountIn);

        bytes memory protocolData = encodeUniswapV2Swap(
            WETH_ADDR,
            WETH_DAI_POOL,
            tychoRouterAddr, // IMPORTANT: receiver must be router when fees are involved
            false,
            RestrictTransferFrom.TransferType.TransferFromSender
        );

        bytes memory swap =
            encodeSingleSwap(address(usv2Executor), protocolData);

        uint256 minAmountOut = 2000 * 1e18;
        uint256 amountOut = tychoRouter.singleSwap(
            amountIn,
            WETH_ADDR,
            DAI_ADDR,
            minAmountOut,
            false,
            false,
            BOB,
            true,
            swap
        );

        vm.stopPrank();

        // Bob should have received 99% of the output (1% fee)
        uint256 bobBalance = IERC20(DAI_ADDR).balanceOf(BOB);
        // amountOut should already be the amount after fee
        assertEq(bobBalance, amountOut);

        // Fee (1%) should be credited to Bob's vault
        uint256 expectedTotalBeforeFee = (amountOut * 10000) / 9900; // Reverse calculate
        uint256 expectedFee = expectedTotalBeforeFee - amountOut;
        uint256 bobVaultBalance = tychoRouter.vaultBalanceOf(BOB, DAI_ADDR);
        assertGt(bobVaultBalance, 0);
        assertApproxEqRel(bobVaultBalance, expectedFee, 0.01e18); // 1% tolerance

        // Router should have the fee in its balance
        uint256 routerBalance = IERC20(DAI_ADDR).balanceOf(tychoRouterAddr);
        assertGt(routerBalance, 0);
        assertApproxEqRel(routerBalance, expectedFee, 0.01e18); // 1% tolerance
    }

    function testSwapWithoutFee() public {
        // Bob does a swap without any fee set
        uint256 amountIn = 1 ether;
        deal(WETH_ADDR, BOB, amountIn);

        vm.startPrank(BOB);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, amountIn);

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
        uint256 amountOut = tychoRouter.singleSwap(
            amountIn,
            WETH_ADDR,
            DAI_ADDR,
            minAmountOut,
            false,
            false,
            BOB,
            true,
            swap
        );

        vm.stopPrank();

        // Bob should have received full output (no fee)
        uint256 bobBalance = IERC20(DAI_ADDR).balanceOf(BOB);
        assertEq(bobBalance, amountOut);

        // Router should have no DAI (all went to Bob)
        uint256 routerBalance = IERC20(DAI_ADDR).balanceOf(tychoRouterAddr);
        assertEq(routerBalance, 0);
    }

    function testInvalidReceiverForFee() public {
        // Set 1% fee for Bob
        vm.startPrank(FEE_SETTER);
        tychoRouter.setFeePercentage(BOB, 100); // 1%
        vm.stopPrank();

        // Bob tries to swap with receiver set to himself (not the router)
        uint256 amountIn = 1 ether;
        deal(WETH_ADDR, BOB, amountIn);

        vm.startPrank(BOB);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, amountIn);

        bytes memory protocolData = encodeUniswapV2Swap(
            WETH_ADDR,
            WETH_DAI_POOL,
            BOB, // Wrong: should be router
            false,
            RestrictTransferFrom.TransferType.TransferFromSender
        );

        bytes memory swap =
            encodeSingleSwap(address(usv2Executor), protocolData);

        // Should revert with InvalidReceiverForFee
        vm.expectRevert();
        tychoRouter.singleSwap(
            amountIn,
            WETH_ADDR,
            DAI_ADDR,
            2000 * 1e18,
            false,
            false,
            BOB,
            true,
            swap
        );

        vm.stopPrank();
    }

    function testFeePercentageTooHigh() public {
        // Try to set fee above maximum (50%)
        uint256 tooHighFee = 5001; // 50.01%

        vm.startPrank(FEE_SETTER);
        vm.expectRevert();
        tychoRouter.setFeePercentage(BOB, tooHighFee);
        vm.stopPrank();
    }

    function testOnlyFeeSetterCanSetFees() public {
        // Random user tries to set fee
        vm.startPrank(ALICE);
        vm.expectRevert();
        tychoRouter.setFeePercentage(BOB, 100);
        vm.stopPrank();
    }
}
