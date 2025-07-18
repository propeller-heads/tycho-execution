// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {TychoRouter} from "@src/TychoRouter.sol";
import "./TychoRouterTestSetup.sol";

contract TychoRouterTest is TychoRouterTestSetup {
    bytes32 public constant EXECUTOR_SETTER_ROLE =
        0x6a1dd52dcad5bd732e45b6af4e7344fa284e2d7d4b23b5b09cb55d36b0685c87;
    bytes32 public constant PAUSER_ROLE =
        0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a;
    bytes32 public constant FUND_RESCUER_ROLE =
        0x912e45d663a6f4cc1d0491d8f046e06c616f40352565ea1cdb86a0e1aaefa41b;

    event CallbackVerifierSet(address indexed callbackVerifier);
    event Withdrawal(
        address indexed token, uint256 amount, address indexed receiver
    );

    function testSetExecutorsValidRole() public {
        // Set single executor
        address[] memory executors = new address[](1);
        executors[0] = DUMMY;
        vm.startPrank(EXECUTOR_SETTER);
        tychoRouter.setExecutors(executors);
        vm.stopPrank();
        assert(tychoRouter.executors(DUMMY) == true);

        // Set multiple executors
        address[] memory executors2 = new address[](2);
        executors2[0] = DUMMY2;
        executors2[1] = DUMMY3;
        vm.startPrank(EXECUTOR_SETTER);
        tychoRouter.setExecutors(executors2);
        vm.stopPrank();
        assert(tychoRouter.executors(DUMMY2) == true);
        assert(tychoRouter.executors(DUMMY3) == true);
    }

    function testRemoveExecutorValidRole() public {
        vm.startPrank(EXECUTOR_SETTER);
        address[] memory executors = new address[](1);
        executors[0] = DUMMY;
        tychoRouter.setExecutors(executors);
        tychoRouter.removeExecutor(DUMMY);
        vm.stopPrank();
        assert(tychoRouter.executors(DUMMY) == false);
    }

    function testRemoveExecutorMissingSetterRole() public {
        vm.expectRevert();
        tychoRouter.removeExecutor(BOB);
    }

    function testSetExecutorsMissingSetterRole() public {
        vm.expectRevert();
        address[] memory executors = new address[](1);
        executors[0] = DUMMY;
        tychoRouter.setExecutors(executors);
    }

    function testWithdrawNative() public {
        vm.startPrank(FUND_RESCUER);
        // Send 100 ether to tychoRouter
        assertEq(tychoRouterAddr.balance, 0);
        assertEq(FUND_RESCUER.balance, 0);
        vm.deal(tychoRouterAddr, 100 ether);
        vm.expectEmit();
        emit Withdrawal(address(0), 100 ether, FUND_RESCUER);
        tychoRouter.withdrawNative(FUND_RESCUER);
        assertEq(tychoRouterAddr.balance, 0);
        assertEq(FUND_RESCUER.balance, 100 ether);
        vm.stopPrank();
    }

    function testWithdrawNativeFailures() public {
        vm.deal(tychoRouterAddr, 100 ether);
        vm.startPrank(FUND_RESCUER);
        vm.expectRevert(TychoRouter__AddressZero.selector);
        tychoRouter.withdrawNative(address(0));
        vm.stopPrank();

        // Not role FUND_RESCUER
        vm.startPrank(BOB);
        vm.expectRevert();
        tychoRouter.withdrawNative(FUND_RESCUER);
        vm.stopPrank();
    }

    function testWithdrawERC20Tokens() public {
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(WETH_ADDR);
        tokens[1] = IERC20(USDC_ADDR);
        for (uint256 i = 0; i < tokens.length; i++) {
            deal(address(tokens[i]), tychoRouterAddr, 100 ether);
        }

        vm.startPrank(FUND_RESCUER);
        tychoRouter.withdraw(tokens, FUND_RESCUER);

        // Check balances after withdrawing
        for (uint256 i = 0; i < tokens.length; i++) {
            // slither-disable-next-line calls-loop
            assertEq(tokens[i].balanceOf(tychoRouterAddr), 0);
            // slither-disable-next-line calls-loop
            assertEq(tokens[i].balanceOf(FUND_RESCUER), 100 ether);
        }
        vm.stopPrank();
    }

    function testWithdrawERC20TokensFailures() public {
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(WETH_ADDR);
        tokens[1] = IERC20(USDC_ADDR);
        for (uint256 i = 0; i < tokens.length; i++) {
            deal(address(tokens[i]), tychoRouterAddr, 100 ether);
        }

        vm.startPrank(FUND_RESCUER);
        vm.expectRevert(TychoRouter__AddressZero.selector);
        tychoRouter.withdraw(tokens, address(0));
        vm.stopPrank();

        // Not role FUND_RESCUER
        vm.startPrank(BOB);
        vm.expectRevert();
        tychoRouter.withdraw(tokens, FUND_RESCUER);
        vm.stopPrank();
    }

    function testPause() public {
        vm.startPrank(PAUSER);
        assertEq(tychoRouter.paused(), false);
        tychoRouter.pause();
        assertEq(tychoRouter.paused(), true);
        vm.stopPrank();

        vm.startPrank(UNPAUSER);
        tychoRouter.unpause();
        assertEq(tychoRouter.paused(), false);
        vm.stopPrank();

        vm.startPrank(UNPAUSER);
        vm.expectRevert();
        tychoRouter.unpause();
        vm.stopPrank();
    }

    function testPauseNonRole() public {
        vm.startPrank(BOB);
        vm.expectRevert();
        tychoRouter.pause();
        vm.stopPrank();
    }

    function testWrapETH() public {
        uint256 amount = 1 ether;
        vm.deal(BOB, amount);

        vm.startPrank(BOB);
        tychoRouter.wrapETH{value: amount}(amount);
        vm.stopPrank();

        assertEq(tychoRouterAddr.balance, 0);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), amount);
    }

    function testUnwrapETH() public {
        uint256 amount = 1 ether;
        deal(WETH_ADDR, tychoRouterAddr, amount);

        tychoRouter.unwrapETH(amount);

        assertEq(tychoRouterAddr.balance, amount);
        assertEq(IERC20(WETH_ADDR).balanceOf(tychoRouterAddr), 0);
    }

    function testEmptySwapsRevert() public {
        uint256 amountIn = 10 ** 18;
        bytes memory swaps = "";
        vm.expectRevert(TychoRouter__EmptySwaps.selector);
        tychoRouter.exposedSplitSwap(amountIn, 2, swaps);
    }
}
