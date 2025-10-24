// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../TychoRouterTestSetup.sol";
import "@permit2/src/interfaces/IAllowanceTransfer.sol";
import "@src/executors/ShibaswapV2Executor.sol";
import {Constants} from "../Constants.sol";
import {Permit2TestHelper} from "../Permit2TestHelper.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";

contract ShibaswapV2ExecutorExposed is ShibaswapV2Executor {
    constructor(address _factory, bytes32 _initCode, address _permit2)
        ShibaswapV2Executor(_factory, _initCode, _permit2)
    {}

    function decodeData(bytes calldata data)
        external
        pure
        returns (
            address inToken,
            address outToken,
            uint24 fee,
            address receiver,
            address target,
            bool zeroForOne,
            RestrictTransferFrom.TransferType transferType
        )
    {
        return _decodeData(data);
    }

    function verifyPairAddress(
        address tokenA,
        address tokenB,
        uint24 fee,
        address target
    ) external view {
        _verifyPairAddress(tokenA, tokenB, fee, target);
    }
}

contract ShibaswapV2ExecutorTest is
    Test,
    TestUtils,
    Constants,
    Permit2TestHelper
{
    using SafeERC20 for IERC20;

    ShibaswapV2ExecutorExposed shibaswapV2Exposed;
    IERC20 DAI = IERC20(DAI_ADDR);
    IAllowanceTransfer permit2;

    function setUp() public {
        uint256 forkBlock = 17323404;
        vm.createSelectFork(vm.rpcUrl("mainnet"), forkBlock);

        // Note: Update with actual Shibaswap V2 factory and init code hash
        shibaswapV2Exposed = new ShibaswapV2ExecutorExposed(
            SHIBASWAPV2_FACTORY_ETHEREUM,
            SHIBASWAPV2_POOL_CODE_INIT_HASH,
            PERMIT2_ADDRESS
        );
        permit2 = IAllowanceTransfer(PERMIT2_ADDRESS);
    }

    function testDecodeParams() public view {
        uint24 expectedPoolFee = 500;
        bytes memory data = abi.encodePacked(
            WETH_ADDR,
            DAI_ADDR,
            expectedPoolFee,
            address(2),
            address(3),
            false,
            RestrictTransferFrom.TransferType.Transfer
        );

        (
            address tokenIn,
            address tokenOut,
            uint24 fee,
            address receiver,
            address target,
            bool zeroForOne,
            RestrictTransferFrom.TransferType transferType
        ) = shibaswapV2Exposed.decodeData(data);

        assertEq(tokenIn, WETH_ADDR);
        assertEq(tokenOut, DAI_ADDR);
        assertEq(fee, expectedPoolFee);
        assertEq(receiver, address(2));
        assertEq(target, address(3));
        assertEq(zeroForOne, false);
        assertEq(
            uint8(transferType),
            uint8(RestrictTransferFrom.TransferType.Transfer)
        );
    }

    // Note: The following integration tests require actual Shibaswap V2 pool addresses
    // Uncomment and update addresses once Shibaswap V2 is deployed

    /*
    function testSwapIntegration() public {
        uint256 amountIn = 10 ** 18;
        deal(WETH_ADDR, address(shibaswapV2Exposed), amountIn);

        uint256 expAmountOut = 1205_128428842122129186; //Expected output
        bool zeroForOne = false;

        bytes memory data = encodeShibaswapV2Swap(
            WETH_ADDR,
            DAI_ADDR,
            address(this),
            SHIBASWAPV2_WETH_USDT_POOL, // Update with actual pool address
            zeroForOne,
            RestrictTransferFrom.TransferType.Transfer
        );

        uint256 amountOut = shibaswapV2Exposed.swap(amountIn, data);

        assertGe(amountOut, expAmountOut);
        assertEq(IERC20(WETH_ADDR).balanceOf(address(shibaswapV2Exposed)), 0);
        assertGe(IERC20(DAI_ADDR).balanceOf(address(this)), expAmountOut);
    }
    */

    function testDecodeParamsInvalidDataLength() public {
        bytes memory invalidParams =
            abi.encodePacked(WETH_ADDR, address(2), address(3));

        vm.expectRevert(ShibaswapV2Executor__InvalidDataLength.selector);
        shibaswapV2Exposed.decodeData(invalidParams);
    }

    /*
    function testVerifyPairAddress() public view {
        // Update with actual Shibaswap V2 pool
        shibaswapV2Exposed.verifyPairAddress(
            WETH_ADDR, USDT_ADDR, 3000, SHIBASWAPV2_WETH_USDT_POOL
        );
    }

    function testShibaswapV2Callback() public {
        uint24 poolFee = 3000;
        uint256 amountOwed = 1000000000000000000;
        deal(WETH_ADDR, address(shibaswapV2Exposed), amountOwed);
        uint256 initialPoolReserve = IERC20(WETH_ADDR).balanceOf(SHIBASWAPV2_WETH_USDT_POOL);

        vm.startPrank(SHIBASWAPV2_WETH_USDT_POOL);
        bytes memory protocolData = abi.encodePacked(
            WETH_ADDR,
            USDT_ADDR,
            poolFee,
            RestrictTransferFrom.TransferType.Transfer,
            address(shibaswapV2Exposed)
        );
        uint256 dataOffset = 3;
        uint256 dataLength = protocolData.length;

        bytes memory callbackData = abi.encodePacked(
            bytes4(0xfa461e33),
            int256(amountOwed), // amount0Delta
            int256(0), // amount1Delta
            dataOffset,
            dataLength,
            protocolData
        );
        shibaswapV2Exposed.handleCallback(callbackData);
        vm.stopPrank();

        uint256 finalPoolReserve = IERC20(WETH_ADDR).balanceOf(SHIBASWAPV2_WETH_USDT_POOL);
        assertEq(finalPoolReserve - initialPoolReserve, amountOwed);
    }
    */

    function testSwapFailureInvalidTarget() public {
        uint256 amountIn = 10 ** 18;
        deal(WETH_ADDR, address(shibaswapV2Exposed), amountIn);
        bool zeroForOne = false;
        address fakePool = DUMMY; // Contract with minimal code

        bytes memory protocolData = abi.encodePacked(
            WETH_ADDR,
            DAI_ADDR,
            uint24(3000),
            address(this),
            fakePool,
            zeroForOne,
            RestrictTransferFrom.TransferType.Transfer
        );

        vm.expectRevert(ShibaswapV2Executor__InvalidTarget.selector);
        shibaswapV2Exposed.swap(amountIn, protocolData);
    }

    function encodeShibaswapV2Swap(
        address tokenIn,
        address tokenOut,
        address receiver,
        address target,
        bool zero2one,
        RestrictTransferFrom.TransferType transferType
    ) internal view returns (bytes memory) {
        IUniswapV3Pool pool = IUniswapV3Pool(target);
        return abi.encodePacked(
            tokenIn,
            tokenOut,
            pool.fee(),
            receiver,
            target,
            zero2one,
            transferType
        );
    }

    function testExportContract() public {
        exportRuntimeBytecode(address(shibaswapV2Exposed), "ShibaswapV2");
    }
}

