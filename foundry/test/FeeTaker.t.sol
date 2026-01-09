// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../src/executors/FeeTaker.sol";
import "./TychoRouterTestSetup.sol";

contract FeeTakerExposed is FeeTaker {
    constructor(address _permit2) FeeTaker(_permit2) {}

    function decodeData(bytes calldata data)
        external
        pure
        returns (
            uint16 solutionFeeBps,
            address solutionFeeReceiver,
            uint16 routerFeeOnOutputBps,
            uint16 routerFeeOnSolverFeeBps,
            address routerFeeReceiver,
            address token
        )
    {
        return _decodeData(data);
    }
}

contract FeeTakerTest is Constants, TestUtils {
    FeeTakerExposed feeTaker;

    function setUp() public {
        feeTaker = new FeeTakerExposed(PERMIT2_ADDRESS);
    }

    function testDecodeData() public view {
        uint16 expectedSolutionFeeBps = 100; // 1%
        address expectedSolutionFeeReceiver = address(0x123);
        uint16 expectedRouterFeeOnOutputBps = 50; // 0.5%
        uint16 expectedRouterFeeOnSolverFeeBps = 25; // 0.25%
        address expectedRouterFeeReceiver = address(0x456);
        address expectedToken = DAI_ADDR;

        bytes memory data = abi.encodePacked(
            expectedSolutionFeeBps,
            expectedSolutionFeeReceiver,
            expectedRouterFeeOnOutputBps,
            expectedRouterFeeOnSolverFeeBps,
            expectedRouterFeeReceiver,
            expectedToken
        );

        (
            uint16 solutionFeeBps,
            address solutionFeeReceiver,
            uint16 routerFeeOnOutputBps,
            uint16 routerFeeOnSolverFeeBps,
            address routerFeeReceiver,
            address token
        ) = feeTaker.decodeData(data);

        assertEq(solutionFeeBps, expectedSolutionFeeBps);
        assertEq(solutionFeeReceiver, expectedSolutionFeeReceiver);
        assertEq(routerFeeOnOutputBps, expectedRouterFeeOnOutputBps);
        assertEq(routerFeeOnSolverFeeBps, expectedRouterFeeOnSolverFeeBps);
        assertEq(routerFeeReceiver, expectedRouterFeeReceiver);
        assertEq(token, expectedToken);
    }

    function testDecodeDataInvalidLength() public {
        bytes memory data = abi.encodePacked(uint16(100), address(0x123));

        vm.expectRevert(FeeTaker__InvalidDataLength.selector);
        feeTaker.decodeData(data);
    }

    function testSwapDeductsFee() public {
        uint256 amountIn = 1000 ether;
        uint16 solutionFeeBps = 100; // 1%
        address solutionFeeReceiver = address(0x456);
        uint16 routerFeeOnOutputBps = 0; // no router fee on output
        uint16 routerFeeOnSolverFeeBps = 0; // no router fee on solver fee
        address routerFeeReceiver = address(0);
        address token = DAI_ADDR;
        address receiver = address(0x789);
        bool unwrapEth = true; // skip transfer in test

        bytes memory data = abi.encodePacked(
            solutionFeeBps,
            solutionFeeReceiver,
            routerFeeOnOutputBps,
            routerFeeOnSolverFeeBps,
            routerFeeReceiver,
            token,
            receiver,
            unwrapEth
        );

        uint256 amountOut = feeTaker.take_fee(amountIn, data);

        // Should return 99% of input (1% fee)
        uint256 expectedAmountOut = 990 ether;
        assertEq(amountOut, expectedAmountOut);
    }

    function testSwapWithZeroFee() public {
        uint256 amountIn = 1000 ether;
        uint16 solutionFeeBps = 0; // 0% fee
        address solutionFeeReceiver = address(0x456);
        uint16 routerFeeOnOutputBps = 0; // 0% fee
        uint16 routerFeeOnSolverFeeBps = 0; // 0% fee
        address routerFeeReceiver = address(0x789);
        address token = DAI_ADDR;
        address receiver = address(0xabc);
        bool unwrapEth = true; // skip transfer in test

        bytes memory data = abi.encodePacked(
            solutionFeeBps,
            solutionFeeReceiver,
            routerFeeOnOutputBps,
            routerFeeOnSolverFeeBps,
            routerFeeReceiver,
            token,
            receiver,
            unwrapEth
        );

        uint256 amountOut = feeTaker.take_fee(amountIn, data);

        // Should return full amount
        assertEq(amountOut, amountIn);
    }

    function testSwapFeeTooHigh() public {
        uint256 amountIn = 1000 ether;
        uint16 solutionFeeBps = 5001; // 50.01% - above max
        address solutionFeeReceiver = address(0x456);
        uint16 routerFeeOnOutputBps = 0;
        uint16 routerFeeOnSolverFeeBps = 0;
        address routerFeeReceiver = address(0);
        address token = DAI_ADDR;
        address receiver = address(0xabc);
        bool unwrapEth = true; // skip transfer in test

        bytes memory data = abi.encodePacked(
            solutionFeeBps,
            solutionFeeReceiver,
            routerFeeOnOutputBps,
            routerFeeOnSolverFeeBps,
            routerFeeReceiver,
            token,
            receiver,
            unwrapEth
        );

        vm.expectRevert(FeeTaker__FeeTooHigh.selector);
        feeTaker.take_fee(amountIn, data);
    }

    function testSwapMaxFee() public {
        uint256 amountIn = 1000 ether;
        uint16 solutionFeeBps = 5000; // 50% - at max
        address solutionFeeReceiver = address(0x456);
        uint16 routerFeeOnOutputBps = 0;
        uint16 routerFeeOnSolverFeeBps = 0;
        address routerFeeReceiver = address(0);
        address token = DAI_ADDR;
        address receiver = address(0xabc);
        bool unwrapEth = true; // skip transfer in test

        bytes memory data = abi.encodePacked(
            solutionFeeBps,
            solutionFeeReceiver,
            routerFeeOnOutputBps,
            routerFeeOnSolverFeeBps,
            routerFeeReceiver,
            token,
            receiver,
            unwrapEth
        );

        uint256 amountOut = feeTaker.take_fee(amountIn, data);

        // Should return 50% of input
        uint256 expectedAmountOut = 500 ether;
        assertEq(amountOut, expectedAmountOut);
    }

    function testRouterFeeOnSolverFee() public {
        uint256 amountIn = 1000 ether;
        uint16 solutionFeeBps = 1000; // 10%
        address solutionFeeReceiver = address(0x456);
        uint16 routerFeeOnOutputBps = 0; // no router fee on output
        uint16 routerFeeOnSolverFeeBps = 1000; // 10% of the solver fee
        address routerFeeReceiver = address(0x789);
        address token = DAI_ADDR;
        address receiver = address(0xabc);
        bool unwrapEth = true; // skip transfer in test

        bytes memory data = abi.encodePacked(
            solutionFeeBps,
            solutionFeeReceiver,
            routerFeeOnOutputBps,
            routerFeeOnSolverFeeBps,
            routerFeeReceiver,
            token,
            receiver,
            unwrapEth
        );

        uint256 amountOut = feeTaker.take_fee(amountIn, data);

        // Solution fee: 10% of 1000 = 100 ether
        // Router fee on solver fee: 10% of 100 = 10 ether
        // Expected output: 1000 - 100 - 10 = 890 ether
        uint256 expectedAmountOut = 890 ether;
        assertEq(amountOut, expectedAmountOut);
    }

    function testBothRouterFees() public {
        uint256 amountIn = 1000 ether;
        uint16 solutionFeeBps = 1000; // 10%
        address solutionFeeReceiver = address(0x456);
        uint16 routerFeeOnOutputBps = 500; // 5% of remaining output
        uint16 routerFeeOnSolverFeeBps = 500; // 5% of solver fee
        address routerFeeReceiver = address(0x789);
        address token = DAI_ADDR;
        address receiver = address(0xabc);
        bool unwrapEth = true; // skip transfer in test

        bytes memory data = abi.encodePacked(
            solutionFeeBps,
            solutionFeeReceiver,
            routerFeeOnOutputBps,
            routerFeeOnSolverFeeBps,
            routerFeeReceiver,
            token,
            receiver,
            unwrapEth
        );

        uint256 amountOut = feeTaker.take_fee(amountIn, data);

        // Solution fee: 10% of 1000 = 100 ether
        // Remaining after solution fee: 900 ether
        // Router fee on output: 5% of 900 = 45 ether
        // Remaining: 855 ether
        // Router fee on solver fee: 5% of 100 = 5 ether
        // Final output: 855 - 5 = 850 ether
        uint256 expectedAmountOut = 850 ether;
        assertEq(amountOut, expectedAmountOut);
    }

    function testRouterFeeOnSolverFeeBpsTooHigh() public {
        uint256 amountIn = 1000 ether;
        uint16 solutionFeeBps = 100; // 1%
        address solutionFeeReceiver = address(0x456);
        uint16 routerFeeOnOutputBps = 0;
        uint16 routerFeeOnSolverFeeBps = 5001; // 50.01% - above max
        address routerFeeReceiver = address(0x789);
        address token = DAI_ADDR;
        address receiver = address(0xabc);
        bool unwrapEth = true; // skip transfer in test

        bytes memory data = abi.encodePacked(
            solutionFeeBps,
            solutionFeeReceiver,
            routerFeeOnOutputBps,
            routerFeeOnSolverFeeBps,
            routerFeeReceiver,
            token,
            receiver,
            unwrapEth
        );

        vm.expectRevert(FeeTaker__FeeTooHigh.selector);
        feeTaker.take_fee(amountIn, data);
    }

    function testExportContract() public {
        exportRuntimeBytecode(address(feeTaker), "FeeTaker");
    }
}
