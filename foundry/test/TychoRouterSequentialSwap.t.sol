// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@src/executors/UniswapV4Executor.sol";
import {TychoRouter} from "@src/TychoRouter.sol";
import "./TychoRouterTestSetup.sol";
import "./executors/UniswapV4Utils.sol";
import {SafeCallback} from "@uniswap/v4-periphery/src/base/SafeCallback.sol";

contract TychoRouterSequentialSwapTest is TychoRouterTestSetup {
    function _getSequentialSwaps(bool permit2)
        internal
        view
        returns (bytes[] memory)
    {
        // Trade 1 WETH for USDC through DAI with 2 swaps on Uniswap V2
        // 1 WETH   ->   DAI   ->   USDC
        //       (univ2)     (univ2)

        TokenTransfer.TransferType transferType = permit2
            ? TokenTransfer.TransferType.TRANSFER_PERMIT2_TO_PROTOCOL
            : TokenTransfer.TransferType.TRANSFER_FROM_TO_PROTOCOL;

        bytes[] memory swaps = new bytes[](2);
        // WETH -> DAI
        swaps[0] = encodeSequentialSwap(
            address(usv2Executor),
            encodeUniswapV2Swap(
                WETH_ADDR, WETH_DAI_POOL, tychoRouterAddr, false, transferType
            )
        );

        // DAI -> USDC
        swaps[1] = encodeSequentialSwap(
            address(usv2Executor),
            encodeUniswapV2Swap(
                DAI_ADDR,
                DAI_USDC_POOL,
                ALICE,
                true,
                TokenTransfer.TransferType.TRANSFER_TO_PROTOCOL
            )
        );
        return swaps;
    }

    function testSequentialSwapPermit2() public {
        // Trade 1 WETH for USDC through DAI - see _getSequentialSwaps for more info
        uint256 amountIn = 1 ether;
        deal(WETH_ADDR, ALICE, amountIn);

        vm.startPrank(ALICE);
        (
            IAllowanceTransfer.PermitSingle memory permitSingle,
            bytes memory signature
        ) = handlePermit2Approval(WETH_ADDR, tychoRouterAddr, amountIn);

        bytes[] memory swaps = _getSequentialSwaps(true);
        tychoRouter.sequentialSwapPermit2(
            amountIn,
            WETH_ADDR,
            USDC_ADDR,
            1000_000000, // min amount
            false,
            false,
            ALICE,
            permitSingle,
            signature,
            pleEncode(swaps)
        );

        uint256 usdcBalance = IERC20(USDC_ADDR).balanceOf(ALICE);
        assertEq(usdcBalance, 2644659787);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }

    function testSequentialSwapNoPermit2() public {
        // Trade 1 WETH for USDC through DAI - see _getSequentialSwaps for more info
        uint256 amountIn = 1 ether;
        deal(WETH_ADDR, ALICE, amountIn);

        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, amountIn);

        bytes[] memory swaps = _getSequentialSwaps(false);
        tychoRouter.sequentialSwap(
            amountIn,
            WETH_ADDR,
            USDC_ADDR,
            1000_000000, // min amount
            false,
            false,
            ALICE,
            pleEncode(swaps)
        );

        uint256 usdcBalance = IERC20(USDC_ADDR).balanceOf(ALICE);
        assertEq(usdcBalance, 2644659787);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }

    function testSequentialSwapUndefinedMinAmount() public {
        // Trade 1 WETH for USDC through DAI - see _getSequentialSwaps for more info
        uint256 amountIn = 1 ether;
        deal(WETH_ADDR, ALICE, amountIn);

        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, amountIn);

        bytes[] memory swaps = _getSequentialSwaps(false);
        vm.expectRevert(TychoRouter__UndefinedMinAmountOut.selector);
        tychoRouter.sequentialSwap(
            amountIn,
            WETH_ADDR,
            USDC_ADDR,
            0, // min amount
            false,
            false,
            ALICE,
            pleEncode(swaps)
        );
    }

    function testSequentialSwapInsufficientApproval() public {
        // Trade 1 WETH for USDC through DAI - see _getSequentialSwaps for more info
        uint256 amountIn = 1 ether;
        deal(WETH_ADDR, ALICE, amountIn);

        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, amountIn - 1);

        bytes[] memory swaps = _getSequentialSwaps(false);
        vm.expectRevert();
        tychoRouter.sequentialSwap(
            amountIn,
            WETH_ADDR,
            USDC_ADDR,
            0, // min amount
            false,
            false,
            ALICE,
            pleEncode(swaps)
        );
    }

    function testSequentialSwapNegativeSlippageFailure() public {
        // Trade 1 WETH for USDC through DAI - see _getSequentialSwaps for more info

        uint256 amountIn = 1 ether;
        deal(WETH_ADDR, ALICE, amountIn);
        vm.startPrank(ALICE);
        (
            IAllowanceTransfer.PermitSingle memory permitSingle,
            bytes memory signature
        ) = handlePermit2Approval(WETH_ADDR, tychoRouterAddr, amountIn);

        bytes[] memory swaps = _getSequentialSwaps(true);

        uint256 minAmountOut = 3000 * 1e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                TychoRouter__NegativeSlippage.selector,
                2644659787, // actual amountOut
                minAmountOut
            )
        );
        tychoRouter.sequentialSwapPermit2(
            amountIn,
            WETH_ADDR,
            DAI_ADDR,
            minAmountOut,
            false,
            false,
            ALICE,
            permitSingle,
            signature,
            pleEncode(swaps)
        );
        vm.stopPrank();
    }

    function testSequentialSwapWrapETH() public {
        uint256 amountIn = 1 ether;
        deal(ALICE, amountIn);
        vm.startPrank(ALICE);

        IAllowanceTransfer.PermitSingle memory emptyPermitSingle =
        IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: address(0),
                amount: 0,
                expiration: 0,
                nonce: 0
            }),
            spender: address(0),
            sigDeadline: 0
        });

        bytes[] memory swaps = new bytes[](2);
        // WETH -> DAI
        swaps[0] = encodeSequentialSwap(
            address(usv2Executor),
            encodeUniswapV2Swap(
                WETH_ADDR,
                WETH_DAI_POOL,
                tychoRouterAddr,
                false,
                TokenTransfer.TransferType.TRANSFER_TO_PROTOCOL
            )
        );

        // DAI -> USDC
        swaps[1] = encodeSequentialSwap(
            address(usv2Executor),
            encodeUniswapV2Swap(
                DAI_ADDR,
                DAI_USDC_POOL,
                ALICE,
                true,
                TokenTransfer.TransferType.TRANSFER_TO_PROTOCOL
            )
        );

        uint256 amountOut = tychoRouter.sequentialSwapPermit2{value: amountIn}(
            amountIn,
            address(0),
            USDC_ADDR,
            1000_000000,
            true,
            false,
            ALICE,
            emptyPermitSingle,
            "",
            pleEncode(swaps)
        );
        uint256 expectedAmount = 2644659787;
        assertEq(amountOut, expectedAmount);
        uint256 usdcBalance = IERC20(USDC_ADDR).balanceOf(ALICE);
        assertEq(usdcBalance, expectedAmount);
        assertEq(ALICE.balance, 0);

        vm.stopPrank();
    }

    function testSequentialSwapUnwrapETH() public {
        // Trade 3k DAI for WETH with 1 swap on Uniswap V2 and unwrap it at the end

        uint256 amountIn = 3_000 * 10 ** 6;
        deal(USDC_ADDR, ALICE, amountIn);

        vm.startPrank(ALICE);

        (
            IAllowanceTransfer.PermitSingle memory permitSingle,
            bytes memory signature
        ) = handlePermit2Approval(USDC_ADDR, tychoRouterAddr, amountIn);

        bytes[] memory swaps = new bytes[](2);

        // USDC -> DAI
        swaps[0] = encodeSequentialSwap(
            address(usv2Executor),
            encodeUniswapV2Swap(
                USDC_ADDR,
                DAI_USDC_POOL,
                tychoRouterAddr,
                false,
                TokenTransfer.TransferType.TRANSFER_PERMIT2_TO_PROTOCOL
            )
        );

        // DAI -> WETH
        swaps[1] = encodeSequentialSwap(
            address(usv2Executor),
            encodeUniswapV2Swap(
                DAI_ADDR,
                WETH_DAI_POOL,
                tychoRouterAddr,
                true,
                TokenTransfer.TransferType.TRANSFER_TO_PROTOCOL
            )
        );

        uint256 amountOut = tychoRouter.sequentialSwapPermit2(
            amountIn,
            USDC_ADDR,
            address(0),
            1 * 10 ** 18, // min amount
            false,
            true,
            ALICE,
            permitSingle,
            signature,
            pleEncode(swaps)
        );

        uint256 expectedAmount = 1111174255471849849; // 1.11 ETH
        assertEq(amountOut, expectedAmount);
        assertEq(ALICE.balance, expectedAmount);

        vm.stopPrank();
    }

    function testCyclicSequentialSwap() public {
        // This test has start and end tokens that are the same
        // The flow is:
        // USDC --(USV3)--> WETH --(USV3)--> USDC
        uint256 amountIn = 100 * 10 ** 6;
        deal(USDC_ADDR, tychoRouterAddr, amountIn);

        bytes memory usdcWethV3Pool1ZeroOneData = encodeUniswapV3Swap(
            USDC_ADDR,
            WETH_ADDR,
            tychoRouterAddr,
            USDC_WETH_USV3,
            true,
            TokenTransfer.TransferType.TRANSFER_TO_PROTOCOL
        );

        bytes memory usdcWethV3Pool2OneZeroData = encodeUniswapV3Swap(
            WETH_ADDR,
            USDC_ADDR,
            tychoRouterAddr,
            USDC_WETH_USV3_2,
            false,
            TokenTransfer.TransferType.TRANSFER_TO_PROTOCOL
        );

        bytes[] memory swaps = new bytes[](2);
        // USDC -> WETH
        swaps[0] = encodeSequentialSwap(
            address(usv3Executor), usdcWethV3Pool1ZeroOneData
        );
        // WETH -> USDC
        swaps[1] = encodeSequentialSwap(
            address(usv3Executor), usdcWethV3Pool2OneZeroData
        );

        tychoRouter.exposedSequentialSwap(amountIn, pleEncode(swaps));
        assertEq(IERC20(USDC_ADDR).balanceOf(tychoRouterAddr), 99889294);
    }

    function testUSV3USV2Integration() public {
        // Performs a sequential swap from WETH to USDC though WBTC and DAI using USV3 and USV2 pools
        //
        //   WETH ──(USV3)──> WBTC ───(USV2)──> USDC
        deal(WETH_ADDR, ALICE, 1 ether);
        uint256 balanceBefore = IERC20(USDC_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, type(uint256).max);
        // Encoded solution generated using `test_uniswap_v3_uniswap_v2`
        (bool success,) = tychoRouterAddr.call(
            hex"e8a980d70000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000018f61ec00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000bf00692e234dae75c793f67a35089c9d99245e1c58470bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc22260fac5e5542a773aa44fbcfedf7c193bc2c599000bb8004375dff511095cc5a197a54140a24efef3a416cbcdf9626bc03e24f779434178a73a0b4bad62ed000100525615deb798bb3e4dfa0139dfa1b3d433cc23b72f2260fac5e5542a773aa44fbcfedf7c193bc2c599004375dff511095cc5a197a54140a24efef3a416cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2010500"
        );

        vm.stopPrank();

        uint256 balanceAfter = IERC20(USDC_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertEq(balanceAfter - balanceBefore, 2554299052);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }

    function testUSV3USV3Integration() public {
        // Performs a sequential swap from WETH to USDC though WBTC using USV3 pools
        //
        //   WETH ──(USV3)──> WBTC ───(USV3)──> USDC
        deal(WETH_ADDR, ALICE, 1 ether);
        uint256 balanceBefore = IERC20(USDC_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, type(uint256).max);
        // Encoded solution generated using `test_uniswap_v3_uniswap_v3`
        (bool success,) = tychoRouterAddr.call(
            hex"e8a980d70000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000018f61ec00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000d600692e234dae75c793f67a35089c9d99245e1c58470bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc22260fac5e5542a773aa44fbcfedf7c193bc2c599000bb83ede3eca2a72b3aecc820e955b36f38437d01395cbcdf9626bc03e24f779434178a73a0b4bad62ed000100692e234dae75c793f67a35089c9d99245e1c58470b2260fac5e5542a773aa44fbcfedf7c193bc2c599a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000bb8cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc299ac8ca7087fa4a2a1fb6357269965a2014abc35010000000000000000000000"
        );

        vm.stopPrank();

        uint256 balanceAfter = IERC20(USDC_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertEq(balanceAfter - balanceBefore, 2647438249);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }

    function testUSV3CurveIntegration() public {
        // Performs a sequential swap from WETH to USDT though WBTC using USV3 and Curve pools
        //
        //   WETH ──(USV3)──> WBTC ───(USV3)──> USDT
        deal(WETH_ADDR, ALICE, 1 ether);
        uint256 balanceBefore = IERC20(USDT_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, type(uint256).max);
        // Encoded solution generated using `test_uniswap_v3_curve`
        (bool success,) = tychoRouterAddr.call(
            hex"e8a980d70000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000018f61ec00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000d600692e234dae75c793f67a35089c9d99245e1c58470bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc22260fac5e5542a773aa44fbcfedf7c193bc2c599000bb83ede3eca2a72b3aecc820e955b36f38437d01395cbcdf9626bc03e24f779434178a73a0b4bad62ed000100691d1499e622d69689cdf9004d05ec547d650ff2112260fac5e5542a773aa44fbcfedf7c193bc2c599dac17f958d2ee523a2206206994597c13d831ec7d51a44d3fae010294c616388b506acda1bfaae460301000105cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc200000000000000000000"
        );

        vm.stopPrank();

        uint256 balanceAfter = IERC20(USDT_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertEq(balanceAfter - balanceBefore, 2650183330);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }

    function testBalancerV2USV2Integration() public {
        // Performs a sequential swap from WETH to USDC though WBTC using Balancer v2 and USV2 pools
        //
        //   WETH ──(balancer)──> WBTC ───(USV2)──> USDC
        deal(WETH_ADDR, ALICE, 1 ether);
        uint256 balanceBefore = IERC20(USDT_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, type(uint256).max);
        // Encoded solution generated using `test_uniswap_v3_curve`
        (bool success,) = tychoRouterAddr.call(
            hex"e8a980d70000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000018f61ec00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000c80072c7183455a4c133ae270771860664b6b7ec320bb1c02aaa39b223fe8d0a0e5c4f27ead9083c756cc22260fac5e5542a773aa44fbcfedf7c193bc2c599a6f548df93de924d73be7d25dc02554c6bd66db500020000000000000000000e004375dff511095cc5a197a54140a24efef3a416010300525615deb798bb3e4dfa0139dfa1b3d433cc23b72f2260fac5e5542a773aa44fbcfedf7c193bc2c599004375dff511095cc5a197a54140a24efef3a416cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc20105000000000000000000000000000000000000000000000000"
        );

        vm.stopPrank();

        uint256 balanceAfter = IERC20(USDC_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertEq(balanceAfter - balanceBefore, 2549391308);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }
}
