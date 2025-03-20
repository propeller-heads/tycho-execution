// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@src/executors/SkyExecutor.sol";
import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {Constants} from "../Constants.sol";

contract SkyExecutorExposed is SkyExecutor {
    function decodeData(
        bytes calldata data
    )
        external
        pure
        returns (
            IERC20 tokenIn,
            IERC20 tokenOut,
            address componentAddress,
            address receiver,
            uint8 componentType,
            bytes memory extraData
        )
    {
        return _decodeData(data);
    }

    function determineComponentType(
        address componentAddress
    ) external pure returns (uint8) {
        return _determineComponentType(componentAddress);
    }
}

contract SkyExecutorTest is Test, Constants {
    using SafeERC20 for IERC20;

    SkyExecutorExposed skyExecutorExposed;
    SkyExecutor skyExecutor;

    // Sky protocol addresses
    address constant SDAI_VAULT_ADDRESS =
        0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address constant DAI_USDS_CONVERTER_ADDRESS =
        0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A;
    address constant DAI_LITE_PSM_ADDRESS =
        0xf6e72Db5454dd049d0788e411b06CfAF16853042;
    address constant USDS_PSM_WRAPPER_ADDRESS =
        0xA188EEC8F81263234dA3622A406892F3D630f98c;
    address constant SUSDS_ADDRESS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address constant MKR_SKY_CONVERTER_ADDRESS =
        0xBDcFCA946b6CDd965f99a839e4435Bcdc1bc470B;

    // Token addresses
    address constant USDS_ADDR = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address constant MKR_ADDR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address constant SKY_ADDR = 0x56072C95FAA701256059aa122697B133aDEd9279;

    // Forks and testing
    uint256 mainnetFork;

    function setUp() public {
        // Fork mainnet for testing real contracts
        mainnetFork = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(mainnetFork);

        // Use a recent block number where the SkySwap contracts are deployed
        vm.rollFork(18000000);

        skyExecutorExposed = new SkyExecutorExposed();
        skyExecutor = new SkyExecutor();

        // Label addresses for better error messages
        vm.label(SDAI_VAULT_ADDRESS, "sDAI Vault");
        vm.label(DAI_USDS_CONVERTER_ADDRESS, "DAI-USDS Converter");
        vm.label(DAI_LITE_PSM_ADDRESS, "DAI Lite PSM");
        vm.label(DAI_ADDR, "DAI");
        vm.label(USDS_ADDR, "USDS");
        vm.label(USDC_ADDR, "USDC");
    }

    function testDetermineComponentTypes() public view {
        assertEq(
            skyExecutorExposed.determineComponentType(SDAI_VAULT_ADDRESS),
            1
        ); // COMPONENT_TYPE_VAULT
        assertEq(skyExecutorExposed.determineComponentType(SUSDS_ADDRESS), 1); // COMPONENT_TYPE_VAULT
        assertEq(
            skyExecutorExposed.determineComponentType(
                DAI_USDS_CONVERTER_ADDRESS
            ),
            2
        ); // COMPONENT_TYPE_CONVERTER
        assertEq(
            skyExecutorExposed.determineComponentType(
                MKR_SKY_CONVERTER_ADDRESS
            ),
            2
        ); // COMPONENT_TYPE_CONVERTER
        assertEq(
            skyExecutorExposed.determineComponentType(DAI_LITE_PSM_ADDRESS),
            3
        ); // COMPONENT_TYPE_PSM
        assertEq(
            skyExecutorExposed.determineComponentType(USDS_PSM_WRAPPER_ADDRESS),
            3
        ); // COMPONENT_TYPE_PSM
    }

    function testDecodeDataBasic() public view {
        bytes memory data = abi.encodePacked(
            DAI_ADDR, // tokenIn
            USDS_ADDR, // tokenOut
            DAI_USDS_CONVERTER_ADDRESS, // component
            BOB // receiver
        );

        (
            IERC20 tokenIn,
            IERC20 tokenOut,
            address componentAddress,
            address receiver,
            uint8 componentType,
            bytes memory extraData
        ) = skyExecutorExposed.decodeData(data);

        assertEq(address(tokenIn), DAI_ADDR);
        assertEq(address(tokenOut), USDS_ADDR);
        assertEq(componentAddress, DAI_USDS_CONVERTER_ADDRESS);
        assertEq(receiver, BOB);
        assertEq(componentType, 2); // CONVERTER type
        assertEq(extraData.length, 0);
    }

    function testDecodeDataWithExtraData() public view {
        // Test vault deposit with isDeposit flag
        bytes memory depositData = abi.encodePacked(
            DAI_ADDR, // tokenIn
            SDAI_VAULT_ADDRESS, // tokenOut
            SDAI_VAULT_ADDRESS, // component
            BOB, // receiver
            bytes1(0x01) // isDeposit flag
        );

        (
            IERC20 tokenIn,
            IERC20 tokenOut,
            address componentAddress,
            address receiver,
            uint8 componentType,
            bytes memory extraData
        ) = skyExecutorExposed.decodeData(depositData);

        assertEq(address(tokenIn), DAI_ADDR);
        assertEq(address(tokenOut), SDAI_VAULT_ADDRESS);
        assertEq(componentAddress, SDAI_VAULT_ADDRESS);
        assertEq(receiver, BOB);
        assertEq(componentType, 1); // VAULT type
        assertEq(extraData.length, 1);
        assertEq(uint8(extraData[0]), 1); // isDeposit = true

        // Test PSM with fee parameter
        bytes memory psmData = abi.encodePacked(
            DAI_ADDR, // tokenIn
            USDC_ADDR, // tokenOut
            DAI_LITE_PSM_ADDRESS, // component
            BOB, // receiver
            bytes3(0x000064) // fee (100 = 1%)
        );

        (
            IERC20 tokenIn2,
            IERC20 tokenOut2,
            address componentAddress2,
            address receiver2,
            uint8 componentType2,
            bytes memory extraData2
        ) = skyExecutorExposed.decodeData(psmData);

        assertEq(address(tokenIn2), DAI_ADDR);
        assertEq(address(tokenOut2), USDC_ADDR);
        assertEq(componentAddress2, DAI_LITE_PSM_ADDRESS);
        assertEq(receiver2, BOB);
        assertEq(componentType2, 3); // PSM type
        assertEq(extraData2.length, 3);
    }

    function testDecodeDataInvalidLength() public {
        bytes memory invalidData = abi.encodePacked(
            DAI_ADDR, // tokenIn
            USDS_ADDR // tokenOut (missing component address and receiver)
        );

        vm.expectRevert(SkyExecutor__InvalidDataLength.selector);
        skyExecutorExposed.decodeData(invalidData);
    }

    function testVaultSwap() public {
        uint256 amountIn = 100 * 10 ** 18; // 100 DAI

        // Create data for sDAI vault deposit
        bytes memory depositData = abi.encodePacked(
            DAI_ADDR, // tokenIn
            SDAI_VAULT_ADDRESS, // tokenOut
            SDAI_VAULT_ADDRESS, // component
            address(this), // receiver
            bytes1(0x01) // isDeposit flag
        );

        // Give this contract some DAI
        deal(DAI_ADDR, address(this), amountIn);

        // Approve the executor to spend our tokens
        IERC20(DAI_ADDR).approve(address(skyExecutor), amountIn);

        // Mock the deposit function (since we can't really execute it in the test)
        vm.mockCall(
            SDAI_VAULT_ADDRESS,
            abi.encodeWithSignature(
                "deposit(uint256,address)",
                amountIn,
                address(this)
            ),
            abi.encode(amountIn) // 1:1 for simplicity
        );

        // Execute the swap
        uint256 amountOut = skyExecutor.swap(amountIn, depositData);

        // Verify the result
        assertEq(
            amountOut,
            amountIn,
            "Incorrect output amount for vault deposit"
        );
    }

    function testConverterSwap() public {
        uint256 amountIn = 100 * 10 ** 18; // 100 DAI

        // Create data for DAI-USDS conversion
        bytes memory converterData = abi.encodePacked(
            DAI_ADDR, // tokenIn
            USDS_ADDR, // tokenOut
            DAI_USDS_CONVERTER_ADDRESS, // component
            address(this) // receiver
        );

        // Give this contract some DAI
        deal(DAI_ADDR, address(this), amountIn);

        // Approve the executor to spend our tokens
        IERC20(DAI_ADDR).approve(address(skyExecutor), amountIn);

        // Mock the converter function
        vm.mockCall(
            DAI_USDS_CONVERTER_ADDRESS,
            abi.encodeWithSignature(
                "swapExactInput(address,address,uint256,address)",
                DAI_ADDR,
                USDS_ADDR,
                amountIn,
                address(this)
            ),
            abi.encode(amountIn) // 1:1 conversion
        );

        // Execute the swap
        uint256 amountOut = skyExecutor.swap(amountIn, converterData);

        // Verify the result
        assertEq(
            amountOut,
            amountIn,
            "Incorrect output amount for converter swap"
        );
    }

    function testPSMSwap() public {
        uint256 amountIn = 100 * 10 ** 18; // 100 DAI
        uint24 fee = 100; // 1% fee
        uint256 expectedOut = amountIn - ((amountIn * fee) / 10000); // Subtract 1% fee

        // Create data for DAI-USDC PSM swap with fee
        bytes memory psmData = abi.encodePacked(
            DAI_ADDR, // tokenIn
            USDC_ADDR, // tokenOut
            DAI_LITE_PSM_ADDRESS, // component
            address(this), // receiver
            bytes3(uint24(fee))
        );

        // Give this contract some DAI
        deal(DAI_ADDR, address(this), amountIn);

        // Approve the executor to spend our tokens
        IERC20(DAI_ADDR).approve(address(skyExecutor), amountIn);

        // Mock the PSM function with fee
        vm.mockCall(
            DAI_LITE_PSM_ADDRESS,
            abi.encodeWithSignature(
                "swapWithFee(address,address,uint256,address,uint24)",
                DAI_ADDR,
                USDC_ADDR,
                amountIn,
                address(this),
                fee
            ),
            abi.encode(expectedOut)
        );

        // Execute the swap
        uint256 amountOut = skyExecutor.swap(amountIn, psmData);

        // Verify the result
        assertEq(
            amountOut,
            expectedOut,
            "Incorrect output amount for PSM swap with fee"
        );
    }

    function testIntegrationWithSkySwapEncoder() public view {
        console.log("BOB address:", BOB);

        // For a converter component (DAI-USDS Converter)
        bytes memory converterEncoding = abi.encodePacked(
            DAI_ADDR, // tokenIn
            USDS_ADDR, // tokenOut
            DAI_USDS_CONVERTER_ADDRESS, // component
            BOB // receiver
        );

        (
            IERC20 tokenIn1,
            IERC20 tokenOut1,
            address componentAddress1,
            address receiver1,
            uint8 componentType1,
            bytes memory extraData1
        ) = skyExecutorExposed.decodeData(converterEncoding);

        assertEq(address(tokenIn1), DAI_ADDR);
        assertEq(address(tokenOut1), USDS_ADDR);
        assertEq(componentAddress1, DAI_USDS_CONVERTER_ADDRESS);
        assertEq(receiver1, BOB);
        assertEq(componentType1, 2); // COMPONENT_TYPE_CONVERTER
        assertEq(extraData1.length, 0);

        // For a vault deposit
        bytes memory vaultDepositEncoding = abi.encodePacked(
            DAI_ADDR, // tokenIn
            SDAI_VAULT_ADDRESS, // tokenOut
            SDAI_VAULT_ADDRESS, // component
            BOB, // receiver
            bytes1(0x01) // isDeposit flag
        );

        (
            IERC20 tokenIn2,
            IERC20 tokenOut2,
            address componentAddress2,
            address receiver2,
            uint8 componentType2,
            bytes memory extraData2
        ) = skyExecutorExposed.decodeData(vaultDepositEncoding);

        assertEq(address(tokenIn2), DAI_ADDR);
        assertEq(address(tokenOut2), SDAI_VAULT_ADDRESS);
        assertEq(componentAddress2, SDAI_VAULT_ADDRESS);
        assertEq(receiver2, BOB);
        assertEq(componentType2, 1); // COMPONENT_TYPE_VAULT
        assertEq(extraData2.length, 1);
        assertEq(uint8(extraData2[0]), 1); // isDeposit = true

        // For a PSM with fee
        bytes memory psmEncoding = abi.encodePacked(
            DAI_ADDR, // tokenIn
            USDC_ADDR, // tokenOut
            DAI_LITE_PSM_ADDRESS, // component
            BOB, // receiver
            bytes3(0x000064) // fee (100 = 1%)
        );

        (
            IERC20 tokenIn3,
            IERC20 tokenOut3,
            address componentAddress3,
            address receiver3,
            uint8 componentType3,
            bytes memory extraData3
        ) = skyExecutorExposed.decodeData(psmEncoding);

        assertEq(address(tokenIn3), DAI_ADDR);
        assertEq(address(tokenOut3), USDC_ADDR);
        assertEq(componentAddress3, DAI_LITE_PSM_ADDRESS);
        assertEq(receiver3, BOB);
        assertEq(componentType3, 3); // COMPONENT_TYPE_PSM
        assertEq(extraData3.length, 3);
    }

    // This test verifies the format of data from the SkySwapEncoder
    function testExtraDataFormat() public view {
        // Based on the Rust encoder test_encode_sky_swap for PSM component with fee
        bytes
            memory encodedPSMData = hex"6b175474e89094c44da98b954eedeac495271d0fa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48f6e72db5454dd049d0788e411b06cfaf168530421d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e000064";

        (
            IERC20 tokenIn,
            IERC20 tokenOut,
            address componentAddress,
            address receiver,
            uint8 componentType,
            bytes memory extraData
        ) = skyExecutorExposed.decodeData(encodedPSMData);

        // Verify the decoded data
        assertEq(address(tokenIn), DAI_ADDR);
        assertEq(address(tokenOut), USDC_ADDR);
        assertEq(componentAddress, DAI_LITE_PSM_ADDRESS);
        assertEq(receiver, BOB);
        assertEq(componentType, 3); // COMPONENT_TYPE_PSM

        // Important: verify the format of the fee data
        assertEq(extraData.length, 3);
        assertEq(uint24(bytes3(extraData)), 100); // Fee should be 100 (1%)
    }
}
