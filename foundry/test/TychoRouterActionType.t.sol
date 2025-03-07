// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@src/executors/UniswapV4Executor.sol";
import {TychoRouter} from "@src/TychoRouter.sol";
import "./TychoRouterTestSetupActionType.sol";
import "./executors/UniswapV4Utils.sol";
import {SafeCallback} from "@uniswap/v4-periphery/src/base/SafeCallback.sol";

contract TychoRouterActionTypeTest is TychoRouterTestSetupActionType {
    bytes32 public constant EXECUTOR_SETTER_ROLE =
        0x6a1dd52dcad5bd732e45b6af4e7344fa284e2d7d4b23b5b09cb55d36b0685c87;
    bytes32 public constant FEE_SETTER_ROLE =
        0xe6ad9a47fbda1dc18de1eb5eeb7d935e5e81b4748f3cfc61e233e64f88182060;
    bytes32 public constant PAUSER_ROLE =
        0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a;
    bytes32 public constant FUND_RESCUER_ROLE =
        0x912e45d663a6f4cc1d0491d8f046e06c616f40352565ea1cdb86a0e1aaefa41b;

    event CallbackVerifierSet(address indexed callbackVerifier);
    event Withdrawal(
        address indexed token, uint256 amount, address indexed receiver
    );

    function testSwapActionType() public {
        // Trade 1 WETH for DAI with 1 swap on Uniswap V2
        // Checks amount out at the end
        uint256 amountIn = 1 ether;
        deal(WETH_ADDR, ALICE, amountIn);

        bytes memory protocolData = encodeUniswapV2Swap(
            WETH_ADDR, WETH_DAI_POOL, tychoRouterAddr, false
        );
        bytes memory swap = encodeSwap(
            uint8(0), uint8(1), uint24(0), address(usv2Executor), protocolData
        );
        bytes[] memory swaps = new bytes[](1);
        swaps[0] = swap;
        uint256 minAmountOut = 2600 * 1e18;
        bytes memory transferData = abi.encodePacked(
            amountIn, // amount
            uint8(0), // actionType
            WETH_DAI_POOL, // actionData (from here downwards) - receiver
            WETH_ADDR // token
        );
        bytes memory swapData = abi.encodePacked(
            amountIn, // amount
            uint8(1), // actionType
            WETH_ADDR, // actionData (from here downwards)
            DAI_ADDR,
            minAmountOut,
            false,
            false,
            uint256(2),
            ALICE,
            pleEncode(swaps)
        );

        bytes[] memory batchArray = new bytes[](2);
        batchArray[0] = transferData;
        batchArray[1] = swapData;

        bytes memory batchData = pleEncode(batchArray);


        vm.startPrank(ALICE);
        // Approve the tokenIn to be transferred to the router
        IERC20(WETH_ADDR).approve(address(tychoRouterAddr), amountIn);
        tychoRouter.batchExecute(batchData);

        uint256 expectedAmount = 2659881924818443699787;
        uint256 daiBalance = IERC20(DAI_ADDR).balanceOf(ALICE);
        assertEq(daiBalance, expectedAmount);
        assertEq(IERC20(WETH_ADDR).balanceOf(ALICE), 0);

        vm.stopPrank();
    }
}
