// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@src/executors/SkyExecutor.sol";
import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {Constants} from "../Constants.sol";

contract SkyExecutorExposed is SkyExecutor {
    function decodeData(bytes calldata data)
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

    function determineComponentType(address componentAddress)
        external
        pure
        returns (uint8)
    {
        return _determineComponentType(componentAddress);
    }
}

contract SkyExecutorTest is Test, Constants {
    using SafeERC20 for IERC20;

    SkyExecutorExposed skyExecutorExposed;
    SkyExecutor skyExecutor;

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

    address constant USDS_ADDR = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address constant MKR_ADDR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address constant SKY_ADDR = 0x56072C95FAA701256059aa122697B133aDEd9279;

    function setUp() public {
        uint256 forkBlock = 21678075;
        vm.createSelectFork(vm.rpcUrl("mainnet"), forkBlock);

        skyExecutorExposed = new SkyExecutorExposed();
        skyExecutor = new SkyExecutor();

        vm.label(SDAI_VAULT_ADDRESS, "sDAI Vault");
        vm.label(DAI_USDS_CONVERTER_ADDRESS, "DAI-USDS Converter");
        vm.label(DAI_LITE_PSM_ADDRESS, "DAI Lite PSM");
        vm.label(DAI_ADDR, "DAI");
        vm.label(USDS_ADDR, "USDS");
        vm.label(USDC_ADDR, "USDC");
    }

    function testDetermineComponentTypes() public view {
        assertEq(
            skyExecutorExposed.determineComponentType(SDAI_VAULT_ADDRESS), 1
        );
        assertEq(skyExecutorExposed.determineComponentType(SUSDS_ADDRESS), 1);
        assertEq(
            skyExecutorExposed.determineComponentType(
                DAI_USDS_CONVERTER_ADDRESS
            ),
            2
        );
        assertEq(
            skyExecutorExposed.determineComponentType(MKR_SKY_CONVERTER_ADDRESS),
            2
        );
        assertEq(
            skyExecutorExposed.determineComponentType(DAI_LITE_PSM_ADDRESS), 3
        );
        assertEq(
            skyExecutorExposed.determineComponentType(USDS_PSM_WRAPPER_ADDRESS),
            3
        );
    }

    function testDecodeDataBasic() public view {
        bytes memory data = abi.encodePacked(
            DAI_ADDR, USDS_ADDR, DAI_USDS_CONVERTER_ADDRESS, BOB
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
        assertEq(componentType, 2);
        assertEq(extraData.length, 0);
    }

    function testDecodeDataWithExtraData() public view {
        bytes memory depositData = abi.encodePacked(
            DAI_ADDR, SDAI_VAULT_ADDRESS, SDAI_VAULT_ADDRESS, BOB, bytes1(0x01)
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
        assertEq(componentType, 1);
        assertEq(extraData.length, 1);
        assertEq(uint8(extraData[0]), 1); // isDeposit = true

        bytes memory psmData = abi.encodePacked(
            DAI_ADDR,
            USDC_ADDR,
            DAI_LITE_PSM_ADDRESS,
            BOB,
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
        assertEq(componentType2, 3);
        assertEq(extraData2.length, 3);
    }

    function testDecodeDataInvalidLength() public {
        bytes memory invalidData = abi.encodePacked(DAI_ADDR, USDS_ADDR);

        vm.expectRevert(SkyExecutor__InvalidDataLength.selector);
        skyExecutorExposed.decodeData(invalidData);
    }

    function testVaultSwap() public {
        uint256 amountIn = 100 * 10 ** 18; // 100 DAI

        bytes memory depositData = abi.encodePacked(
            DAI_ADDR,
            SDAI_VAULT_ADDRESS,
            SDAI_VAULT_ADDRESS,
            address(this),
            bytes1(0x01)
        );

        deal(DAI_ADDR, address(this), amountIn);

        IERC20(DAI_ADDR).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            SDAI_VAULT_ADDRESS,
            abi.encodeWithSignature(
                "deposit(uint256,address)", amountIn, address(this)
            ),
            abi.encode(amountIn)
        );

        uint256 amountOut = skyExecutor.swap(amountIn, depositData);

        assertEq(
            amountOut, amountIn, "Incorrect output amount for vault deposit"
        );
    }

    function testConverterSwap() public {
        uint256 amountIn = 100 * 10 ** 18; // 100 DAI

        bytes memory converterData = abi.encodePacked(
            DAI_ADDR, USDS_ADDR, DAI_USDS_CONVERTER_ADDRESS, address(this)
        );

        deal(DAI_ADDR, address(this), amountIn);

        IERC20(DAI_ADDR).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            DAI_USDS_CONVERTER_ADDRESS,
            abi.encodeWithSignature(
                "swapExactInput(address,address,uint256,address)",
                DAI_ADDR,
                USDS_ADDR,
                amountIn,
                address(this)
            ),
            abi.encode(amountIn)
        );

        uint256 amountOut = skyExecutor.swap(amountIn, converterData);

        assertEq(
            amountOut, amountIn, "Incorrect output amount for converter swap"
        );
    }

    function testPSMSwap() public {
        uint256 amountIn = 100 * 10 ** 18; // 100 DAI
        uint24 fee = 100; // 1% fee
        uint256 expectedOut = amountIn - ((amountIn * fee) / 10000); // Subtract 1% fee

        bytes memory psmData = abi.encodePacked(
            DAI_ADDR,
            USDC_ADDR,
            DAI_LITE_PSM_ADDRESS,
            address(this),
            bytes3(uint24(fee))
        );

        deal(DAI_ADDR, address(this), amountIn);

        IERC20(DAI_ADDR).approve(address(skyExecutor), amountIn);

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

        uint256 amountOut = skyExecutor.swap(amountIn, psmData);

        assertEq(
            amountOut,
            expectedOut,
            "Incorrect output amount for PSM swap with fee"
        );
    }

    function testIntegrationWithSkySwapEncoder() public view {
        console.log("BOB address:", BOB);

        bytes memory converterEncoding = abi.encodePacked(
            DAI_ADDR, USDS_ADDR, DAI_USDS_CONVERTER_ADDRESS, BOB
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
        assertEq(componentType1, 2);
        assertEq(extraData1.length, 0);

        bytes memory vaultDepositEncoding = abi.encodePacked(
            DAI_ADDR, SDAI_VAULT_ADDRESS, SDAI_VAULT_ADDRESS, BOB, bytes1(0x01)
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
        assertEq(componentType2, 1);
        assertEq(extraData2.length, 1);
        assertEq(uint8(extraData2[0]), 1);

        bytes memory psmEncoding = abi.encodePacked(
            DAI_ADDR,
            USDC_ADDR,
            DAI_LITE_PSM_ADDRESS,
            BOB,
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
        assertEq(componentType3, 3);
        assertEq(extraData3.length, 3);
    }

    function testExtraDataFormat() public view {
        bytes memory encodedPSMData =
            hex"6b175474e89094c44da98b954eedeac495271d0fa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48f6e72db5454dd049d0788e411b06cfaf168530421d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e000064";

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
        assertEq(componentType, 3);

        // Important: verify the format of the fee data
        assertEq(extraData.length, 3);
        assertEq(uint24(bytes3(extraData)), 100); // Fee should be 100 (1%)
    }

    function testVaultWithdraw() public {
        uint256 amountIn = 100 * 10 ** 18; // 100 sDAI

        bytes memory withdrawData = abi.encodePacked(
            SDAI_VAULT_ADDRESS,
            DAI_ADDR,
            SDAI_VAULT_ADDRESS,
            address(this),
            bytes1(0x00) // isDeposit flag = false (withdraw)
        );

        deal(SDAI_VAULT_ADDRESS, address(this), amountIn);
        IERC20(SDAI_VAULT_ADDRESS).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            SDAI_VAULT_ADDRESS,
            abi.encodeWithSignature(
                "withdraw(uint256,address,address)",
                amountIn,
                address(this),
                address(skyExecutor)
            ),
            abi.encode(amountIn)
        );

        uint256 amountOut = skyExecutor.swap(amountIn, withdrawData);
        assertEq(
            amountOut, amountIn, "Incorrect output amount for vault withdrawal"
        );
    }

    function testSUSdsVaultDeposit() public {
        uint256 amountIn = 100 * 10 ** 18; // 100 USDS

        bytes memory depositData = abi.encodePacked(
            USDS_ADDR,
            SUSDS_ADDRESS,
            SUSDS_ADDRESS,
            address(this),
            bytes1(0x01) // isDeposit flag = true
        );

        deal(USDS_ADDR, address(this), amountIn);
        IERC20(USDS_ADDR).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            SUSDS_ADDRESS,
            abi.encodeWithSignature(
                "deposit(uint256,address)", amountIn, address(this)
            ),
            abi.encode(amountIn)
        );

        uint256 amountOut = skyExecutor.swap(amountIn, depositData);
        assertEq(
            amountOut, amountIn, "Incorrect output amount for sUSDS deposit"
        );
    }

    function testSUSdsVaultWithdraw() public {
        uint256 amountIn = 100 * 10 ** 18; // 100 sUSDS

        bytes memory withdrawData = abi.encodePacked(
            SUSDS_ADDRESS,
            USDS_ADDR,
            SUSDS_ADDRESS,
            address(this),
            bytes1(0x00) // isDeposit flag = false (withdraw)
        );

        deal(SUSDS_ADDRESS, address(this), amountIn);
        IERC20(SUSDS_ADDRESS).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            SUSDS_ADDRESS,
            abi.encodeWithSignature(
                "withdraw(uint256,address,address)",
                amountIn,
                address(this),
                address(skyExecutor)
            ),
            abi.encode(amountIn)
        );

        uint256 amountOut = skyExecutor.swap(amountIn, withdrawData);
        assertEq(
            amountOut, amountIn, "Incorrect output amount for sUSDS withdrawal"
        );
    }

    function testConverterSwapReverse() public {
        uint256 amountIn = 100 * 10 ** 18; // 100 USDS

        bytes memory converterData = abi.encodePacked(
            USDS_ADDR, DAI_ADDR, DAI_USDS_CONVERTER_ADDRESS, address(this)
        );

        deal(USDS_ADDR, address(this), amountIn);
        IERC20(USDS_ADDR).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            DAI_USDS_CONVERTER_ADDRESS,
            abi.encodeWithSignature(
                "swapExactInput(address,address,uint256,address)",
                USDS_ADDR,
                DAI_ADDR,
                amountIn,
                address(this)
            ),
            abi.encode(amountIn)
        );

        uint256 amountOut = skyExecutor.swap(amountIn, converterData);
        assertEq(
            amountOut,
            amountIn,
            "Incorrect output amount for reverse converter swap"
        );
    }

    function testMkrSkyConverterToSky() public {
        uint256 amountIn = 1 * 10 ** 18; // 1 MKR
        uint256 expectedOut = 24000 * 10 ** 18; // 24,000 SKY

        bytes memory converterData = abi.encodePacked(
            MKR_ADDR, SKY_ADDR, MKR_SKY_CONVERTER_ADDRESS, address(this)
        );

        deal(MKR_ADDR, address(this), amountIn);
        IERC20(MKR_ADDR).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            MKR_SKY_CONVERTER_ADDRESS,
            abi.encodeWithSignature(
                "swapExactInput(address,address,uint256,address)",
                MKR_ADDR,
                SKY_ADDR,
                amountIn,
                address(this)
            ),
            abi.encode(expectedOut)
        );

        uint256 amountOut = skyExecutor.swap(amountIn, converterData);
        assertEq(
            amountOut,
            expectedOut,
            "Incorrect output amount for MKR to SKY conversion"
        );
    }

    function testMkrSkyConverterToMkr() public {
        uint256 amountIn = 24000 * 10 ** 18; // 24,000 SKY
        uint256 expectedOut = 1 * 10 ** 18; // 1 MKR

        bytes memory converterData = abi.encodePacked(
            SKY_ADDR, MKR_ADDR, MKR_SKY_CONVERTER_ADDRESS, address(this)
        );

        deal(SKY_ADDR, address(this), amountIn);
        IERC20(SKY_ADDR).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            MKR_SKY_CONVERTER_ADDRESS,
            abi.encodeWithSignature(
                "swapExactInput(address,address,uint256,address)",
                SKY_ADDR,
                MKR_ADDR,
                amountIn,
                address(this)
            ),
            abi.encode(expectedOut)
        );

        uint256 amountOut = skyExecutor.swap(amountIn, converterData);
        assertEq(
            amountOut,
            expectedOut,
            "Incorrect output amount for SKY to MKR conversion"
        );
    }

    function testPSMSwapReverse() public {
        uint256 amountIn = 100 * 10 ** 6; // 100 USDC (6 decimals)
        uint24 fee = 100; // 1% fee
        uint256 expectedOut =
            (amountIn * 10 ** 12) - ((amountIn * 10 ** 12 * fee) / 10000); // Convert to 18 decimals and subtract fee

        bytes memory psmData = abi.encodePacked(
            USDC_ADDR,
            DAI_ADDR,
            DAI_LITE_PSM_ADDRESS,
            address(this),
            bytes3(uint24(fee))
        );

        deal(USDC_ADDR, address(this), amountIn);
        IERC20(USDC_ADDR).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            DAI_LITE_PSM_ADDRESS,
            abi.encodeWithSignature(
                "swapWithFee(address,address,uint256,address,uint24)",
                USDC_ADDR,
                DAI_ADDR,
                amountIn,
                address(this),
                fee
            ),
            abi.encode(expectedOut)
        );

        uint256 amountOut = skyExecutor.swap(amountIn, psmData);
        assertEq(
            amountOut,
            expectedOut,
            "Incorrect output amount for USDC to DAI PSM swap"
        );
    }

    function testUSDSPSMWrapperToUSDC() public {
        uint256 amountIn = 100 * 10 ** 18; // 100 USDS (18 decimals)
        uint24 fee = 50; // 0.5% fee
        uint256 expectedOut =
            (amountIn / 10 ** 12) - (((amountIn / 10 ** 12) * fee) / 10000); // Convert to 6 decimals and subtract fee

        bytes memory psmData = abi.encodePacked(
            USDS_ADDR,
            USDC_ADDR,
            USDS_PSM_WRAPPER_ADDRESS,
            address(this),
            bytes3(uint24(fee))
        );

        deal(USDS_ADDR, address(this), amountIn);
        IERC20(USDS_ADDR).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            USDS_PSM_WRAPPER_ADDRESS,
            abi.encodeWithSignature(
                "swapWithFee(address,address,uint256,address,uint24)",
                USDS_ADDR,
                USDC_ADDR,
                amountIn,
                address(this),
                fee
            ),
            abi.encode(expectedOut)
        );

        uint256 amountOut = skyExecutor.swap(amountIn, psmData);
        assertEq(
            amountOut,
            expectedOut,
            "Incorrect output amount for USDS to USDC PSM swap"
        );
    }

    function testUSDSPSMWrapperToUSDS() public {
        uint256 amountIn = 100 * 10 ** 6; // 100 USDC (6 decimals)
        uint24 fee = 50; // 0.5% fee
        uint256 expectedOut =
            (amountIn * 10 ** 12) - ((amountIn * 10 ** 12 * fee) / 10000); // Convert to 18 decimals and subtract fee

        bytes memory psmData = abi.encodePacked(
            USDC_ADDR,
            USDS_ADDR,
            USDS_PSM_WRAPPER_ADDRESS,
            address(this),
            bytes3(uint24(fee))
        );

        deal(USDC_ADDR, address(this), amountIn);
        IERC20(USDC_ADDR).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            USDS_PSM_WRAPPER_ADDRESS,
            abi.encodeWithSignature(
                "swapWithFee(address,address,uint256,address,uint24)",
                USDC_ADDR,
                USDS_ADDR,
                amountIn,
                address(this),
                fee
            ),
            abi.encode(expectedOut)
        );

        uint256 amountOut = skyExecutor.swap(amountIn, psmData);
        assertEq(
            amountOut,
            expectedOut,
            "Incorrect output amount for USDC to USDS PSM swap"
        );
    }

    function testZeroAmountFail() public {
        uint256 amountIn = 0;
        bytes memory converterData = abi.encodePacked(
            DAI_ADDR, USDS_ADDR, DAI_USDS_CONVERTER_ADDRESS, address(this)
        );

        IERC20(DAI_ADDR).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            DAI_USDS_CONVERTER_ADDRESS,
            abi.encodeWithSignature(
                "swapExactInput(address,address,uint256,address)",
                DAI_ADDR,
                USDS_ADDR,
                amountIn,
                address(this)
            ),
            abi.encode(0) // Zero output, should trigger the error
        );

        vm.expectRevert(SkyExecutor__OperationFailed.selector);
        skyExecutor.swap(amountIn, converterData);
    }

    function testInvalidComponentType() public {
        uint256 amountIn = 100 * 10 ** 18;

        bytes memory invalidData =
            abi.encodePacked(DAI_ADDR, USDS_ADDR, ALICE, address(this));

        deal(DAI_ADDR, address(this), amountIn);
        IERC20(DAI_ADDR).approve(address(skyExecutor), amountIn);

        vm.mockCall(
            DAI_ADDR,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(this),
                address(skyExecutor),
                amountIn
            ),
            abi.encode(true)
        );

        vm.mockCall(
            DAI_ADDR,
            abi.encodeWithSignature("approve(address,uint256)", ALICE, amountIn),
            abi.encode(true)
        );

        vm.mockCall(
            ALICE,
            abi.encodeWithSignature(
                "swapExactInput(address,address,uint256,address)",
                DAI_ADDR,
                USDS_ADDR,
                amountIn,
                address(this)
            ),
            abi.encode(0)
        );

        vm.expectRevert(SkyExecutor__OperationFailed.selector);
        skyExecutor.swap(amountIn, invalidData);
    }
}
