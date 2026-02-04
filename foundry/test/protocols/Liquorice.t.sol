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
    constructor(address _permit2) LiquoriceExecutor(_permit2) {}

    function decodeData(bytes calldata data)
        external
        pure
        returns (
            address tokenIn,
            address tokenOut,
            TransferType transferType,
            uint8 partialFillOffset,
            uint256 originalBaseTokenAmount,
            address[] memory allowanceSpenders,
            bool[] memory approvalsNeeded,
            address targetContract,
            address receiver,
            bytes memory liquoriceCalldata
        )
    {
        return _decodeData(data);
    }
}

contract LiquoriceExecutorTest is Constants, Permit2TestHelper, TestUtils {
    using SafeERC20 for IERC20;

    LiquoriceExecutorExposed liquoriceExecutor;

    IERC20 WETH = IERC20(WETH_ADDR);
    IERC20 USDC = IERC20(USDC_ADDR);
    IERC20 WBTC = IERC20(WBTC_ADDR);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 22667985);
        liquoriceExecutor = new LiquoriceExecutorExposed(PERMIT2_ADDRESS);
    }

    function testDecodeData_NoAllowances() public view {
        bytes memory liquoriceCalldata = abi.encodePacked(
            bytes4(0xdeadbeef), // mock selector
            hex"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        );

        uint256 originalAmount = 1000000000; // 1000 USDC
        address targetContract = address(0x1234567890123456789012345678901234567890);
        address receiver = address(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD);

        // Encode with 0 allowances
        bytes memory params = abi.encodePacked(
            USDC_ADDR, // tokenIn (20 bytes)
            WETH_ADDR, // tokenOut (20 bytes)
            uint8(RestrictTransferFrom.TransferType.Transfer), // transferType (1 byte)
            uint8(5), // partialFillOffset (1 byte)
            originalAmount, // originalBaseTokenAmount (32 bytes)
            uint8(0), // numAllowances (1 byte)
            targetContract, // targetContract (20 bytes)
            receiver, // receiver (20 bytes)
            liquoriceCalldata // variable length
        );

        (
            address decodedTokenIn,
            address decodedTokenOut,
            RestrictTransferFrom.TransferType decodedTransferType,
            uint8 decodedPartialFillOffset,
            uint256 decodedOriginalAmount,
            address[] memory decodedSpenders,
            bool[] memory decodedApprovals,
            address decodedTarget,
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
            decodedOriginalAmount, originalAmount, "originalAmount mismatch"
        );
        assertEq(decodedSpenders.length, 0, "spenders length mismatch");
        assertEq(decodedApprovals.length, 0, "approvals length mismatch");
        assertEq(decodedTarget, targetContract, "targetContract mismatch");
        assertEq(decodedReceiver, receiver, "receiver mismatch");
        assertEq(
            keccak256(decodedCalldata),
            keccak256(liquoriceCalldata),
            "calldata mismatch"
        );
    }

    function testDecodeData_WithAllowances() public view {
        bytes memory liquoriceCalldata = hex"deadbeef";

        uint256 originalAmount = 2000000000; // 2000 USDC
        address targetContract = address(0x1111111111111111111111111111111111111111);
        address receiver = address(0x2222222222222222222222222222222222222222);
        address spender1 = address(0x3333333333333333333333333333333333333333);
        address spender2 = address(0x4444444444444444444444444444444444444444);

        // Encode with 2 allowances
        bytes memory params = abi.encodePacked(
            USDC_ADDR, // tokenIn (20 bytes)
            WBTC_ADDR, // tokenOut (20 bytes)
            uint8(RestrictTransferFrom.TransferType.None), // transferType (1 byte)
            uint8(12), // partialFillOffset (1 byte)
            originalAmount, // originalBaseTokenAmount (32 bytes)
            uint8(2), // numAllowances (1 byte)
            spender1, // allowance spender 1 (20 bytes)
            uint8(1), // approval needed 1 (1 byte) - true
            spender2, // allowance spender 2 (20 bytes)
            uint8(0), // approval needed 2 (1 byte) - false
            targetContract, // targetContract (20 bytes)
            receiver, // receiver (20 bytes)
            liquoriceCalldata // variable length
        );

        (
            address decodedTokenIn,
            address decodedTokenOut,
            RestrictTransferFrom.TransferType decodedTransferType,
            uint8 decodedPartialFillOffset,
            uint256 decodedOriginalAmount,
            address[] memory decodedSpenders,
            bool[] memory decodedApprovals,
            address decodedTarget,
            address decodedReceiver,
            bytes memory decodedCalldata
        ) = liquoriceExecutor.decodeData(params);

        assertEq(decodedTokenIn, USDC_ADDR, "tokenIn mismatch");
        assertEq(decodedTokenOut, WBTC_ADDR, "tokenOut mismatch");
        assertEq(
            uint8(decodedTransferType),
            uint8(RestrictTransferFrom.TransferType.None),
            "transferType mismatch"
        );
        assertEq(decodedPartialFillOffset, 12, "partialFillOffset mismatch");
        assertEq(
            decodedOriginalAmount, originalAmount, "originalAmount mismatch"
        );
        assertEq(decodedSpenders.length, 2, "spenders length mismatch");
        assertEq(decodedApprovals.length, 2, "approvals length mismatch");
        assertEq(decodedSpenders[0], spender1, "spender1 mismatch");
        assertEq(decodedSpenders[1], spender2, "spender2 mismatch");
        assertTrue(decodedApprovals[0], "approval1 should be true");
        assertFalse(decodedApprovals[1], "approval2 should be false");
        assertEq(decodedTarget, targetContract, "targetContract mismatch");
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
            // missing: partialFillOffset, originalAmount, numAllowances, target, receiver
        );

        vm.expectRevert(
            LiquoriceExecutor.LiquoriceExecutor__InvalidDataLength.selector
        );
        liquoriceExecutor.decodeData(tooShort);
    }

    function testDecodeData_InvalidDataLength_MissingAllowanceData() public {
        // Has numAllowances = 1 but doesn't include the allowance data
        bytes memory missingAllowance = abi.encodePacked(
            USDC_ADDR, // tokenIn (20 bytes)
            WETH_ADDR, // tokenOut (20 bytes)
            uint8(RestrictTransferFrom.TransferType.Transfer), // transferType (1 byte)
            uint8(5), // partialFillOffset (1 byte)
            uint256(1000000000), // originalAmount (32 bytes)
            uint8(1), // numAllowances = 1 (1 byte)
            // Missing: spender (20 bytes) + approvalNeeded (1 byte)
            address(0x1234567890123456789012345678901234567890), // target (20 bytes)
            address(0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD) // receiver (20 bytes)
        );

        vm.expectRevert(
            LiquoriceExecutor.LiquoriceExecutor__InvalidDataLength.selector
        );
        liquoriceExecutor.decodeData(missingAllowance);
    }

    function testDecodeData_ZeroPartialFillOffset() public view {
        bytes memory liquoriceCalldata = hex"cafebabe";
        address targetContract = address(0x5555555555555555555555555555555555555555);
        address receiver = address(0x6666666666666666666666666666666666666666);

        // partialFillOffset = 0 means partial fill not supported
        bytes memory params = abi.encodePacked(
            WETH_ADDR,
            USDC_ADDR,
            uint8(RestrictTransferFrom.TransferType.Transfer),
            uint8(0), // partialFillOffset = 0
            uint256(1e18),
            uint8(0), // no allowances
            targetContract,
            receiver,
            liquoriceCalldata
        );

        (,,, uint8 decodedOffset,,,,,,) = liquoriceExecutor.decodeData(params);

        assertEq(decodedOffset, 0, "partialFillOffset should be 0");
    }
}
