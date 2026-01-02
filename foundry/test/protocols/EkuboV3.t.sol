// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../TestUtils.sol";
import "../TychoRouterTestSetup.sol";
import "@src/executors/EkuboV3Executor.sol";
import {Constants} from "../Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/Test.sol";

// Handles callbacks directly and receives the native token directly
contract EkuboV3ExecutorStandalone is EkuboV3Executor, ILocker {
    constructor(
        ICore _core,
        address _mevCapture,
        address _permit2
    ) EkuboV3Executor(_core, _mevCapture, _permit2) {}

    function locked_6416899205(uint256 id) external {
        _handleCallback(msg.data);
    }

    // To receive withdrawals from Core
    receive() external payable {}
}

contract EkuboV3ExecutorTest is Constants, TestUtils {
    address constant EXECUTOR_ADDRESS =
        0x0000000000000000000000000000000000000000; // Same address as in swap_encoder.rs tests // TODO
    EkuboV3Executor executor;

    IERC20 USDC = IERC20(USDC_ADDR);
    IERC20 USDT = IERC20(USDT_ADDR);

    address constant CORE_ADDRESS = 0x0000000000000000000000000000000000000000; // TODO
    address constant MEV_RESIST_ADDRESS =
        0x0000000000000000000000000000000000000000; // TODO

    bytes32 constant ORACLE_CONFIG =
        0x0000000000000000000000000000000000000000000000000000000000000000; // TODO

    // 0.01% fee and 0.02% tick spacing
    bytes32 constant MEV_RESIST_POOL_CONFIG =
        0x0000000000000000000000000000000000000000000000000000000000000000; // TODO

    modifier setUpFork(uint256 blockNumber) {
        vm.createSelectFork(vm.rpcUrl("mainnet"), blockNumber);

        deployCodeTo(
            "EkuboV3.t.sol:EkuboV3ExecutorStandalone",
            abi.encode(CORE_ADDRESS, MEV_RESIST_ADDRESS, PERMIT2_ADDRESS),
            EXECUTOR_ADDRESS
        );
        executor = EkuboV3Executor(payable(EXECUTOR_ADDRESS));
        _;
    }

    // TODO
    function testSingleSwapEth() public setUpFork(0) {
        uint256 amountIn = 1 ether;

        deal(address(executor), amountIn);

        uint256 ethBalanceBeforeCore = CORE_ADDRESS.balance;
        uint256 ethBalanceBeforeExecutor = address(executor).balance;

        uint256 usdcBalanceBeforeCore = USDC.balanceOf(CORE_ADDRESS);
        uint256 usdcBalanceBeforeExecutor = USDC.balanceOf(address(executor));

        bytes memory data = abi.encodePacked(
            uint8(RestrictTransferFrom.TransferType.Transfer), // transfer type (transfer from executor to core)
            address(executor), // receiver
            NATIVE_TOKEN_ADDRESS, // tokenIn
            USDC_ADDR, // tokenOut
            ORACLE_CONFIG // poolConfig
        );

        uint256 gasBefore = gasleft();
        uint256 amountOut = executor.swap(amountIn, data);
        console.log(gasBefore - gasleft());

        console.log(amountOut);

        assertEq(CORE_ADDRESS.balance, ethBalanceBeforeCore + amountIn);
        assertEq(
            address(executor).balance,
            ethBalanceBeforeExecutor - amountIn
        );

        assertEq(
            USDC.balanceOf(CORE_ADDRESS),
            usdcBalanceBeforeCore - amountOut
        );
        assertEq(
            USDC.balanceOf(address(executor)),
            usdcBalanceBeforeExecutor + amountOut
        );
    }

    // TODO
    function testSingleSwapERC20() public setUpFork(0) {
        uint256 amountIn = 1_000_000_000;

        deal(USDC_ADDR, address(executor), amountIn);

        uint256 usdcBalanceBeforeCore = USDC.balanceOf(CORE_ADDRESS);
        uint256 usdcBalanceBeforeExecutor = USDC.balanceOf(address(executor));

        uint256 ethBalanceBeforeCore = CORE_ADDRESS.balance;
        uint256 ethBalanceBeforeExecutor = address(executor).balance;

        bytes memory data = abi.encodePacked(
            uint8(RestrictTransferFrom.TransferType.Transfer), // transferNeeded (transfer from executor to core)
            address(executor), // receiver
            USDC_ADDR, // tokenIn
            NATIVE_TOKEN_ADDRESS, // tokenOut
            ORACLE_CONFIG // config
        );

        uint256 gasBefore = gasleft();
        uint256 amountOut = executor.swap(amountIn, data);
        console.log(gasBefore - gasleft());

        console.log(amountOut);

        assertEq(
            USDC.balanceOf(CORE_ADDRESS),
            usdcBalanceBeforeCore + amountIn
        );
        assertEq(
            USDC.balanceOf(address(executor)),
            usdcBalanceBeforeExecutor - amountIn
        );

        assertEq(CORE_ADDRESS.balance, ethBalanceBeforeCore - amountOut);
        assertEq(
            address(executor).balance,
            ethBalanceBeforeExecutor + amountOut
        );
    }

    // TODO
    function testMevResist() public setUpFork(0) {
        uint256 amountIn = 1_000_000_000;

        deal(USDC_ADDR, address(executor), amountIn);

        uint256 usdcBalanceBeforeCore = USDC.balanceOf(CORE_ADDRESS);
        uint256 usdcBalanceBeforeExecutor = USDC.balanceOf(address(executor));

        uint256 ethBalanceBeforeCore = CORE_ADDRESS.balance;
        uint256 ethBalanceBeforeExecutor = address(executor).balance;

        bytes memory data = abi.encodePacked(
            uint8(RestrictTransferFrom.TransferType.Transfer), // transferNeeded (transfer from executor to core)
            address(executor), // receiver
            USDC_ADDR, // tokenIn
            NATIVE_TOKEN_ADDRESS, // tokenOut
            MEV_RESIST_POOL_CONFIG // config
        );

        uint256 gasBefore = gasleft();
        uint256 amountOut = executor.swap(amountIn, data);
        console.log(gasBefore - gasleft());

        console.log(amountOut);

        assertEq(
            USDC.balanceOf(CORE_ADDRESS),
            usdcBalanceBeforeCore + amountIn
        );
        assertEq(
            USDC.balanceOf(address(executor)),
            usdcBalanceBeforeExecutor - amountIn
        );

        assertEq(CORE_ADDRESS.balance, ethBalanceBeforeCore - amountOut);
        assertEq(
            address(executor).balance,
            ethBalanceBeforeExecutor + amountOut
        );
    }

    // Data is generated by test case in swap_encoder::tests::ekubo_v3::test_encode_swap_multi
    // TODO
    function testMultiHopSwapIntegration() public setUpFork(0) {
        uint256 amountIn = 1 ether;

        deal(address(executor), amountIn);

        uint256 ethBalanceBeforeCore = CORE_ADDRESS.balance;
        uint256 ethBalanceBeforeExecutor = address(executor).balance;

        uint256 usdtBalanceBeforeCore = USDT.balanceOf(CORE_ADDRESS);
        uint256 usdtBalanceBeforeExecutor = USDT.balanceOf(address(executor));

        uint256 gasBefore = gasleft();
        uint256 amountOut = executor.swap(
            amountIn,
            loadCallDataFromFile("test_ekubo_v3_encode_swap_multi")
        );
        console.log(gasBefore - gasleft());

        console.log(amountOut);

        assertEq(CORE_ADDRESS.balance, ethBalanceBeforeCore + amountIn);
        assertEq(
            address(executor).balance,
            ethBalanceBeforeExecutor - amountIn
        );

        assertEq(
            USDT.balanceOf(CORE_ADDRESS),
            usdtBalanceBeforeCore - amountOut
        );
        assertEq(
            USDT.balanceOf(address(executor)),
            usdtBalanceBeforeExecutor + amountOut
        );
    }
}

contract TychoRouterForEkuboV3Test is TychoRouterTestSetup {
    function testSingleEkuboIntegration() public {
        deal(ALICE, 1 ether);
        uint256 balanceBefore = IERC20(USDC_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        bytes memory callData = loadCallDataFromFile(
            "test_single_encoding_strategy_ekubo_v3"
        );
        (bool success, ) = tychoRouterAddr.call{value: 1 ether}(callData);

        uint256 balanceAfter = IERC20(USDC_ADDR).balanceOf(ALICE);

        assertTrue(success, "call Failed");
        assertGe(balanceAfter - balanceBefore, 26173932);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }
}
