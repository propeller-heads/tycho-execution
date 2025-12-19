// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {RestrictTransferFrom} from "../RestrictTransferFrom.sol";
import {TychoVault} from "../TychoVault.sol";

error FeeExecutor__InvalidDataLength();
error FeeExecutor__FeeTooHigh();
error FeeExecutor__InsufficientVaultBalance(
    address user, address token, uint256 required, uint256 available
);

/**
 * @title FeeExecutor
 * @notice Executor that deducts fees from the swap amount and credits them to fee receivers' vaults
 * @dev Handles both solution-specific fees and router platform fees
 * @dev This executor is called mandatorily after each swap sequence
 */
contract FeeExecutor is RestrictTransferFrom, TychoVault {
    uint16 private constant MAX_FEE_BPS = 5000; // 50% max

    constructor(address _permit2) RestrictTransferFrom(_permit2) {}

    /**
     * @dev Deducts fees from the input amount and credits them to fee receivers' vaults
     * @dev Verifies msg.sender has sufficient balance in vault before deducting
     * @param amountIn The input amount (before fees)
     * @param data Encoded fee parameters:
     *        solutionFeeBps (uint16) | solutionFeeReceiver (address) |
     *        routerFeeBps (uint16) | routerFeeReceiver (address) | token (address)
     * @return amountOut The output amount (after fee deductions)
     */
    function take_fee(uint256 amountIn, bytes calldata data)
        external
        returns (uint256 amountOut)
    {
        (
            uint16 solutionFeeBps,
            address solutionFeeReceiver,
            uint16 routerFeeBps,
            address routerFeeReceiver,
            address token
        ) = _decodeData(data);

        if (solutionFeeBps > MAX_FEE_BPS || routerFeeBps > MAX_FEE_BPS) {
            revert FeeExecutor__FeeTooHigh();
        }

        // Verify msg.sender has sufficient balance in vault
        uint256 userVaultBalance = this.balanceOf(msg.sender, uint256(uint160(token)));
        if (userVaultBalance < amountIn) {
            revert FeeExecutor__InsufficientVaultBalance(
                msg.sender, token, amountIn, userVaultBalance
            );
        }

        amountOut = amountIn;

        // Deduct solution fee if > 0
        if (solutionFeeBps > 0) {
            uint256 solutionFee = (amountOut * solutionFeeBps) / 10000;
            amountOut -= solutionFee;
            _debitUserVault(msg.sender, token, solutionFee);
            _creditUserVault(solutionFeeReceiver, token, solutionFee);
        }

        // Deduct router fee if > 0
        if (routerFeeBps > 0) {
            uint256 routerFee = (amountOut * routerFeeBps) / 10000;
            amountOut -= routerFee;
            _debitUserVault(msg.sender, token, routerFee);
            _creditUserVault(routerFeeReceiver, token, routerFee);
        }

        return amountOut;
    }

    /**
     * @dev Decodes fee parameters from calldata
     * @param data The encoded data
     * @return solutionFeeBps Solution fee in basis points
     * @return solutionFeeReceiver Address to receive the solution fee
     * @return routerFeeBps Router fee in basis points
     * @return routerFeeReceiver Address to receive the router fee
     * @return token Token address for the fees
     */
    function _decodeData(bytes calldata data)
        internal
        pure
        returns (
            uint16 solutionFeeBps,
            address solutionFeeReceiver,
            uint16 routerFeeBps,
            address routerFeeReceiver,
            address token
        )
    {
        // expected calldata layout
        // ---------------------
        // 0  | solutionFeeBps (uint16)
        // 2  | solutionFeeReceiver (address)
        // 22 | routerFeeBps (uint16)
        // 24 | routerFeeReceiver (address)
        // 44 | token (address)
        // 64 | EOF
        if (data.length != 64) {
            revert FeeExecutor__InvalidDataLength();
        }

        solutionFeeBps = uint16(bytes2(data[0:2]));
        solutionFeeReceiver = address(bytes20(data[2:22]));
        routerFeeBps = uint16(bytes2(data[22:24]));
        routerFeeReceiver = address(bytes20(data[24:44]));
        token = address(bytes20(data[44:64]));
    }
}

