// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../../src/executors/UniswapV4Executor.sol";
import "../TestUtils.sol";
import "../TychoRouterTestSetup.sol";
import "./UniswapV4Utils.sol";
import "@src/executors/UniswapV4Executor.sol";
import {Constants} from "../Constants.sol";
import {SafeCallback} from "@uniswap/v4-periphery/src/base/SafeCallback.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";

contract UniswapV4ExecutorExposed is UniswapV4Executor {
    constructor(IPoolManager _poolManager, address _permit2)
        UniswapV4Executor(_poolManager, _permit2)
    {}

    function decodeData(bytes calldata data)
        external
        pure
        returns (
            address tokenIn,
            address tokenOut,
            bool zeroForOne,
            RestrictTransferFrom.TransferType transferType,
            address receiver,
            UniswapV4Pool[] memory pools
        )
    {
        return _decodeData(data);
    }
}

contract UniswapV4ExecutorTest is Constants, TestUtils {
    using SafeERC20 for IERC20;

    UniswapV4ExecutorExposed uniswapV4Exposed;
    IERC20 USDE = IERC20(USDE_ADDR);
    IERC20 USDT = IERC20(USDT_ADDR);
    address poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    function setUp() public {
        uint256 forkBlock = 21817316;
        vm.createSelectFork(vm.rpcUrl("mainnet"), forkBlock);
        uniswapV4Exposed = new UniswapV4ExecutorExposed(
            IPoolManager(poolManager), PERMIT2_ADDRESS
        );
    }

    function testDecodeParams() public view {
        bool zeroForOne = true;
        uint24 pool1Fee = 500;
        int24 tickSpacing1 = 60;
        uint24 pool2Fee = 1000;
        int24 tickSpacing2 = -10;

        UniswapV4Executor.UniswapV4Pool[] memory pools =
            new UniswapV4Executor.UniswapV4Pool[](2);
        pools[0] = UniswapV4Executor.UniswapV4Pool({
            intermediaryToken: USDT_ADDR,
            fee: pool1Fee,
            tickSpacing: tickSpacing1
        });
        pools[1] = UniswapV4Executor.UniswapV4Pool({
            intermediaryToken: USDE_ADDR,
            fee: pool2Fee,
            tickSpacing: tickSpacing2
        });

        bytes memory data = UniswapV4Utils.encodeExactInput(
            USDE_ADDR,
            USDT_ADDR,
            zeroForOne,
            RestrictTransferFrom.TransferType.Transfer,
            ALICE,
            pools
        );

        (
            address tokenIn,
            address tokenOut,
            bool zeroForOneDecoded,
            RestrictTransferFrom.TransferType transferType,
            address receiver,
            UniswapV4Executor.UniswapV4Pool[] memory decodedPools
        ) = uniswapV4Exposed.decodeData(data);

        assertEq(tokenIn, USDE_ADDR);
        assertEq(tokenOut, USDT_ADDR);
        assertEq(zeroForOneDecoded, zeroForOne);
        assertEq(
            uint8(transferType),
            uint8(RestrictTransferFrom.TransferType.Transfer)
        );
        assertEq(receiver, ALICE);
        assertEq(decodedPools.length, 2);
        assertEq(decodedPools[0].intermediaryToken, USDT_ADDR);
        assertEq(decodedPools[0].fee, pool1Fee);
        assertEq(decodedPools[0].tickSpacing, tickSpacing1);
        assertEq(decodedPools[1].intermediaryToken, USDE_ADDR);
        assertEq(decodedPools[1].fee, pool2Fee);
        assertEq(decodedPools[1].tickSpacing, tickSpacing2);
    }

    function testSingleSwap() public {
        uint256 amountIn = 100 ether;
        deal(USDE_ADDR, address(uniswapV4Exposed), amountIn);
        uint256 usdeBalanceBeforePool = USDE.balanceOf(poolManager);
        uint256 usdeBalanceBeforeSwapExecutor =
            USDE.balanceOf(address(uniswapV4Exposed));

        UniswapV4Executor.UniswapV4Pool[] memory pools =
            new UniswapV4Executor.UniswapV4Pool[](1);
        pools[0] = UniswapV4Executor.UniswapV4Pool({
            intermediaryToken: USDT_ADDR,
            fee: uint24(100),
            tickSpacing: int24(1)
        });

        bytes memory data = UniswapV4Utils.encodeExactInput(
            USDE_ADDR,
            USDT_ADDR,
            true,
            RestrictTransferFrom.TransferType.Transfer,
            ALICE,
            pools
        );

        uint256 amountOut = uniswapV4Exposed.swap(amountIn, data);
        assertEq(USDE.balanceOf(poolManager), usdeBalanceBeforePool + amountIn);
        assertEq(
            USDE.balanceOf(address(uniswapV4Exposed)),
            usdeBalanceBeforeSwapExecutor - amountIn
        );
        assertTrue(USDT.balanceOf(ALICE) == amountOut);
    }

    function testSingleSwapIntegration() public {
        // USDE -> USDT
        bytes memory protocolData =
            loadCallDataFromFile("test_encode_uniswap_v4_simple_swap");
        uint256 amountIn = 100 ether;
        deal(USDE_ADDR, address(uniswapV4Exposed), amountIn);
        uint256 usdeBalanceBeforePool = USDE.balanceOf(poolManager);
        uint256 usdeBalanceBeforeSwapExecutor =
            USDE.balanceOf(address(uniswapV4Exposed));

        uint256 amountOut = uniswapV4Exposed.swap(amountIn, protocolData);
        assertEq(USDE.balanceOf(poolManager), usdeBalanceBeforePool + amountIn);
        assertEq(
            USDE.balanceOf(ALICE), usdeBalanceBeforeSwapExecutor - amountIn
        );
        assertTrue(USDT.balanceOf(ALICE) == amountOut);
    }

    function testMultipleSwap() public {
        // USDE -> USDT -> WBTC
        uint256 amountIn = 100 ether;
        deal(USDE_ADDR, address(uniswapV4Exposed), amountIn);
        uint256 usdeBalanceBeforePool = USDE.balanceOf(poolManager);
        uint256 usdeBalanceBeforeSwapExecutor =
            USDE.balanceOf(address(uniswapV4Exposed));

        UniswapV4Executor.UniswapV4Pool[] memory pools =
            new UniswapV4Executor.UniswapV4Pool[](2);
        pools[0] = UniswapV4Executor.UniswapV4Pool({
            intermediaryToken: USDT_ADDR,
            fee: uint24(100),
            tickSpacing: int24(1)
        });
        pools[1] = UniswapV4Executor.UniswapV4Pool({
            intermediaryToken: WBTC_ADDR,
            fee: uint24(3000),
            tickSpacing: int24(60)
        });

        bytes memory data = UniswapV4Utils.encodeExactInput(
            USDE_ADDR,
            WBTC_ADDR,
            true,
            RestrictTransferFrom.TransferType.Transfer,
            ALICE,
            pools
        );

        uint256 amountOut = uniswapV4Exposed.swap(amountIn, data);
        assertEq(USDE.balanceOf(poolManager), usdeBalanceBeforePool + amountIn);
        assertEq(
            USDE.balanceOf(address(uniswapV4Exposed)),
            usdeBalanceBeforeSwapExecutor - amountIn
        );
        assertTrue(IERC20(WBTC_ADDR).balanceOf(ALICE) == amountOut);
    }

    function testMultipleSwapIntegration() public {
        // USDE -> USDT -> WBTC
        bytes memory protocolData =
            loadCallDataFromFile("test_encode_uniswap_v4_sequential_swap");

        uint256 amountIn = 100 ether;
        deal(USDE_ADDR, address(uniswapV4Exposed), amountIn);
        uint256 usdeBalanceBeforePool = USDE.balanceOf(poolManager);
        uint256 usdeBalanceBeforeSwapExecutor =
            USDE.balanceOf(address(uniswapV4Exposed));

        uint256 amountOut = uniswapV4Exposed.swap(amountIn, protocolData);
        assertEq(USDE.balanceOf(poolManager), usdeBalanceBeforePool + amountIn);
        assertEq(
            USDE.balanceOf(address(uniswapV4Exposed)),
            usdeBalanceBeforeSwapExecutor - amountIn
        );
        assertTrue(IERC20(WBTC_ADDR).balanceOf(ALICE) == amountOut);
    }
}

