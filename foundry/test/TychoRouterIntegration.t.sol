// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./TychoRouterTestSetup.sol";

contract TychoRouterTestIntegration is TychoRouterTestSetup {
    function testSplitSwapSingleWithoutPermit2Integration() public {
        // Tests swapping WETH -> DAI on a USV2 pool without permit2
        deal(WETH_ADDR, ALICE, 1 ether);
        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(address(tychoRouterAddr), 1 ether);
        uint256 balancerBefore = IERC20(DAI_ADDR).balanceOf(ALICE);
        // Encoded solution generated using `test_split_swap_strategy_encoder_no_permit2`
        (bool success,) = tychoRouterAddr.call(
            hex"79b9b93b0000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000008f1d5c1cae37400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc200000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000059005700010000005615deb798bb3e4dfa0139dfa1b3d433cc23b72fc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a478c2975ab1ea89e8196811f51a7b7ade33eb113ede3eca2a72b3aecc820e955b36f38437d01395000100000000000000"
        );

        vm.stopPrank();
        uint256 balancerAfter = IERC20(DAI_ADDR).balanceOf(ALICE);
        assertTrue(success, "Call Failed");
        assertEq(balancerAfter - balancerBefore, 2659881924818443699787);
    }

    function testSplitUSV4Integration() public {
        // Test created with calldata from our router encoder.

        // Performs a sequential swap from USDC to PEPE though ETH using two
        // consecutive USV4 pools
        //
        //   USDC ──(USV4)──> ETH ───(USV4)──> PEPE
        //
        deal(USDC_ADDR, ALICE, 1 ether);
        uint256 balancerBefore = IERC20(PEPE_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(USDC_ADDR).approve(PERMIT2_ADDRESS, type(uint256).max);
        // Encoded solution generated using `test_split_encoding_strategy_usv4`
        (bool success,) = tychoRouterAddr.call(
            hex"7c553846000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006982508145454ce325ddbe47a25d4ec3d23119330000000000000000000000000000000000000000005064ff624d54346285543f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000003b9aca0000000000000000000000000000000000000000000000000000000000682163b600000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ede3eca2a72b3aecc820e955b36f38437d013950000000000000000000000000000000000000000000000000000000067f9ddbe000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002800000000000000000000000000000000000000000000000000000000000000041e9e58e3facf99cd2c64b834d3b646b8cf9377c47540d65b5e180a06bca6f42851cf320a205cf466c7943abe45c2998afa6fd3d870043a108578e71256831ca1c1c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008d008b0001000000f62849f9a0b5bf2913b396098f7c7019b51a820aa0b86991c6218b36c1d19d4a2e9eb0ce3606eb486982508145454ce325ddbe47a25d4ec3d231193300f62849f9a0b5bf2913b396098f7c7019b51a820a040000000000000000000000000000000000000000000bb800003c6982508145454ce325ddbe47a25d4ec3d23119330061a80001f400000000000000000000000000000000000000"
        );

        vm.stopPrank();

        uint256 balancerAfter = IERC20(PEPE_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertEq(balancerAfter - balancerBefore, 97191013220606467325121599);
    }

    function testSplitUSV4IntegrationInputETH() public {
        // Test created with calldata from our router encoder.

        // Performs a single swap from ETH to PEPE without wrapping or unwrapping
        //
        //   ETH ───(USV4)──> PEPE
        //
        deal(ALICE, 1 ether);
        uint256 balancerBefore = IERC20(PEPE_ADDR).balanceOf(ALICE);

        // Encoded solution generated using `test_split_encoding_strategy_usv4_eth_in`
        (bool success,) = tychoRouterAddr.call{value: 1 ether}(
            hex"7c5538460000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006982508145454ce325ddbe47a25d4ec3d2311933000000000000000000000000000000000000000000c87c939ae635f92dc2379c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000006821689800000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ede3eca2a72b3aecc820e955b36f38437d013950000000000000000000000000000000000000000000000000000000067f9e2a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000028000000000000000000000000000000000000000000000000000000000000000412da8d5aab101bbdf256d785a42db176328e8298ee6d0906e0ef1998cfcaa332460f8409d9b298dff73c947796a22c8de21caa17405ea157ced090da2b6cb27431c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007300710001000000f62849f9a0b5bf2913b396098f7c7019b51a820a00000000000000000000000000000000000000006982508145454ce325ddbe47a25d4ec3d231193301f62849f9a0b5bf2913b396098f7c7019b51a820a056982508145454ce325ddbe47a25d4ec3d23119330061a80001f400000000000000000000000000"
        );

        vm.stopPrank();

        uint256 balancerAfter = IERC20(PEPE_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertEq(balancerAfter - balancerBefore, 242373460199848577067005852);
    }

    function testSplitUSV4IntegrationOutputETH() public {
        // Test created with calldata from our router encoder.

        // Performs a single swap from USDC to ETH without wrapping or unwrapping
        //
        //   USDC ───(USV4)──> ETH
        //
        deal(USDC_ADDR, ALICE, 3000_000000);
        uint256 balancerBefore = ALICE.balance;

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(USDC_ADDR).approve(PERMIT2_ADDRESS, type(uint256).max);

        // Encoded solution generated using `test_split_encoding_strategy_usv4_eth_out`
        (bool success,) = tychoRouterAddr.call(
            hex"7c55384600000000000000000000000000000000000000000000000000000000b2d05e00000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f81490b4f29aade000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000b2d05e0000000000000000000000000000000000000000000000000000000000682163ee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ede3eca2a72b3aecc820e955b36f38437d013950000000000000000000000000000000000000000000000000000000067f9ddf60000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000028000000000000000000000000000000000000000000000000000000000000000416056d925e7906c11b865992ac5c853532f5058bb57b67cd000a53b899503dd8a6fd4c0e5ea44c1ca4137753589bf89f66824796e719e807adee7567a707ee6681b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007300710001000000f62849f9a0b5bf2913b396098f7c7019b51a820aa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000f62849f9a0b5bf2913b396098f7c7019b51a820a040000000000000000000000000000000000000000000bb800003c00000000000000000000000000"
        );

        vm.stopPrank();

        uint256 balancerAfter = ALICE.balance;

        assertTrue(success, "Call Failed");
        console.logUint(balancerAfter - balancerBefore);
        assertEq(balancerAfter - balancerBefore, 1117254495486192350);
    }

    function testSplitSwapSingleWithWrapIntegration() public {
        // Tests swapping WETH -> DAI on a USV2 pool, but ETH is received from the user
        // and wrapped before the swap
        deal(ALICE, 1 ether);
        uint256 balancerBefore = IERC20(DAI_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        // Encoded solution generated using `test_split_swap_strategy_encoder_wrap`
        (bool success,) = tychoRouterAddr.call{value: 1 ether}(
            hex"7c5538460000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000903146e5f6c59c064b000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000006821640400000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ede3eca2a72b3aecc820e955b36f38437d013950000000000000000000000000000000000000000000000000000000067f9de0c000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002800000000000000000000000000000000000000000000000000000000000000041b34e1f3d4e78942b2429b776073a5dfab1420f763de7d7e2a2296ca8abf684f923f7ae7945e824d8a084b9610d33ed49246a36e8e0efbce8ae210b0474f9fe3a1b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000059005700020000005615deb798bb3e4dfa0139dfa1b3d433cc23b72fc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a478c2975ab1ea89e8196811f51a7b7ade33eb113ede3eca2a72b3aecc820e955b36f38437d01395000000000000000000"
        );

        vm.stopPrank();

        uint256 balancerAfter = IERC20(DAI_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertEq(balancerAfter - balancerBefore, 2659881924818443699787);
    }

    function testSplitSwapSingleWithUnwrapIntegration() public {
        // Tests swapping DAI -> WETH on a USV2 pool, and WETH is unwrapped to ETH
        // before sending back to the user
        deal(DAI_ADDR, ALICE, 3000 ether);
        uint256 balancerBefore = ALICE.balance;

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(DAI_ADDR).approve(PERMIT2_ADDRESS, type(uint256).max);
        // Encoded solution generated using `test_split_swap_strategy_encoder_unwrap`
        (bool success,) = tychoRouterAddr.call(
            hex"7c5538460000000000000000000000000000000000000000000000a2a15d09519be000000000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc20000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000a2a15d09519be00000000000000000000000000000000000000000000000000000000000006821641200000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ede3eca2a72b3aecc820e955b36f38437d013950000000000000000000000000000000000000000000000000000000067f9de1a00000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000280000000000000000000000000000000000000000000000000000000000000004181d23336d0cacd47a4d228590a825a1d92a48378cd481ff308b6d235e14b925c584f31e420682879bea58363ca4aa44a3b79557b15a9f73078a4696e00f55f911b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000059005700010000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f6b175474e89094c44da98b954eedeac495271d0fa478c2975ab1ea89e8196811f51a7b7ade33eb113ede3eca2a72b3aecc820e955b36f38437d01395010200000000000000"
        );

        vm.stopPrank();

        uint256 balancerAfter = ALICE.balance;

        assertTrue(success, "Call Failed");
        assertEq(balancerAfter - balancerBefore, 1120007305574805922);
    }

    function testSplitEkuboIntegration() public {
        // Test needs to be run on block 22082754 or later
        // notice that the addresses for the tycho router and the executors are different because we are redeploying
        vm.rollFork(22082754);
        tychoRouter = deployRouter();
        address[] memory executors = deployExecutors();
        vm.startPrank(EXECUTOR_SETTER);
        tychoRouter.setExecutors(executors);
        vm.stopPrank();

        deal(ALICE, 1 ether);
        uint256 balancerBefore = IERC20(USDC_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        // Encoded solution generated using `test_split_encoding_strategy_ekubo`
        (bool success,) = address(tychoRouter).call{value: 1 ether}(
            hex"79b9b93b0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc200000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000077007500010000003d7ebc40af7092e3f1c81f2e996cba5cae2090d7a4ad4f68d0b91cfd19687c881e50f3a00242828c0000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4851d02a5948496a67827242eabc5725531342527c000000000000000000000000000000000000000000"
        );

        uint256 balancerAfter = IERC20(USDC_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertGe(balancerAfter - balancerBefore, 26173932);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }

    function testSplitSwapIntegration() public {
        // Performs a split swap from WETH to USDC though WBTC and DAI using USV2 pools
        //
        //         ┌──(USV2)──> WBTC ───(USV2)──> USDC
        //   WETH ─┤
        //         └──(USV2)──> DAI  ───(USV2)──> USDC
        deal(WETH_ADDR, ALICE, 1 ether);
        uint256 balancerBefore = IERC20(USDC_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(PERMIT2_ADDRESS, type(uint256).max);
        // Encoded solution generated using `test_split_swap_strategy_encoder_complex`
        (bool success,) = tychoRouterAddr.call(
            hex"7c5538460000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000018f61ec000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000006821643700000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ede3eca2a72b3aecc820e955b36f38437d013950000000000000000000000000000000000000000000000000000000067f9de3f00000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000280000000000000000000000000000000000000000000000000000000000000004112f41a590796702b322fa5a9ee1602daef9b22d732e4fd8f122f072b65dda325271f630759db500db8a42bd4f41ddc18ddda63650deaf36228dca702e28eefd31b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000164005700028000005615deb798bb3e4dfa0139dfa1b3d433cc23b72fc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a478c2975ab1ea89e8196811f51a7b7ade33eb113ede3eca2a72b3aecc820e955b36f38437d013950002005700010000005615deb798bb3e4dfa0139dfa1b3d433cc23b72fc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2bb2b8038a1640196fbe3e38816f3e67cba72d9403ede3eca2a72b3aecc820e955b36f38437d013950002005702030000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f6b175474e89094c44da98b954eedeac495271d0fae461ca67b15dc8dc81ce7615e0320da1a9ab8d53ede3eca2a72b3aecc820e955b36f38437d013950100005701030000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f2260fac5e5542a773aa44fbcfedf7c193bc2c599004375dff511095cc5a197a54140a24efef3a4163ede3eca2a72b3aecc820e955b36f38437d01395010000000000000000000000000000000000000000000000000000000000"
        );

        vm.stopPrank();

        uint256 balancerAfter = IERC20(USDC_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertGe(balancerAfter - balancerBefore, 26173932);

        // All input tokens are transferred to the router at first. Make sure we used
        // all of it (and thus our splits are correct).
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }

    function testSequentialSwapIntegrationPermit2() public {
        // Performs a split swap from WETH to USDC though WBTC and DAI using USV2 pools
        //
        //   WETH ──(USV2)──> WBTC ───(USV2)──> USDC
        deal(WETH_ADDR, ALICE, 1 ether);
        uint256 balancerBefore = IERC20(USDC_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(PERMIT2_ADDRESS, type(uint256).max);
        // Encoded solution generated using `test_sequential_swap_strategy_encoder_complex_route`
        (bool success,) = tychoRouterAddr.call(
            hex"51bcc7b60000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000018f61ec00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000006821644a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ede3eca2a72b3aecc820e955b36f38437d013950000000000000000000000000000000000000000000000000000000067f9de5200000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000000000000000041530bdcde0c687eacb51a339f30c7b3eff7c078a3bbd4bc852519568dcdf271bb4c6ac05583f32c4a8d1a99be3a2817fe86c15ad2a06c5cf938bde9c22bc80f301c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a800525615deb798bb3e4dfa0139dfa1b3d433cc23b72fc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2bb2b8038a1640196fbe3e38816f3e67cba72d9403ede3eca2a72b3aecc820e955b36f38437d01395000200525615deb798bb3e4dfa0139dfa1b3d433cc23b72f2260fac5e5542a773aa44fbcfedf7c193bc2c599004375dff511095cc5a197a54140a24efef3a4163ede3eca2a72b3aecc820e955b36f38437d013950100000000000000000000000000000000000000000000000000"
        );

        vm.stopPrank();

        uint256 balancerAfter = IERC20(USDC_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertEq(balancerAfter - balancerBefore, 2552915143);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }

    function testSequentialSwapIntegration() public {
        // Performs a split swap from WETH to USDC though WBTC and DAI using USV2 pools
        //
        //   WETH ──(USV2)──> WBTC ───(USV2)──> USDC
        deal(WETH_ADDR, ALICE, 1 ether);
        uint256 balancerBefore = IERC20(USDC_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(WETH_ADDR).approve(tychoRouterAddr, type(uint256).max);
        // Encoded solution generated using `test_sequential_swap_strategy_encoder_no_permit2`
        (bool success,) = tychoRouterAddr.call(
            hex"e8a980d70000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000018f61ec00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000a800525615deb798bb3e4dfa0139dfa1b3d433cc23b72fc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2bb2b8038a1640196fbe3e38816f3e67cba72d9403ede3eca2a72b3aecc820e955b36f38437d01395000100525615deb798bb3e4dfa0139dfa1b3d433cc23b72f2260fac5e5542a773aa44fbcfedf7c193bc2c599004375dff511095cc5a197a54140a24efef3a4163ede3eca2a72b3aecc820e955b36f38437d013950100000000000000000000000000000000000000000000000000"
        );

        vm.stopPrank();

        uint256 balancerAfter = IERC20(USDC_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertEq(balancerAfter - balancerBefore, 2552915143);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }

    function testCyclicSequentialSwapIntegration() public {
        deal(USDC_ADDR, ALICE, 100 * 10 ** 6);

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(USDC_ADDR).approve(PERMIT2_ADDRESS, type(uint256).max);
        // Encoded solution generated using `test_cyclic_sequential_swap`
        (bool success,) = tychoRouterAddr.call(
            hex"7c5538460000000000000000000000000000000000000000000000000000000005f5e100000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000005f4308e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000005f5e100000000000000000000000000000000000000000000000000000000006821647000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ede3eca2a72b3aecc820e955b36f38437d013950000000000000000000000000000000000000000000000000000000067f9de780000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000028000000000000000000000000000000000000000000000000000000000000000413c8b048dc7b7614106a5aa1fa13e48c02a6a9714dfa07d2c424f68b81a5f828c39ace62f2dd57d7bfad10910ae44f77d68aec5c079fce456028b1bd7f72053151c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0006e00010000002e234dae75c793f67a35089c9d99245e1c58470ba0b86991c6218b36c1d19d4a2e9eb0ce3606eb48c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f43ede3eca2a72b3aecc820e955b36f38437d0139588e6a0c2ddd26feeb64f039a2c41296fcb3f56400102006e01000000002e234dae75c793f67a35089c9d99245e1c58470bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000bb83ede3eca2a72b3aecc820e955b36f38437d013958ad599c3a0ff1de082011efddc58f1908eb6e6d80000"
        );

        assertEq(IERC20(USDC_ADDR).balanceOf(ALICE), 99889294);

        vm.stopPrank();
    }

    function testSplitInputCyclicSwapIntegration() public {
        deal(USDC_ADDR, ALICE, 100 * 10 ** 6);

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(USDC_ADDR).approve(PERMIT2_ADDRESS, type(uint256).max);
        // Encoded solution generated using `test_split_input_cyclic_swap`
        (bool success,) = tychoRouterAddr.call(
            hex"7c5538460000000000000000000000000000000000000000000000000000000005f5e100000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000005ef619b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000005f5e100000000000000000000000000000000000000000000000000000000006821659d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ede3eca2a72b3aecc820e955b36f38437d013950000000000000000000000000000000000000000000000000000000067f9dfa5000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002800000000000000000000000000000000000000000000000000000000000000041dd84c5cdc51719e377598eccd8eac0aae036e7e0745a7c65b5d44cc817071a7460ccc73934363f33cc7af71dc07545aeff1d92f8c2f0b2973e1fc37e7b2de3551c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000139006e00019999992e234dae75c793f67a35089c9d99245e1c58470ba0b86991c6218b36c1d19d4a2e9eb0ce3606eb48c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f43ede3eca2a72b3aecc820e955b36f38437d0139588e6a0c2ddd26feeb64f039a2c41296fcb3f56400102006e00010000002e234dae75c793f67a35089c9d99245e1c58470ba0b86991c6218b36c1d19d4a2e9eb0ce3606eb48c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000bb83ede3eca2a72b3aecc820e955b36f38437d013958ad599c3a0ff1de082011efddc58f1908eb6e6d80102005701000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72fc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2b4e16d0168e52d35cacd2c6185b44281ec28c9dc3ede3eca2a72b3aecc820e955b36f38437d01395000000000000000000"
        );

        assertEq(IERC20(USDC_ADDR).balanceOf(ALICE), 99574171);

        vm.stopPrank();
    }

    function testSplitOutputCyclicSwapIntegration() public {
        deal(USDC_ADDR, ALICE, 100 * 10 ** 6);

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(USDC_ADDR).approve(PERMIT2_ADDRESS, type(uint256).max);
        // Encoded solution generated using `test_split_output_cyclic_swap`
        (bool success,) = tychoRouterAddr.call(
            hex"7c5538460000000000000000000000000000000000000000000000000000000005f5e100000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000005eea514000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000005f5e10000000000000000000000000000000000000000000000000000000000682165ac00000000000000000000000000000000000000000000000000000000000000000000000000000000000000003ede3eca2a72b3aecc820e955b36f38437d013950000000000000000000000000000000000000000000000000000000067f9dfb400000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000280000000000000000000000000000000000000000000000000000000000000004107f2b0f9c2e4e308ab43b288d69de30d84b10c8075e4dd9a2cf66594f97a52fb34de2534b89bf1887da74c92fd03464f45baff700dd32e213e3add1a3f351e891b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000139005700010000005615deb798bb3e4dfa0139dfa1b3d433cc23b72fa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48b4e16d0168e52d35cacd2c6185b44281ec28c9dc3ede3eca2a72b3aecc820e955b36f38437d013950102006e01009999992e234dae75c793f67a35089c9d99245e1c58470bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480001f43ede3eca2a72b3aecc820e955b36f38437d0139588e6a0c2ddd26feeb64f039a2c41296fcb3f56400000006e01000000002e234dae75c793f67a35089c9d99245e1c58470bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000bb83ede3eca2a72b3aecc820e955b36f38437d013958ad599c3a0ff1de082011efddc58f1908eb6e6d8000000000000000000"
        );

        assertEq(IERC20(USDC_ADDR).balanceOf(ALICE), 99525908);

        vm.stopPrank();
    }

    function testSplitCurveIntegration() public {
        deal(UWU_ADDR, ALICE, 1 ether);

        vm.startPrank(ALICE);
        IERC20(UWU_ADDR).approve(tychoRouterAddr, type(uint256).max);
        // Encoded solution generated using `test_split_encoding_strategy_curve`
        (bool success,) = tychoRouterAddr.call(
            hex"79b9b93b0000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000055c08ca52497e2f1534b59e2917bf524d4765257000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc20000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000005b005900010000001d1499e622d69689cdf9004d05ec547d650ff21155c08ca52497e2f1534b59e2917bf524d4765257c02aaa39b223fe8d0a0e5c4f27ead9083c756cc277146b0a1d08b6844376df6d9da99ba7f1b19e71020100010000000000"
        );

        assertEq(IERC20(WETH_ADDR).balanceOf(ALICE), 4691958787921);

        vm.stopPrank();
    }

    function testSplitCurveIntegrationStETH() public {
        deal(ALICE, 1 ether);

        vm.startPrank(ALICE);
        // Encoded solution generated using `test_split_encoding_strategy_curve_st_eth`
        (bool success,) = tychoRouterAddr.call{value: 1 ether}(
            hex"79b9b93b0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc20000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000005b005900010000001d1499e622d69689cdf9004d05ec547d650ff211eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeae7ab96520de3a18e5e111b5eaab095312d7fe84dc24316b9ae028f1497c275eb9192a3ea0f67022010001000000000000"
        );

        assertEq(IERC20(STETH_ADDR).balanceOf(ALICE), 1000754689941529590);

        vm.stopPrank();
    }
}
