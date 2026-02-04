// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@interfaces/IExecutor.sol";
import "../RestrictTransferFrom.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {
    IERC20,
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/// @title LiquoriceExecutor
/// @notice Executor for Liquorice RFQ (Request for Quote) swaps
/// @dev Handles RFQ swaps through Liquorice settlement contracts with support for
///      partial fills and dynamic allowance management
contract LiquoriceExecutor is IExecutor, RestrictTransferFrom {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    /// @notice Liquorice-specific errors
    error LiquoriceExecutor__InvalidDataLength();

    /// @notice Maximum number of allowances supported
    uint8 public constant MAX_ALLOWANCES = 5;

    // TODO: add _liquoriceSettlement address argument
    constructor(address _permit2) RestrictTransferFrom(_permit2) {}

    /// @notice Executes a swap through Liquorice's RFQ system
    /// @param givenAmount The amount of input token to swap
    /// @param data Encoded swap data containing tokens, allowances, and liquorice calldata
    /// @return calculatedAmount The amount of output token received
    function swap(
        uint256 givenAmount,
        bytes calldata data
    ) external payable virtual override returns (uint256 calculatedAmount) {
        (
            address tokenIn,
            address tokenOut,
            TransferType transferType,
            uint8 partialFillOffset,
            uint256 originalBaseTokenAmount,
            address[] memory allowanceSpenders,
            bool[] memory approvalsNeeded, // TODO: change to bool approvalNeeded, and give approval to _liquoriceBalanceManager
            address targetContract, // TODO: remove, use _liquoriceSettlement instead
            address receiver,
            bytes memory liquoriceCalldata
        ) = _decodeData(data);

        // Transfer tokens to executor
        _transfer(address(this), transferType, tokenIn, givenAmount);

        // Grant approvals to spenders as needed
        for (uint256 i = 0; i < allowanceSpenders.length; i++) {
            if (approvalsNeeded[i] && tokenIn != address(0)) {
                // slither-disable-next-line unused-return
                IERC20(tokenIn).forceApprove(
                    allowanceSpenders[i],
                    type(uint256).max
                );
            }
        }

        // Modify the fill amount in the calldata if partial fill is supported
        // If partialFillOffset is 0, partial fill is not supported
        bytes memory finalCalldata = liquoriceCalldata;
        if (partialFillOffset > 0) {
            finalCalldata = _modifyFilledTakerAmount(
                liquoriceCalldata,
                givenAmount,
                originalBaseTokenAmount,
                partialFillOffset
            );
        }

        uint256 balanceBefore = _balanceOf(tokenOut, receiver);
        uint256 ethValue = tokenIn == address(0) ? givenAmount : 0;

        // Execute the swap by forwarding calldata to target contract
        // slither-disable-next-line unused-return
        targetContract.functionCallWithValue(finalCalldata, ethValue);

        uint256 balanceAfter = _balanceOf(tokenOut, receiver);
        calculatedAmount = balanceAfter - balanceBefore;
    }

    /// @dev Decodes the packed calldata
    function _decodeData(
        bytes calldata data
    )
        internal
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
        // Minimum fixed fields before allowances:
        // tokenIn (20) + tokenOut (20) + transferType (1) + partialFillOffset (1) +
        // originalBaseTokenAmount (32) + numAllowances (1) = 75 bytes
        // Plus at minimum: targetContract (20) + receiver (20) = 40 bytes
        // Total minimum: 115 bytes (with 0 allowances)
        if (data.length < 115) revert LiquoriceExecutor__InvalidDataLength();

        tokenIn = address(bytes20(data[0:20]));
        tokenOut = address(bytes20(data[20:40]));
        transferType = TransferType(uint8(data[40]));
        partialFillOffset = uint8(data[41]);
        originalBaseTokenAmount = uint256(bytes32(data[42:74]));

        uint8 numAllowances = uint8(data[74]);

        // Each allowance: spender (20) + approvalNeeded (1) = 21 bytes
        uint256 allowancesEnd = 75 + (uint256(numAllowances) * 21);

        // Validate data length includes all allowances plus target, receiver, and at least some calldata
        if (data.length < allowancesEnd + 40) {
            revert LiquoriceExecutor__InvalidDataLength();
        }

        allowanceSpenders = new address[](numAllowances);
        approvalsNeeded = new bool[](numAllowances);

        for (uint256 i = 0; i < numAllowances; i++) {
            uint256 offset = 75 + (i * 21);
            allowanceSpenders[i] = address(bytes20(data[offset:offset + 20]));
            approvalsNeeded[i] = data[offset + 20] != 0;
        }

        targetContract = address(
            bytes20(data[allowancesEnd:allowancesEnd + 20])
        );
        receiver = address(
            bytes20(data[allowancesEnd + 20:allowancesEnd + 40])
        );
        liquoriceCalldata = data[allowancesEnd + 40:];
    }

    /// @dev Modifies the filledTakerAmount in the liquorice calldata to handle slippage
    /// @param liquoriceCalldata The original calldata for the liquorice settlement
    /// @param givenAmount The actual amount available from the router
    /// @param originalBaseTokenAmount The original amount expected when the quote was generated
    /// @param partialFillOffset The offset from Liquorice API indicating where the fill amount is located
    /// @return The modified calldata with updated fill amount
    function _modifyFilledTakerAmount(
        bytes memory liquoriceCalldata,
        uint256 givenAmount,
        uint256 originalBaseTokenAmount,
        uint8 partialFillOffset
    ) internal pure returns (bytes memory) {
        // Use the offset from Liquorice API to locate the fill amount
        // Position = 4 bytes (selector) + offset * 32 bytes
        uint256 fillAmountPos = 4 + uint256(partialFillOffset) * 32;

        // Cap the fill amount at what we actually have available
        uint256 newFillAmount = originalBaseTokenAmount > givenAmount
            ? givenAmount
            : originalBaseTokenAmount;

        // If the new fill amount is the same as the original, return the original calldata
        if (newFillAmount == originalBaseTokenAmount) {
            return liquoriceCalldata;
        }

        // Use assembly to modify the fill amount at the correct position
        // slither-disable-next-line assembly
        assembly {
            // Get pointer to the data portion of the bytes array
            let dataPtr := add(liquoriceCalldata, 0x20)

            // Calculate the actual position and store the new value
            let actualPos := add(dataPtr, fillAmountPos)
            mstore(actualPos, newFillAmount)
        }

        return liquoriceCalldata;
    }

    /// @dev Returns the balance of a token or ETH for an account
    /// @param token The token address, or address(0) for ETH
    /// @param account The account to get the balance of
    /// @return The balance of the token or ETH for the account
    function _balanceOf(
        address token,
        address account
    ) internal view returns (uint256) {
        return
            token == address(0)
                ? account.balance
                : IERC20(token).balanceOf(account);
    }

    /// @dev Allow receiving ETH for settlement calls that require ETH
    receive() external payable {}
}
