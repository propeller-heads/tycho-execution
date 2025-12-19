// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../src/executors/FeeExecutor.sol";
import "./TychoRouterTestSetup.sol";

contract FeeExecutorExposed is FeeExecutor {
    constructor(address _permit2) FeeExecutor(_permit2) {}

    function decodeData(bytes calldata data)
        external
        pure
        returns (
            uint16 solutionFeeBps,
            address solutionFeeReceiver,
            uint16 routerFeeBps,
            address routerFeeReceiver,
            address token
        )
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
        uint16 expectedSolutionFeeBps = 100; // 1%
        address expectedSolutionFeeReceiver = address(0x123);
        uint16 expectedRouterFeeBps = 50; // 0.5%
        address expectedRouterFeeReceiver = address(0x456);
        address expectedToken = DAI_ADDR;

        bytes memory data = abi.encodePacked(
            expectedSolutionFeeBps,
            expectedSolutionFeeReceiver,
            expectedRouterFeeBps,
            expectedRouterFeeReceiver,
            expectedToken
        );

        (
            uint16 solutionFeeBps,
            address solutionFeeReceiver,
            uint16 routerFeeBps,
            address routerFeeReceiver,
            address token
        ) = feeExecutor.decodeData(data);

        assertEq(solutionFeeBps, expectedSolutionFeeBps);
        assertEq(solutionFeeReceiver, expectedSolutionFeeReceiver);
        assertEq(routerFeeBps, expectedRouterFeeBps);
        assertEq(routerFeeReceiver, expectedRouterFeeReceiver);
        assertEq(token, expectedToken);
    }

    function testDecodeDataInvalidLength() public {
        bytes memory data = abi.encodePacked(uint16(100), address(0x123));

        vm.expectRevert(FeeExecutor__InvalidDataLength.selector);
        feeExecutor.decodeData(data);
    }

    function testSwapDeductsFee() public {
        uint256 amountIn = 1000 ether;
        uint16 solutionFeeBps = 100; // 1%
        address solutionFeeReceiver = address(0x456);
        uint16 routerFeeBps = 0; // no router fee
        address routerFeeReceiver = address(0);
        address token = DAI_ADDR;

        bytes memory data = abi.encodePacked(
            solutionFeeBps,
            solutionFeeReceiver,
            routerFeeBps,
            routerFeeReceiver,
            token
        );

        uint256 amountOut = feeExecutor.take_fee(amountIn, data);

        // Should return 99% of input (1% fee)
        uint256 expectedAmountOut = 990 ether;
        assertEq(amountOut, expectedAmountOut);
    }

    function testSwapWithZeroFee() public {
        uint256 amountIn = 1000 ether;
        uint16 solutionFeeBps = 0; // 0% fee
        address solutionFeeReceiver = address(0x456);
        uint16 routerFeeBps = 0; // 0% fee
        address routerFeeReceiver = address(0x789);
        address token = DAI_ADDR;

        bytes memory data = abi.encodePacked(
            solutionFeeBps,
            solutionFeeReceiver,
            routerFeeBps,
            routerFeeReceiver,
            token
        );

        uint256 amountOut = feeExecutor.take_fee(amountIn, data);

        // Should return full amount
        assertEq(amountOut, amountIn);
    }

    function testSwapFeeTooHigh() public {
        uint256 amountIn = 1000 ether;
        uint16 solutionFeeBps = 5001; // 50.01% - above max
        address solutionFeeReceiver = address(0x456);
        uint16 routerFeeBps = 0;
        address routerFeeReceiver = address(0);
        address token = DAI_ADDR;

        bytes memory data = abi.encodePacked(
            solutionFeeBps,
            solutionFeeReceiver,
            routerFeeBps,
            routerFeeReceiver,
            token
        );

        vm.expectRevert(FeeExecutor__FeeTooHigh.selector);
        feeExecutor.take_fee(amountIn, data);
    }

    function testSwapMaxFee() public {
        uint256 amountIn = 1000 ether;
        uint16 solutionFeeBps = 5000; // 50% - at max
        address solutionFeeReceiver = address(0x456);
        uint16 routerFeeBps = 0;
        address routerFeeReceiver = address(0);
        address token = DAI_ADDR;

        bytes memory data = abi.encodePacked(
            solutionFeeBps,
            solutionFeeReceiver,
            routerFeeBps,
            routerFeeReceiver,
            token
        );

        uint256 amountOut = feeExecutor.take_fee(amountIn, data);

        // Should return 50% of input
        uint256 expectedAmountOut = 500 ether;
        assertEq(amountOut, expectedAmountOut);
    }

    function testExportContract() public {
        exportRuntimeBytecode(address(feeExecutor), "FeeExecutor");
    }
}
