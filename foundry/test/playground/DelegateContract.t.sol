// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./Contract.sol";
import "forge-std/Test.sol";
import {Constants} from "../Constants.sol";

contract DelegateContractTest is Test, Constants {
    Contract delegateContract;
    address POOL;

    function setUp() public {
        uint256 forkBlock = 22489327;
        vm.createSelectFork(vm.rpcUrl("mainnet"), forkBlock);

        POOL = address(new StablePool(USDC_ADDR, DAI_ADDR));
        deal(USDC_ADDR, POOL, 1000 ether);
        deal(DAI_ADDR, POOL, 1000 ether);

        delegateContract = new Contract();
    }

    function testSwapDirectly() public {
        uint256 amountIn = 10 ** 18;
        deal(USDC_ADDR, address(delegateContract), amountIn);
        uint256 amountOut =
            delegateContract.execute(amountIn, POOL, USDC_ADDR, DAI_ADDR, ALICE);

        assertEq(amountOut, amountIn);
        assertEq(IERC20(DAI_ADDR).balanceOf(ALICE), amountIn);
    }

    function testDelegate() public {
        console.log("Contract address:", delegateContract.whoIsThis());
        console.log("Alice address:", ALICE);

        // Alice's account has no code
        assert(ALICE.code.length == 0);

        vm.startPrank(ALICE);
        vm.signAndAttachDelegation(address(delegateContract), ALICE_PK);

        // Alice's account has code now
        assertGt(ALICE.code.length, 0);

        address who = Contract(payable(ALICE)).whoIsThis();
        console.log(
            "address(this) in DelegateContract calling from Alice:", who
        );
    }

    function testAliceSwaps() public {
        vm.startPrank(ALICE);
        vm.signAndAttachDelegation(address(delegateContract), ALICE_PK);

        assertGt(ALICE.code.length, 0);

        uint256 amountIn = 10 ** 18;
        deal(USDC_ADDR, ALICE, amountIn);
        uint256 amountOut = Contract(payable(ALICE)).execute(
            amountIn, POOL, USDC_ADDR, DAI_ADDR, ALICE
        );

        assertEq(amountOut, amountIn);
        assertEq(IERC20(DAI_ADDR).balanceOf(ALICE), amountIn);
    }

    function testBobStealsBySwappingAlice() public {
        vm.signAndAttachDelegation(address(delegateContract), ALICE_PK);
        assertGt(ALICE.code.length, 0);

        uint256 amountIn = 10 ** 18;
        deal(USDC_ADDR, ALICE, amountIn);

        vm.startPrank(BOB);
        uint256 amountOut = Contract(payable(ALICE)).execute(
            amountIn, POOL, USDC_ADDR, DAI_ADDR, BOB
        );

        assertEq(amountOut, amountIn);
        assertEq(IERC20(DAI_ADDR).balanceOf(BOB), amountIn);
    }
}
