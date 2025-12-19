// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IERC6909.sol";

error TychoVault__InsufficientBalance(
    address user, address token, uint256 requested, uint256 available
);
error TychoVault__AmountZero();
error TychoVault__UnexpectedNegativeDelta(address token, int256 delta);
error TychoVault__InvalidInputDelta(
    address token, int256 expected, int256 actual
);

/**
 * @title TychoVault - ERC6909-compliant multi-token vault
 * @dev Implements ERC6909 for managing user token balances within the router.
 * Users can deposit tokens, use them for swaps, and withdraw them.
 * Leftover funds from swaps are automatically credited to user balances.
 */
abstract contract TychoVault is IERC6909, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ERC6909 Vault storage: user => token => balance
    mapping(address => mapping(address => uint256)) private _vaultBalances;

    // Transient storage slots for tracking deltas during swap sequences
    // keccak256("TychoVault#NEGATIVE_DELTA_COUNT")
    uint256 private constant _NEGATIVE_DELTA_COUNT_SLOT =
        0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b;

    uint256 private constant DUST_THRESHOLD = 100;

    event VaultDeposit(
        address indexed user, address indexed token, uint256 amount
    );
    event VaultWithdrawal(
        address indexed user, address indexed token, uint256 amount
    );

    // ============ ERC6909 Vault Functions ============

    /**
     * @notice Deposit tokens into the vault for the caller
     * @param token The token address to deposit (use address(0) for native ETH)
     * @param amount The amount to deposit
     */
    function depositToVault(address token, uint256 amount)
        external
        payable
        nonReentrant
    {
        if (amount == 0) {
            revert TychoVault__AmountZero();
        }

        if (token == address(0)) {
            // Native ETH deposit
            require(msg.value == amount, "Value mismatch");
            _vaultBalances[msg.sender][token] += amount;
        } else {
            // ERC20 deposit - transfer to this contract (router)
            _vaultBalances[msg.sender][token] += amount;
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    /**
     * @notice Withdraw tokens from the vault
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     */
    function withdrawFromVault(address token, uint256 amount)
        external
        nonReentrant
    {
        if (amount == 0) {
            revert TychoVault__AmountZero();
        }

        uint256 balance = _vaultBalances[msg.sender][token];
        if (balance < amount) {
            revert TychoVault__InsufficientBalance(
                msg.sender, token, amount, balance
            );
        }

        _vaultBalances[msg.sender][token] = balance - amount;

        // Transfer tokens from contract to user
        if (token == address(0)) {
            Address.sendValue(payable(msg.sender), amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    /**
     * @dev Internal helper to get transient storage slot for a user/token delta
     */
    function _getDeltaSlot(address user, address token)
        private
        pure
        returns (uint256 slot)
    {
        // Generate unique slot: keccak256(user, token, "TychoVault#DELTA")
        slot = uint256(
            keccak256(abi.encodePacked(user, token, "TychoVault#DELTA"))
        );
    }

    /**
     * @dev Get the current delta from transient storage
     */
    function _getTDelta(address user, address token)
        private
        view
        returns (int256 delta)
    {
        uint256 slot = _getDeltaSlot(user, token);
        assembly {
            delta := tload(slot)
        }
    }

    /**
     * @dev Set the delta in transient storage
     */
    function _setTDelta(address user, address token, int256 delta) private {
        uint256 slot = _getDeltaSlot(user, token);
        assembly {
            tstore(slot, delta)
        }
    }

    /**
     * @dev Get negative delta count from transient storage
     */
    function _getNegativeDeltaCount() private view returns (uint256 count) {
        assembly {
            count := tload(_NEGATIVE_DELTA_COUNT_SLOT)
        }
    }

    /**
     * @dev Set negative delta count in transient storage
     */
    function _setNegativeDeltaCount(uint256 count) private {
        assembly {
            tstore(_NEGATIVE_DELTA_COUNT_SLOT, count)
        }
    }

    /**
     * @dev Internal function to credit leftover funds to user's vault
     * Now writes to transient storage instead of persistent storage
     */
    function _creditUserVault(address user, address token, uint256 amount)
        internal
        virtual
    {
        if (amount == 0) return;

        int256 oldDelta = _getTDelta(user, token);
        int256 newDelta = oldDelta + int256(amount);

        // If delta was negative and becomes non-negative, decrement counter
        if (oldDelta < 0 && newDelta >= 0) {
            _setNegativeDeltaCount(_getNegativeDeltaCount() - 1);
        }

        _setTDelta(user, token, newDelta);
    }

    /**
     * @dev Internal helper to debit user's vault balance
     * @notice Now writes to transient storage instead of persistent storage
     */
    function _debitUserVault(address user, address token, uint256 amount)
        internal
    {
        if (amount == 0) return;

        int256 oldDelta = _getTDelta(user, token);
        int256 newDelta = oldDelta - int256(amount);

        // If delta was non-negative and becomes negative, increment counter
        if (oldDelta >= 0 && newDelta < 0) {
            _setNegativeDeltaCount(_getNegativeDeltaCount() + 1);
        }

        _setTDelta(user, token, newDelta);
    }

    /**
     * @dev Settle all transient deltas to persistent storage
     * @param user The user whose deltas should be settled
     * @param inputToken The expected input token with negative delta
     * @param inputAmount The expected input amount (as negative delta)
     * @param outputToken The output token (may have positive delta)
     * @param outputAmount The amount being sent to receiver (not surplus)
     */
    function _settle(
        address user,
        address inputToken,
        uint256 inputAmount,
        address outputToken,
        uint256 outputAmount
    ) internal {
        uint256 negativeCount = _getNegativeDeltaCount();

        // Get input token delta
        int256 inputDelta = _getTDelta(user, inputToken);

        // Check if we have at most one negative delta (for the input token)
        if (negativeCount > 1) {
            revert TychoVault__UnexpectedNegativeDelta(inputToken, inputDelta);
        }

        if (negativeCount == 1) {
            // Verify the negative delta is for the input token
            // and that abs(delta) <= inputAmount (accounting for leftovers)
            if (inputDelta >= 0) {
                // If there's a negative delta, it should be the input token
                revert TychoVault__InvalidInputDelta(
                    inputToken, -int256(inputAmount), inputDelta
                );
            }
            // Check that we didn't debit more than inputAmount
            if (uint256(-inputDelta) > inputAmount) {
                revert TychoVault__InvalidInputDelta(
                    inputToken, -int256(inputAmount), inputDelta
                );
            }
        }
        // If negativeCount == 0, no validation needed - could be wallet-funded swap

        // Apply input token delta to persistent storage (only debit if negative)
        if (inputDelta < 0) {
            uint256 debitAmount = uint256(-inputDelta);
            uint256 balance = _vaultBalances[user][inputToken];
            if (balance < debitAmount) {
                revert TychoVault__InsufficientBalance(
                    user, inputToken, debitAmount, balance
                );
            }
            _vaultBalances[user][inputToken] = balance - debitAmount;
        }
        // If inputDelta >= 0, ignore it (shouldn't happen normally)

        // Calculate surplus output (delta minus amount being sent to receiver)
        int256 outputDelta = _getTDelta(user, outputToken);
        if (outputDelta > 0) {
            int256 surplus = outputDelta - int256(outputAmount);
            // Only credit surplus if above dust threshold
            if (surplus > 0 && uint256(surplus) > DUST_THRESHOLD) {
                _vaultBalances[user][outputToken] += uint256(surplus);
            }
        }

        // Clear transient storage for next swap
        _setTDelta(user, inputToken, 0);
        _setTDelta(user, outputToken, 0);
        _setNegativeDeltaCount(0);
    }

    // ============ IERC6909 Implementation ============
    // Note: We use address cast to uint256 as the token ID

    function balanceOf(address owner, uint256 id)
        external
        view
        override
        returns (uint256)
    {
        return _vaultBalances[owner][address(uint160(id))];
    }

    function allowance(address, address, uint256)
        external
        pure
        override
        returns (uint256)
    {
        // Not implemented - use standard ERC20 approvals
        return 0;
    }

    function isOperator(address, address)
        external
        pure
        override
        returns (bool)
    {
        // Not implemented
        return false;
    }

    function approve(address, uint256, uint256)
        external
        pure
        override
        returns (bool)
    {
        // Not implemented - use standard ERC20 approvals
        revert("Use ERC20 approve");
    }

    function setOperator(address, bool) external pure override returns (bool) {
        // Not implemented
        revert("Not implemented");
    }

    function transfer(address, uint256, uint256)
        external
        pure
        override
        returns (bool)
    {
        // Not implemented - vault balances are not transferable between users
        revert("Vault transfers not supported");
    }

    function transferFrom(
        address sender,
        address receiver,
        uint256 id,
        uint256 amount
    ) external pure override returns (bool) {
        // Not implemented - use standard ERC20 transferFrom
        revert("Use ERC20 transferFrom");
    }
}
