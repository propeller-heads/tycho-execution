// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../TychoRouterTestSetup.sol";
import "../TestUtils.sol";
import "@src/executors/EtherfiExecutor.sol";
import {Constants} from "../Constants.sol";

contract EtherfiExecutorExposed is EtherfiExecutor {
    constructor(address _permit2) EtherfiExecutor(_permit2) {}

    function decodeParams(bytes calldata data)
        external
        pure
        returns (
            address receiver,
            TransferType transferType,
            EtherfiDirection direction,
            bool approvalNeeded
        )
    {
        return _decodeData(data);
    }
}

contract EtherfiExecutorTest is Constants, TestUtils {
    EtherfiExecutorExposed etherfiExposed;

    address constant EETH_ADDR =
        address(0x35fA164735182de50811E8e2E824cFb9B6118ac2);
    address constant WEETH_ADDR =
        address(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);

    function setUp() public {
        uint256 forkBlock = 23934489;
        vm.createSelectFork(vm.rpcUrl("mainnet"), forkBlock);
        etherfiExposed = new EtherfiExecutorExposed(PERMIT2_ADDRESS);
    }

    function _mintEethToExecutor(uint256 amountIn)
        internal
        returns (uint256 minted)
    {
        bytes memory protocolData = abi.encodePacked(
            address(etherfiExposed),
            RestrictTransferFrom.TransferType.None,
            EtherfiDirection.EthToEeth,
            false
        );

        vm.deal(address(this), amountIn);
        minted = etherfiExposed.swap{value: amountIn}(amountIn, protocolData);
    }

    function testDecodeParams() public view {
        bytes memory params = abi.encodePacked(
            BOB,
            RestrictTransferFrom.TransferType.None,
            EtherfiDirection.EethToWeeth,
            true
        );

        (
            address receiver,
            RestrictTransferFrom.TransferType transferType,
            EtherfiDirection direction,
            bool approvalNeeded
        ) = etherfiExposed.decodeParams(params);

        assertEq(receiver, BOB);
        assertEq(
            uint8(transferType), uint8(RestrictTransferFrom.TransferType.None)
        );
        assertEq(uint8(direction), uint8(EtherfiDirection.EethToWeeth));
        assertEq(approvalNeeded, true);
    }

    function testDecodeParamsInvalidDataLength() public {
        bytes memory invalidParams =
            abi.encodePacked(BOB, RestrictTransferFrom.TransferType.None);

        vm.expectRevert(EtherfiExecutor__InvalidDataLength.selector);
        etherfiExposed.decodeParams(invalidParams);
    }

    function testSwapEthToEeth() public {
        uint256 amountIn = 1 ether;
        bytes memory protocolData = abi.encodePacked(
            BOB,
            RestrictTransferFrom.TransferType.None,
            EtherfiDirection.EthToEeth,
            false
        );

        vm.deal(address(this), amountIn);
        uint256 balanceBefore = IERC20(EETH_ADDR).balanceOf(BOB);

        uint256 amountOut =
            etherfiExposed.swap{value: amountIn}(amountIn, protocolData);

        uint256 balanceAfter = IERC20(EETH_ADDR).balanceOf(BOB);
        assertGt(balanceAfter, balanceBefore);
        assertEq(balanceAfter - balanceBefore, amountOut);
    }

    function testSwapEethToWeeth() public {
        uint256 minted = _mintEethToExecutor(1 ether);
        bytes memory protocolData = abi.encodePacked(
            BOB,
            RestrictTransferFrom.TransferType.None,
            EtherfiDirection.EethToWeeth,
            true
        );

        uint256 balanceBefore = IERC20(WEETH_ADDR).balanceOf(BOB);
        uint256 amountOut = etherfiExposed.swap(minted, protocolData);
        uint256 balanceAfter = IERC20(WEETH_ADDR).balanceOf(BOB);

        assertGt(balanceAfter, balanceBefore);
        assertEq(balanceAfter - balanceBefore, amountOut);
    }

    function testSwapWeethToEeth() public {
        uint256 minted = _mintEethToExecutor(1 ether);
        bytes memory wrapData = abi.encodePacked(
            address(etherfiExposed),
            RestrictTransferFrom.TransferType.None,
            EtherfiDirection.EethToWeeth,
            true
        );
        uint256 weethAmount = etherfiExposed.swap(minted, wrapData);

        bytes memory unwrapData = abi.encodePacked(
            BOB,
            RestrictTransferFrom.TransferType.None,
            EtherfiDirection.WeethToEeth,
            false
        );

        uint256 balanceBefore = IERC20(EETH_ADDR).balanceOf(BOB);
        uint256 amountOut = etherfiExposed.swap(weethAmount, unwrapData);
        uint256 balanceAfter = IERC20(EETH_ADDR).balanceOf(BOB);

        assertGt(balanceAfter, balanceBefore);
        assertEq(balanceAfter - balanceBefore, amountOut);
    }
}

contract TychoRouterForEtherfiTest is TychoRouterTestSetup {}
