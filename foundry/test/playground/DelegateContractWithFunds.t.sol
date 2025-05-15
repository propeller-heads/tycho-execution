// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./ContractWithFunds.sol";
import "forge-std/Test.sol";
import {Constants} from "../Constants.sol";

contract DelegateContractTest is Test, Constants {
    ContractWithFunds delegateContract;
    address POOL;

    function setUp() public {
        uint256 forkBlock = 22489327;
        vm.createSelectFork(vm.rpcUrl("mainnet"), forkBlock);

        POOL = address(new StablePool(USDC_ADDR, DAI_ADDR));
        deal(USDC_ADDR, POOL, 1000 ether);
        deal(DAI_ADDR, POOL, 1000 ether);

        delegateContract = new ContractWithFunds();
    }

    function testAliceFailedAttemptToStealContractFunds() public {
        // The original contract has 1000 USDC
        // Alice has no funds in her own wallet
        deal(USDC_ADDR, address(delegateContract), 1000_000_000);

        vm.signAndAttachDelegation(address(delegateContract), ALICE_PK);
        assertGt(ALICE.code.length, 0);

        vm.startPrank(ALICE);

        // Alice cannot steal funds from the original contract by delegating to herself.
        vm.expectRevert();
        ContractWithFunds(payable(ALICE)).withdraw(
            USDC_ADDR, 1000_000_000, ALICE
        );

        assertEq(IERC20(USDC_ADDR).balanceOf(ALICE), 0);
    }

    function testAliceWithdrawOwnFunds() public {
        deal(USDC_ADDR, address(delegateContract), 1000_000_000);

        vm.signAndAttachDelegation(address(delegateContract), ALICE_PK);
        assertGt(ALICE.code.length, 0);

        deal(USDC_ADDR, ALICE, 1000_000_000);

        vm.startPrank(ALICE);

        // Alice cannot steal funds from the original contract.
        ContractWithFunds(payable(ALICE)).withdraw(
            USDC_ADDR, 1000_000_000, ALICE
        );

        assertEq(IERC20(USDC_ADDR).balanceOf(ALICE), 1000_000_000);
    }
}
