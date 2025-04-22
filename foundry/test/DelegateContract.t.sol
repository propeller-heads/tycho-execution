// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../src/DelegateContract.sol";
import "@src/executors/TokenTransfer.sol";
import "forge-std/Test.sol";
import {Constants} from "./Constants.sol";

contract DelegateContractV1Test is Test, Constants {
    DelegateContract delegateContract;
    address WETH = 0x2387fD72C1DA19f6486B843F5da562679FbB4057;
    address DAI = 0xF45fF3F19686c316B3245250404C326Cb65aebEe;
    address POOL;

    function setUp() public {
        uint256 forkBlock = 239114;
        vm.createSelectFork(vm.rpcUrl("testnet"), forkBlock);

        // Alice's account has no code
        require(ALICE.code.length == 0);

        POOL = address(new Pool(WETH, DAI));
        deal(WETH, POOL, 1000 ether);
        deal(DAI, POOL, 1000 ether);

        delegateContract = new DelegateContract();
    }

    function testSwap() public {
        uint256 amountIn = 10 ** 18;
        deal(WETH, address(delegateContract), amountIn);
        uint256 amountOut = delegateContract.execute(
            amountIn, POOL, WETH, DAI, ALICE
        );

        assertEq(amountOut, amountIn);
        assertEq(IERC20(DAI).balanceOf(ALICE), amountIn);
    }

    function testAliceSwaps() public {
        vm.startPrank(ALICE);
        vm.signAndAttachDelegation(address(delegateContract), ALICE_PK);

        assertGt(ALICE.code.length, 0);

        uint256 amountIn = 10 ** 18;
        deal(WETH, ALICE, amountIn);
        uint256 amountOut = DelegateContract(payable(ALICE)).execute(
            amountIn, POOL, WETH, DAI, ALICE
        );

        assertEq(amountOut, amountIn);
        assertEq(IERC20(DAI).balanceOf(ALICE), amountIn);
    }

    function testBobStealsBySwappingAlice() public {
        vm.signAndAttachDelegation(address(delegateContract), ALICE_PK);
        assertGt(ALICE.code.length, 0);

        uint256 amountIn = 10 ** 18;
        deal(WETH, ALICE, amountIn);
        vm.startPrank(BOB);
        uint256 amountOut = DelegateContract(payable(ALICE)).execute(
            amountIn, POOL, WETH, DAI, BOB
        );

        assertEq(amountOut, amountIn);
        assertEq(IERC20(DAI).balanceOf(BOB), amountIn);
    }
}
