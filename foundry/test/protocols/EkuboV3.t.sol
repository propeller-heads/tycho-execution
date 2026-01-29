// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../TestUtils.sol";
import "../TychoRouterTestSetup.sol";
import "@src/executors/EkuboV3Executor.sol";
import {ILocker} from "@ekubo-v3/interfaces/IFlashAccountant.sol";
import {Constants} from "../Constants.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {console} from "forge-std/Test.sol";

// Handles callbacks directly and receives the native token directly
contract EkuboV3ExecutorStandalone is EkuboV3Executor, ILocker {
    constructor(address _permit2) EkuboV3Executor(_permit2) {}

    function locked_6416899205(uint256 id) external {
        bytes memory res = handleCallback(msg.data);
        assembly ("memory-safe") {
            return(add(res, 32), mload(res))
        }
    }

    // To receive withdrawals from Core
    receive() external payable {}
}

contract EkuboV3ExecutorTest is Constants, TestUtils {
    EkuboV3ExecutorStandalone immutable executor =
        new EkuboV3ExecutorStandalone(PERMIT2_ADDRESS);

    IERC20 USDC = IERC20(USDC_ADDR);
    IERC20 USDT = IERC20(USDT_ADDR);

    bytes32 constant ORACLE_CONFIG =
        0x517E506700271AEa091b02f42756F5E174Af5230000000000000000000000000;

    constructor() {
        vm.makePersistent(address(executor));
    }

    modifier setUpFork(uint256 blockNumber) {
        vm.createSelectFork(vm.rpcUrl("mainnet"), blockNumber);
        // Forks always use the default hardfork https://github.com/foundry-rs/foundry/issues/13040
        vm.setEvmVersion("osaka");

        _;
    }

    function testSingleSwapEth() public setUpFork(24218590) {
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
        assertEq(address(executor).balance, ethBalanceBeforeExecutor - amountIn);

        assertEq(
            USDC.balanceOf(CORE_ADDRESS), usdcBalanceBeforeCore - amountOut
        );
        assertEq(
            USDC.balanceOf(address(executor)),
            usdcBalanceBeforeExecutor + amountOut
        );
    }

    function testSingleSwapERC20() public setUpFork(24218590) {
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

        assertEq(USDC.balanceOf(CORE_ADDRESS), usdcBalanceBeforeCore + amountIn);
        assertEq(
            USDC.balanceOf(address(executor)),
            usdcBalanceBeforeExecutor - amountIn
        );

        assertEq(CORE_ADDRESS.balance, ethBalanceBeforeCore - amountOut);
        assertEq(
            address(executor).balance, ethBalanceBeforeExecutor + amountOut
        );
    }

    function testMevCapture() public setUpFork(24198199) {
        uint256 amountIn = 1_000;

        deal(USDC_ADDR, address(executor), amountIn);

        uint256 usdcBalanceBeforeCore = USDC.balanceOf(CORE_ADDRESS);
        uint256 usdcBalanceBeforeExecutor = USDC.balanceOf(address(executor));

        uint256 usdtBalanceBeforeCore = USDT.balanceOf(CORE_ADDRESS);
        uint256 usdtBalanceBeforeExecutor = USDT.balanceOf(address(executor));

        bytes memory data = abi.encodePacked(
            uint8(RestrictTransferFrom.TransferType.Transfer), // transferNeeded (transfer from executor to core)
            address(executor), // receiver
            USDC_ADDR, // tokenIn
            USDT_ADDR, // tokenOut
            bytes32(
                0x5555ff9ff2757500bf4ee020dcfd0210cffa41be000053e2d6238da480000032
            ) // config (0.0005% fee and 0.005% tick spacing)
        );

        uint256 gasBefore = gasleft();
        uint256 amountOut = executor.swap(amountIn, data);
        console.log(gasBefore - gasleft());

        console.log(amountOut);

        assertEq(USDC.balanceOf(CORE_ADDRESS), usdcBalanceBeforeCore + amountIn);
        assertEq(
            USDC.balanceOf(address(executor)),
            usdcBalanceBeforeExecutor - amountIn
        );

        assertEq(
            USDT.balanceOf(CORE_ADDRESS), usdtBalanceBeforeCore - amountOut
        );
        assertEq(
            USDT.balanceOf(address(executor)),
            usdtBalanceBeforeExecutor + amountOut
        );
    }

    // Data is generated by test case in swap_encoder::tests::ekubo_v3::test_encode_swap_multi
    function testMultiHopSwapIntegration() public setUpFork(24218590) {
        uint256 amountIn = 1 ether;
        deal(address(executor), amountIn);

        uint256 ethBalanceBeforeCore = CORE_ADDRESS.balance;
        uint256 ethBalanceBeforeExecutor = address(executor).balance;

        uint256 usdtBalanceBeforeCore = USDT.balanceOf(CORE_ADDRESS);
        uint256 usdtBalanceBeforeAlice = USDT.balanceOf(ALICE);

        uint256 gasBefore = gasleft();
        uint256 amountOut = executor.swap(
            amountIn, loadCallDataFromFile("test_ekubo_v3_encode_swap_multi")
        );
        console.log(gasBefore - gasleft());

        console.log(amountOut);

        assertEq(CORE_ADDRESS.balance, ethBalanceBeforeCore + amountIn);
        assertEq(address(executor).balance, ethBalanceBeforeExecutor - amountIn);

        assertEq(
            USDT.balanceOf(CORE_ADDRESS), usdtBalanceBeforeCore - amountOut
        );
        assertEq(USDT.balanceOf(ALICE), usdtBalanceBeforeAlice + amountOut);
    }
}

contract TychoRouterForEkuboV3Test is TychoRouterTestSetup {
    function getForkBlock() public view virtual override returns (uint256) {
        return 24218590;
    }

    function setUp() public virtual override {
        super.setUp();

        // Remove delegations
        vm.etch(ALICE, "");
    }

    function testSingleEkuboIntegration() public {
        deal(ALICE, 1 ether);
        uint256 balanceBefore = IERC20(USDC_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        (bool success,) = tychoRouterAddr.call{value: 1 ether}(
            loadCallDataFromFile("test_single_encoding_strategy_ekubo_v3")
        );

        uint256 balanceAfter = IERC20(USDC_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertGe(balanceAfter - balanceBefore, 26173932);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }

    function testTwoEkuboIntegration() public {
        // Test multi-hop Ekubo swaps (grouped swap)
        //
        // USDT ──(EKUBO)──> USDC ──(EKUBO)──> ETH
        //
        deal(USDT_ADDR, ALICE, 10_000_000_000);
        uint256 balanceBefore = ALICE.balance;

        // Approve permit2
        vm.startPrank(ALICE);
        SafeTransferLib.safeApprove(
            USDT_ADDR, tychoRouterAddr, type(uint256).max
        );

        (bool success,) = tychoRouterAddr.call(
            loadCallDataFromFile("test_single_ekubo_v3_grouped_swap")
        );
        assertTrue(success, "call failed");

        assertEq(ALICE.balance - balanceBefore, 2500939754680596105);
        assertEq(IERC20(USDT_ADDR).balanceOf(ALICE), 0);
    }
}