contract TychoRouterForBalancerV3Test is TychoRouterTestSetup {
    function testSingleSwapUSV4CallbackPermit2() public {
        vm.startPrank(ALICE);
        uint256 amountIn = 100 ether;
        deal(USDE_ADDR, ALICE, amountIn);
        (
            IAllowanceTransfer.PermitSingle memory permitSingle,
            bytes memory signature
        ) = handlePermit2Approval(USDE_ADDR, tychoRouterAddr, amountIn);

        UniswapV4Executor.UniswapV4Pool[] memory pools =
            new UniswapV4Executor.UniswapV4Pool[](1);
        pools[0] = UniswapV4Executor.UniswapV4Pool({
            intermediaryToken: USDT_ADDR,
            fee: uint24(100),
            tickSpacing: int24(1)
        });

        bytes memory protocolData = UniswapV4Utils.encodeExactInput(
            USDE_ADDR,
            USDT_ADDR,
            true,
            RestrictTransferFrom.TransferType.TransferFrom,
            ALICE,
            pools
        );

        bytes memory swap =
            encodeSingleSwap(address(usv4Executor), protocolData);

        tychoRouter.singleSwapPermit2(
            amountIn,
            USDE_ADDR,
            USDT_ADDR,
            99943850,
            false,
            false,
            ALICE,
            permitSingle,
            signature,
            swap
        );

        assertEq(IERC20(USDT_ADDR).balanceOf(ALICE), 99963618);
        vm.stopPrank();
    }

    function testSplitSwapMultipleUSV4Callback() public {
        // This test has two uniswap v4 hops that will be executed inside of the V4 pool manager
        // USDE -> USDT -> WBTC
        uint256 amountIn = 100 ether;
        deal(USDE_ADDR, ALICE, amountIn);

        UniswapV4Executor.UniswapV4Pool[] memory pools =
            new UniswapV4Executor.UniswapV4Pool[](2);
        pools[0] = UniswapV4Executor.UniswapV4Pool({
            intermediaryToken: USDT_ADDR,
            fee: uint24(100),
            tickSpacing: int24(1)
        });
        pools[1] = UniswapV4Executor.UniswapV4Pool({
            intermediaryToken: WBTC_ADDR,
            fee: uint24(3000),
            tickSpacing: int24(60)
        });

        bytes memory protocolData = UniswapV4Utils.encodeExactInput(
            USDE_ADDR,
            WBTC_ADDR,
            true,
            RestrictTransferFrom.TransferType.TransferFrom,
            ALICE,
            pools
        );

        bytes memory swap =
            encodeSingleSwap(address(usv4Executor), protocolData);

        vm.startPrank(ALICE);
        IERC20(USDE_ADDR).approve(tychoRouterAddr, amountIn);
        tychoRouter.singleSwap(
            amountIn,
            USDE_ADDR,
            WBTC_ADDR,
            118280,
            false,
            false,
            ALICE,
            true,
            swap
        );

        assertEq(IERC20(WBTC_ADDR).balanceOf(ALICE), 118281);
    }

    function testSingleUSV4IntegrationGroupedSwap() public {
        // Test created with calldata from our router encoder.

        // Performs a single swap from USDC to PEPE though ETH using two
        // consecutive USV4 pools. It's a single swap because it is a consecutive grouped swaps
        //
        //   USDC ──(USV4)──> ETH ───(USV4)──> PEPE
        //
        deal(USDC_ADDR, ALICE, 1 ether);
        uint256 balanceBefore = IERC20(PEPE_ADDR).balanceOf(ALICE);

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(USDC_ADDR).approve(PERMIT2_ADDRESS, type(uint256).max);
        bytes memory callData = loadCallDataFromFile(
            "test_single_encoding_strategy_usv4_grouped_swap"
        );
        (bool success,) = tychoRouterAddr.call(callData);

        vm.stopPrank();

        uint256 balanceAfter = IERC20(PEPE_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertEq(balanceAfter - balanceBefore, 123172000092711286554274694);
    }

    function testSingleUSV4IntegrationInputETH() public {
        // Test created with calldata from our router encoder.

        // Performs a single swap from ETH to PEPE without wrapping or unwrapping
        //
        //   ETH ───(USV4)──> PEPE
        //
        deal(ALICE, 1 ether);
        uint256 balanceBefore = IERC20(PEPE_ADDR).balanceOf(ALICE);

        bytes memory callData =
            loadCallDataFromFile("test_single_encoding_strategy_usv4_eth_in");
        (bool success,) = tychoRouterAddr.call{value: 1 ether}(callData);

        vm.stopPrank();

        uint256 balanceAfter = IERC20(PEPE_ADDR).balanceOf(ALICE);

        assertTrue(success, "Call Failed");
        assertEq(balanceAfter - balanceBefore, 235610487387677804636755778);
    }

    function testSingleUSV4IntegrationOutputETH() public {
        // Test created with calldata from our router encoder.

        // Performs a single swap from USDC to ETH without wrapping or unwrapping
        //
        //   USDC ───(USV4)──> ETH
        //
        deal(USDC_ADDR, ALICE, 3000_000000);
        uint256 balanceBefore = ALICE.balance;

        // Approve permit2
        vm.startPrank(ALICE);
        IERC20(USDC_ADDR).approve(PERMIT2_ADDRESS, type(uint256).max);

        bytes memory callData =
            loadCallDataFromFile("test_single_encoding_strategy_usv4_eth_out");
        (bool success,) = tychoRouterAddr.call(callData);

        vm.stopPrank();

        uint256 balanceAfter = ALICE.balance;

        assertTrue(success, "Call Failed");
        console.logUint(balanceAfter - balanceBefore);
        assertEq(balanceAfter - balanceBefore, 1474406268748155809);
    }
}
