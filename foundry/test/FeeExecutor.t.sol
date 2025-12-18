// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../src/executors/FeeExecutor.sol";
import "./TychoRouterTestSetup.sol";

contract FeeExecutorExposed is FeeExecutor {
    constructor(address _permit2) FeeExecutor(_permit2) {}

    function decodeData(bytes calldata data)
        external
        pure
        returns (uint16 feeBps, address feeReceiver, address token)
    {
        return _decodeData(data);
    }
}

contract FeeExecutorTest is Constants, TestUtils {
    FeeExecutorExposed feeExecutor;

    function setUp() public {
        feeExecutor = new FeeExecutorExposed(PERMIT2_ADDRESS);
    }

    function testDecodeData() public view {
        uint16 expectedFeeBps = 100; // 1%
        address expectedFeeReceiver = address(0x123);
        address expectedToken = DAI_ADDR;

        bytes memory data = abi.encodePacked(
            expectedFeeBps, expectedFeeReceiver, expectedToken
        );

        (uint16 feeBps, address feeReceiver, address token) =
            feeExecutor.decodeData(data);

        assertEq(feeBps, expectedFeeBps);
        assertEq(feeReceiver, expectedFeeReceiver);
        assertEq(token, expectedToken);
    }

    function testDecodeDataInvalidLength() public {
        bytes memory data = abi.encodePacked(uint16(100), address(0x123));

        vm.expectRevert(FeeExecutor__InvalidDataLength.selector);
        feeExecutor.decodeData(data);
    }

    function testSwapDeductsFee() public {
        uint256 amountIn = 1000 ether;
        uint16 feeBps = 100; // 1%
        address feeReceiver = address(0x456);
        address token = DAI_ADDR;

        bytes memory data = abi.encodePacked(feeBps, feeReceiver, token);

        uint256 amountOut = feeExecutor.swap(amountIn, data);

        // Should return 99% of input (1% fee)
        uint256 expectedAmountOut = 990 ether;
        assertEq(amountOut, expectedAmountOut);
    }

    function testSwapWithZeroFee() public {
        uint256 amountIn = 1000 ether;
        uint16 feeBps = 0; // 0% fee
        address feeReceiver = address(0x456);
        address token = DAI_ADDR;

        bytes memory data = abi.encodePacked(feeBps, feeReceiver, token);

        uint256 amountOut = feeExecutor.swap(amountIn, data);

        // Should return full amount
        assertEq(amountOut, amountIn);
    }

    function testSwapFeeTooHigh() public {
        uint256 amountIn = 1000 ether;
        uint16 feeBps = 5001; // 50.01% - above max
        address feeReceiver = address(0x456);
        address token = DAI_ADDR;

        bytes memory data = abi.encodePacked(feeBps, feeReceiver, token);

        vm.expectRevert(FeeExecutor__FeeTooHigh.selector);
        feeExecutor.swap(amountIn, data);
    }

    function testSwapMaxFee() public {
        uint256 amountIn = 1000 ether;
        uint16 feeBps = 5000; // 50% - at max
        address feeReceiver = address(0x456);
        address token = DAI_ADDR;

        bytes memory data = abi.encodePacked(feeBps, feeReceiver, token);

        uint256 amountOut = feeExecutor.swap(amountIn, data);

        // Should return 50% of input
        uint256 expectedAmountOut = 500 ether;
        assertEq(amountOut, expectedAmountOut);
    }

    function testExportContract() public {
        exportRuntimeBytecode(address(feeExecutor), "FeeExecutor");
    }
}
