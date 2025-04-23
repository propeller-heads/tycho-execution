// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../lib/LibSwap.sol";

contract LibSwapTest is Test {
    using LibSwap for bytes;

    function testSingleSwap() public view {
        address executor = 0x1234567890123456789012345678901234567890;
        bytes memory protocolData = abi.encodePacked(uint256(123));

        bytes memory swap = abi.encodePacked(executor, protocolData);
        this.assertSingleSwap(swap, executor, protocolData);
    }

    function assertSingleSwap(
        bytes calldata swap,
        address executor,
        bytes calldata protocolData
    ) public pure {
        (address decodedExecutor, bytes memory decodedProtocolData) =
            swap.decodeSingleSwap();
        assertEq(decodedExecutor, executor);
        assertEq(decodedProtocolData, protocolData);
    }

    function testSequentialSwap() public view {
        address executor = 0x1234567890123456789012345678901234567890;
        bytes memory protocolData = abi.encodePacked(uint256(234));

        bytes memory swap = abi.encodePacked(executor, protocolData);
        this.assertSequentialSwap(swap, executor, protocolData);
    }

    function assertSequentialSwap(
        bytes calldata swap,
        address executor,
        bytes calldata protocolData
    ) public pure {
        (address decodedExecutor, bytes memory decodedProtocolData) =
            swap.decodeSequentialSwap();
        assertEq(decodedExecutor, executor);
        assertEq(decodedProtocolData, protocolData);
    }

    function testSplitSwap() public view {
        uint8 tokenInIndex = 1;
        uint8 tokenOutIndex = 2;
        uint24 split = 3;
        address executor = 0x1234567890123456789012345678901234567890;
        bytes memory protocolData = abi.encodePacked(uint256(456));

        bytes memory swap = abi.encodePacked(
            tokenInIndex, tokenOutIndex, split, executor, protocolData
        );
        this.assertSplitSwap(
            swap, tokenInIndex, tokenOutIndex, split, executor, protocolData
        );
    }

    // This is necessary so that the compiler accepts bytes as a LibSwap.sol for testing
    // This is because this function takes calldata as input
    function assertSplitSwap(
        bytes calldata swap,
        uint8 tokenInIndex,
        uint8 tokenOutIndex,
        uint24 split,
        address executor,
        bytes calldata protocolData
    ) public pure {
        (
            uint8 decodedTokenInIndex,
            uint8 decodedTokenOutIndex,
            uint24 decodedSplit,
            address decodedExecutor,
            bytes memory decodedProtocolData
        ) = swap.decodeSplitSwap();
        assertEq(decodedTokenInIndex, tokenInIndex);
        assertEq(decodedTokenOutIndex, tokenOutIndex);
        assertEq(decodedSplit, split);
        assertEq(decodedExecutor, executor);
        assertEq(decodedProtocolData, protocolData);
    }
}
