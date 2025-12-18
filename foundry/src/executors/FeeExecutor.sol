// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {RestrictTransferFrom} from "../RestrictTransferFrom.sol";

error FeeExecutor__InvalidDataLength();
error FeeExecutor__FeeTooHigh();

/**
 * @title FeeExecutor
 * @notice Executor that deducts a fee from the swap amount and credits it to a fee receiver's vault
 * @dev This executor should be the last in a sequence to apply fees to the final output
 */
contract FeeExecutor is RestrictTransferFrom {
    uint16 private constant MAX_FEE_BPS = 5000; // 50% max

    constructor(address _permit2) RestrictTransferFrom(_permit2) {}

    /**
     * @dev Deducts a fee from the input amount and credits it to the fee receiver's vault
     * @param amountIn The input amount (before fee)
     * @param data Encoded fee parameters: feeBps (uint16) | feeReceiver (address) | token (address)
     * @return amountOut The output amount (after fee deduction)
     */
    function swap(uint256 amountIn, bytes calldata data)
        external
        returns (uint256 amountOut)
    {
        (uint16 feeBps, address feeReceiver, address token) = _decodeData(data);

        if (feeBps > MAX_FEE_BPS) {
            revert FeeExecutor__FeeTooHigh();
        }

        uint256 feeAmount = (amountIn * feeBps) / 10000;
        amountOut = amountIn - feeAmount;

        if (feeAmount > 0) {
            _creditVault(feeReceiver, token, feeAmount);
        }

        return amountOut;
    }

    /**
     * @dev Decodes fee parameters from calldata
     * @param data The encoded data
     * @return feeBps Fee in basis points (0-10000, where 10000 = 100%)
     * @return feeReceiver Address to receive the fee
     * @return token Token address for the fee
     */
    function _decodeData(bytes calldata data)
        internal
        pure
        returns (uint16 feeBps, address feeReceiver, address token)
    {
        // expected calldata layout
        // ---------------------
        // 0  | feeBps (uint16)
        // 2  | feeReceiver (address)
        // 22 | token (address)
        // 42 | EOF
        if (data.length != 42) {
            revert FeeExecutor__InvalidDataLength();
        }

        feeBps = uint16(bytes2(data[0:2]));
        feeReceiver = address(bytes20(data[2:22]));
        token = address(bytes20(data[22:42]));
    }
}