contract TychoRouterForShibaswapV2Test is TychoRouterTestSetup {
    // Note: Uncomment once Shibaswap V2 executor is deployed and configured
    /*
    function testSingleSwapShibaswapV2Permit2() public {
        // Trade 1 WETH for USDT with 1 swap on Shibaswap V2 using Permit2
        // Tests entire ShibaswapV2 flow including callback
        vm.startPrank(ALICE);
        uint256 amountIn = 10 ** 18;
        deal(WETH_ADDR, ALICE, amountIn);
        (
            IAllowanceTransfer.PermitSingle memory permitSingle,
            bytes memory signature
        ) = handlePermit2Approval(WETH_ADDR, tychoRouterAddr, amountIn);

        uint256 expAmountOut = 1000_000000; // Expected USDT output
        bool zeroForOne = false;
        bytes memory protocolData = encodeShibaswapV2Swap(
            WETH_ADDR,
            USDT_ADDR,
            ALICE,
            SHIBASWAPV2_WETH_USDT_POOL,
            zeroForOne,
            RestrictTransferFrom.TransferType.TransferFrom
        );
        bytes memory swap =
            encodeSingleSwap(address(shibaswapV2Executor), protocolData);

        tychoRouter.singleSwapPermit2(
            amountIn,
            WETH_ADDR,
            USDT_ADDR,
            expAmountOut - 1,
            false,
            false,
            ALICE,
            permitSingle,
            signature,
            swap
        );

        uint256 finalBalance = IERC20(USDT_ADDR).balanceOf(ALICE);
        assertGe(finalBalance, expAmountOut);

        vm.stopPrank();
    }
    */
}

