// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./TychoVault.sol";

error TychoFees__InvalidFeePercentage(uint256 feePercentage);
error TychoFees__InvalidReceiverForFee(
    address expectedReceiver, uint256 expectedAmount, uint256 actualAmount
);
error TychoFees__FeeExceedsAmount(uint256 fee, uint256 amount);
error TychoFees__AmountOutNotFullyReceived(
    uint256 amountReceived, uint256 amountExpected
);

/**
 * @title TychoFees - Fee management for swaps
 * @dev Allows users to set fee percentages for their swaps. When a user with a fee
 * performs a swap, the output must be sent to the router first, then the fee is deducted
 * and the remainder is sent to the user.
 */
abstract contract TychoFees is AccessControl, TychoVault {
    using SafeERC20 for IERC20;

    // Mapping: user address => fee percentage in basis points (100 = 1%, 10000 = 100%)
    mapping(address => uint256) private _feePercentages;

    // Maximum fee percentage: 50% (5000 basis points)
    uint256 public constant MAX_FEE_PERCENTAGE = 5000;

    // Fee precision: 10000 basis points = 100%
    uint256 public constant FEE_BASIS_POINTS = 10000;

    // Role for setting fees
    bytes32 public constant FEE_SETTER_ROLE = keccak256("FEE_SETTER_ROLE");

    event FeePercentageSet(
        address indexed user, uint256 oldPercentage, uint256 newPercentage
    );

    /**
     * @notice Set the fee percentage for a user
     * @param user The user address
     * @param feePercentage The fee percentage in basis points (100 = 1%)
     */
    function setFeePercentage(address user, uint256 feePercentage)
        external
        onlyRole(FEE_SETTER_ROLE)
    {
        if (feePercentage > MAX_FEE_PERCENTAGE) {
            revert TychoFees__InvalidFeePercentage(feePercentage);
        }

        uint256 oldPercentage = _feePercentages[user];
        _feePercentages[user] = feePercentage;

        emit FeePercentageSet(user, oldPercentage, feePercentage);
    }

    /**
     * @notice Get the fee percentage for a user
     * @param user The user address
     * @return The fee percentage in basis points
     */
    function getFeePercentage(address user) external view returns (uint256) {
        return _feePercentages[user];
    }

    /**
     * @dev Internal function to check if a user has a fee set
     */
    function _hasFee(address user) internal view returns (bool) {
        return _feePercentages[user] > 0;
    }

    /**
     * @dev Handle fee collection and transfer to user
     * @param tokenOut The output token
     * @param unwrapEth Whether to unwrap ETH
     * @param balanceBefore The router's balance before the swap
     * @param amountOut The amount received from the swap
     * @param receiver The final receiver
     * @return finalAmount The amount after fee (if any)
     */
    function _handleFeeAndTransfer(
        address tokenOut,
        bool unwrapEth,
        uint256 balanceBefore,
        uint256 amountOut,
        address receiver
    ) internal returns (uint256 finalAmount) {
        bool hasFee = _hasFee(msg.sender);

        if (hasFee) {
            address tokenToCheck = unwrapEth ? _getWethAddress() : tokenOut;
            // Validate that the router received the full amountOut
            _validateFeeReceiver(tokenToCheck, balanceBefore, amountOut);

            // Deduct fee and get amount after fee
            if (unwrapEth) {
                _unwrapETH(amountOut);
                finalAmount = _deductFeeAndTransfer(receiver, address(0), amountOut);
            } else {
                finalAmount = _deductFeeAndTransfer(receiver, tokenOut, amountOut);
            }
        } else {
            // No fee - current behavior
            finalAmount = amountOut;
            if (unwrapEth) {
                _unwrapETH(amountOut);
                Address.sendValue(payable(receiver), amountOut);
            }
        }
    }

    /**
     * @dev Abstract function for WETH unwrapping - implemented by child contract
     */
    function _unwrapETH(uint256 amount) internal virtual;

    /**
     * @dev Abstract function to get WETH address - implemented by child contract
     */
    function _getWethAddress() internal view virtual returns (address);

    /**
     * @dev Abstract function to get balance of a token for an address - implemented by child contract
     * @param token The token address (address(0) for native ETH)
     * @param owner The address to check balance for
     * @return The token balance
     */
    function _balanceOf(address token, address owner)
        internal
        view
        virtual
        returns (uint256);

    /**
     * @dev Internal function to validate that the swap output was sent to the router
     * @param token The output token
     * @param balanceBefore Router's balance before the swap
     * @param amountOut The amount returned by the swap
     */
    function _validateFeeReceiver(
        address token,
        uint256 balanceBefore,
        uint256 amountOut
    ) internal view {
        uint256 balanceAfter = _balanceOf(token, address(this));
        uint256 actualReceived = balanceAfter - balanceBefore;

        if (actualReceived != amountOut) {
            // Receiver of final swap was likely incorrectly specified.
            // In order to enable fees, the TychoRouter must be the receiver of the
            // final swap.
            revert TychoFees__InvalidReceiverForFee(
                address(this), amountOut, actualReceived
            );
        }
    }

    /**
     * @dev Internal function to deduct fee and transfer remainder to receiver
     * @param receiver The address to receive the amount after fee
     * @param token The token address
     * @param amount The total amount before fee
     * @return amountAfterFee The amount after deducting the fee
     */
    function _deductFeeAndTransfer(address receiver, address token, uint256 amount)
        internal
        returns (uint256 amountAfterFee)
    {
        // Check fee percentage for msg.sender (the caller/fee payer)
        uint256 feePercentage = _feePercentages[msg.sender];
        if (feePercentage == 0) {
            // No fee, transfer entire amount to receiver
            _transferToken(token, receiver, amount);
            return amount;
        }

        // Calculate fee
        uint256 fee = (amount * feePercentage) / FEE_BASIS_POINTS;
        if (fee >= amount) {
            revert TychoFees__FeeExceedsAmount(fee, amount);
        }

        amountAfterFee = amount - fee;

        // Credit fee to msg.sender's vault
        _creditUserVault(msg.sender, token, fee);

        // Transfer remainder to receiver
        _transferToken(token, receiver, amountAfterFee);
    }

    /**
     * @dev Verifies that the expected amount of output tokens was received by the receiver.
     * Checks that receiver received the amount after fee (if applicable).
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @param initialBalanceReceiver The receiver's initial balance
     * @param amountOut The amount received (after fee if applicable)
     * @param receiver The intended receiver
     * @param amountIn The input amount
     */
    function _verifyAmountOutWasReceived(
        address tokenIn,
        address tokenOut,
        uint256 initialBalanceReceiver,
        uint256 amountOut,
        address receiver,
        uint256 amountIn
    ) internal view {
        uint256 currentBalance = _balanceOf(tokenOut, receiver);
        uint256 initialBalance = initialBalanceReceiver;

        if (tokenIn == tokenOut) {
            // If it is an arbitrage, we need to remove the amountIn from the initial balance
            initialBalance -= amountIn;
        }

        uint256 userAmount = currentBalance - initialBalance;
        if (userAmount != amountOut) {
            revert TychoFees__AmountOutNotFullyReceived(userAmount, amountOut);
        }
    }

    /**
     * @dev Helper function to transfer tokens
     */
    function _transferToken(address token, address to, uint256 amount)
        internal
    {
        if (token == address(0)) {
            Address.sendValue(payable(to), amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

}
