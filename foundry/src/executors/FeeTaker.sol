// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {RestrictTransferFrom} from "../RestrictTransferFrom.sol";
import {TychoVault} from "../TychoVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error FeeTaker__InvalidDataLength();
error FeeTaker__FeeTooHigh();

/**
 * @title FeeTaker
 * @notice Executor that deducts fees from the swap amount and credits them to fee receivers' vaults
 * @dev Handles both solution-specific fees and router platform fees
 * @dev This executor is called mandatorily after each swap sequence
 */
contract FeeTaker is RestrictTransferFrom, TychoVault {
    using SafeERC20 for IERC20;

    uint16 private constant MAX_FEE_BPS = 5000; // 50% max

    constructor(address _permit2) RestrictTransferFrom(_permit2) {}

    /**
     * @dev Override to resolve multiple inheritance
     */
    function _updateDeltaAccounting(
        address token,
        int256 deltaChange
    ) internal override(RestrictTransferFrom, TychoVault) {
        super._updateDeltaAccounting(token, deltaChange);
    }

    /**
     * @dev Override to resolve multiple inheritance
     */
    // Required to resolve multiple inheritance between RestrictTransferFrom and TychoVault
    // slither-disable-next-line dead-code
    function _debitVault(address user, address token, uint256 amount)
        internal
        override(RestrictTransferFrom, TychoVault)
    {
        super._debitVault(user, token, amount);
    }

    /**
     * @dev Deducts fees from the input amount and credits them to fee receivers' vaults
     * @dev Note: Does NOT transfer to receiver - caller must handle that after checking for solver subsidy
     * @param amountIn The input amount (before fees)
     * @param data Encoded fee parameters:
     *        solverFeeBps (uint16) | solverFeeReceiver (address) |
     *        routerFeeOnOutputBps (uint16) | routerFeeOnSolverFeeBps (uint16) |
     *        routerFeeReceiver (address) | token (address)
     * @return amountOut The output amount (after fee deductions)
     */
    function takeFee(uint256 amountIn, bytes calldata data)
        external
        returns (uint256 amountOut)
    {
        (
            uint16 solverFeeBps,
            address solverFeeReceiver,
            uint16 routerFeeOnOutputBps,
            uint16 routerFeeOnSolverFeeBps,
            address routerFeeReceiver,
            address token
        ) = _decodeData(data);

        if (
            solverFeeBps > MAX_FEE_BPS || routerFeeOnOutputBps > MAX_FEE_BPS
                || routerFeeOnSolverFeeBps > MAX_FEE_BPS
        ) {
            revert FeeTaker__FeeTooHigh();
        }

        amountOut = amountIn;
        uint256 solverFee = 0;

        // Deduct solution fee if > 0
        if (solverFeeBps > 0) {
            solverFee = (amountOut * solverFeeBps) / 10000;
            amountOut -= solverFee;
            _updateDeltaAccounting(token, -int256(solverFee));
            _creditVault(solverFeeReceiver, token, solverFee);
        }

        uint256 totalRouterFeesTaken = 0;
        // Deduct router fee on output amount if > 0
        if (routerFeeOnOutputBps > 0) {
            uint256 routerFeeOnOutput =
                (amountOut * routerFeeOnOutputBps) / 10000;
            amountOut -= routerFeeOnOutput;
            totalRouterFeesTaken += routerFeeOnOutput;
        }

        // Deduct router fee on solver fee if > 0 (calculated from solution fee)
        if (routerFeeOnSolverFeeBps > 0 && solverFee > 0) {
            uint256 routerFeeOnSolverFee =
                (solverFee * routerFeeOnSolverFeeBps) / 10000;
            amountOut -= routerFeeOnSolverFee;
            totalRouterFeesTaken += routerFeeOnSolverFee;
        }

        if (totalRouterFeesTaken > 0) {
            _updateDeltaAccounting(token, -int256(totalRouterFeesTaken));
            _creditVault(routerFeeReceiver, token, totalRouterFeesTaken);
        }

        return amountOut;
    }

    /**
     * @dev Decodes fee parameters from calldata
     * @param data The encoded data
     * @return solverFeeBps Solution fee in basis points
     * @return solverFeeReceiver Address to receive the solution fee
     * @return routerFeeOnOutputBps Router fee on output amount in basis points
     * @return routerFeeOnSolverFeeBps Router fee on solver fee in basis points
     * @return routerFeeReceiver Address to receive the router fee
     * @return token Token address for the fees
     */
    function _decodeData(bytes calldata data)
        internal
        pure
        returns (
            uint16 solverFeeBps,
            address solverFeeReceiver,
            uint16 routerFeeOnOutputBps,
            uint16 routerFeeOnSolverFeeBps,
            address routerFeeReceiver,
            address token
        )
    {
        // expected calldata layout
        // ---------------------
        // 0  | solverFeeBps (uint16)
        // 2  | solverFeeReceiver (address)
        // 22 | routerFeeOnOutputBps (uint16)
        // 24 | routerFeeOnSolverFeeBps (uint16)
        // 26 | routerFeeReceiver (address)
        // 46 | token (address)
        // 66 | EOF
        if (data.length != 66) {
            revert FeeTaker__InvalidDataLength();
        }

        solverFeeBps = uint16(bytes2(data[0:2]));
        solverFeeReceiver = address(bytes20(data[2:22]));
        routerFeeOnOutputBps = uint16(bytes2(data[22:24]));
        routerFeeOnSolverFeeBps = uint16(bytes2(data[24:26]));
        routerFeeReceiver = address(bytes20(data[26:46]));
        token = address(bytes20(data[46:66]));
    }
}

