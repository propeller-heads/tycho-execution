// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../TestUtils.sol";
import "../TychoRouterTestSetup.sol";
import "@src/executors/LiquoriceExecutor.sol";
import {Constants} from "../Constants.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Permit2TestHelper} from "../Permit2TestHelper.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LiquoriceExecutorExposed is LiquoriceExecutor {
    constructor(
        address _liquoriceSettlement,
        address _permit2
    ) LiquoriceExecutor(_liquoriceSettlement, _permit2) {}

    function decodeData(
        bytes calldata data
    )
        external
        pure
        returns (
            address tokenIn,
            address tokenOut,
            TransferType transferType,
            uint8 partialFillOffset,
            uint256 originalBaseTokenAmount,
            uint256 minBaseTokenAmount,
            bool approvalNeeded,
            address receiver,
            bytes memory liquoriceCalldata
        )
    {
        return _decodeData(data);
    }

    function clampAmount(
        uint256 givenAmount,
        uint256 originalBaseTokenAmount,
        uint256 minBaseTokenAmount
    ) external pure returns (uint256) {
        return
            _clampAmount(
                givenAmount,
                originalBaseTokenAmount,
                minBaseTokenAmount
            );
    }
}

contract LiquoriceExecutorTest is Constants, Permit2TestHelper, TestUtils {
    using SafeERC20 for IERC20;

    LiquoriceExecutorExposed liquoriceExecutor;

    address constant LIQUORICE_SETTLEMENT =
        0x0448633eb8B0A42EfED924C42069E0DcF08fb552;

    IERC20 WETH = IERC20(WETH_ADDR);
    IERC20 USDC = IERC20(USDC_ADDR);
    IERC20 WBTC = IERC20(WBTC_ADDR);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 22667985);
        liquoriceExecutor = new LiquoriceExecutorExposed(
            LIQUORICE_SETTLEMENT,
            PERMIT2_ADDRESS
        );
    }

    function testDecodeData() public view {
        bytes memory liquoriceCalldata = abi.encodePacked(
            bytes4(0xdeadbeef), // mock selector
            hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        );

        uint256 originalAmount = 1000000000; // 1000 USDC
        uint256 minAmount = 800000000; // 800 USDC
        address receiver = address(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD);

        bytes memory params = abi.encodePacked(
            USDC_ADDR, // tokenIn (20 bytes)
            WETH_ADDR, // tokenOut (20 bytes)
            uint8(RestrictTransferFrom.TransferType.Transfer), // transferType (1 byte)
            uint8(5), // partialFillOffset (1 byte)
            originalAmount, // originalBaseTokenAmount (32 bytes)
            minAmount, // minBaseTokenAmount (32 bytes)
            uint8(0), // approvalNeeded (1 byte) - false
            receiver, // receiver (20 bytes)
            liquoriceCalldata // variable length
        );

        (
            address decodedTokenIn,
            address decodedTokenOut,
            RestrictTransferFrom.TransferType decodedTransferType,
            uint8 decodedPartialFillOffset,
            uint256 decodedOriginalAmount,
            uint256 decodedMinAmount,
            bool decodedApprovalNeeded,
            address decodedReceiver,
            bytes memory decodedCalldata
        ) = liquoriceExecutor.decodeData(params);

        assertEq(decodedTokenIn, USDC_ADDR, "tokenIn mismatch");
        assertEq(decodedTokenOut, WETH_ADDR, "tokenOut mismatch");
        assertEq(
            uint8(decodedTransferType),
            uint8(RestrictTransferFrom.TransferType.Transfer),
            "transferType mismatch"
        );
        assertEq(decodedPartialFillOffset, 5, "partialFillOffset mismatch");
        assertEq(
            decodedOriginalAmount,
            originalAmount,
            "originalAmount mismatch"
        );
        assertEq(decodedMinAmount, minAmount, "minAmount mismatch");
        assertFalse(decodedApprovalNeeded, "approvalNeeded should be false");
        assertEq(decodedReceiver, receiver, "receiver mismatch");
        assertEq(
            keccak256(decodedCalldata),
            keccak256(liquoriceCalldata),
            "calldata mismatch"
        );
    }

    function testDecodeData_InvalidDataLength() public {
        // Too short - missing required fields
        bytes memory tooShort = abi.encodePacked(
            USDC_ADDR, // tokenIn (20 bytes)
            WETH_ADDR, // tokenOut (20 bytes)
            uint8(RestrictTransferFrom.TransferType.Transfer) // transferType (1 byte)
            // missing: partialFillOffset, originalAmount, approvalNeeded, receiver
        );

        vm.expectRevert(
            LiquoriceExecutor.LiquoriceExecutor__InvalidDataLength.selector
        );
        liquoriceExecutor.decodeData(tooShort);
    }

    function testClampAmount_WithinRange() public view {
        // givenAmount is within [minBaseTokenAmount, originalBaseTokenAmount]
        uint256 result = liquoriceExecutor.clampAmount(
            500, // givenAmount
            1000, // originalBaseTokenAmount
            100 // minBaseTokenAmount
        );
        assertEq(result, 500, "Should return givenAmount when within range");
    }

    function testClampAmount_ExceedsMax() public view {
        // givenAmount exceeds originalBaseTokenAmount
        uint256 result = liquoriceExecutor.clampAmount(
            1500, // givenAmount
            1000, // originalBaseTokenAmount
            100 // minBaseTokenAmount
        );
        assertEq(
            result,
            1000,
            "Should clamp to originalBaseTokenAmount when exceeded"
        );
    }

    function testClampAmount_BelowMin_Reverts() public {
        // givenAmount is below minBaseTokenAmount - should revert
        vm.expectRevert(
            LiquoriceExecutor.LiquoriceExecutor__AmountBelowMinimum.selector
        );
        liquoriceExecutor.clampAmount(
            50, // givenAmount
            1000, // originalBaseTokenAmount
            100 // minBaseTokenAmount
        );
    }
}
