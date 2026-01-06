// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC6909/ERC6909.sol";

error TychoVault__InsufficientBalance(
    address user, address token, uint256 requested, uint256 available
);
error TychoVault__AmountZero();
error TychoVault__UnexpectedNegativeDelta(uint256 negativeCount);
error TychoVault__InvalidInputDelta(
    address token, int256 expected, int256 actual
);

/**
 * @title TychoVault - ERC6909-compliant multi-token vault
 * @dev Implements ERC6909 for managing user token balances within the router.
 * Users can deposit tokens, use them for swaps, and withdraw them.
 * Leftover funds from swaps are automatically credited to user balances.
 */
abstract contract TychoVault is ERC6909, ReentrancyGuard {
    using SafeERC20 for IERC20;

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

        uint256 id = uint256(uint160(token));

        if (token == address(0)) {
            // Native ETH deposit
            require(msg.value == amount, "Value mismatch");
            _mint(msg.sender, id, amount);
        } else {
            // ERC20 deposit - transfer to this contract (router)
            _mint(msg.sender, id, amount);
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

        uint256 id = uint256(uint160(token));
        uint256 balance = balanceOf(msg.sender, id);
        if (balance < amount) {
            revert TychoVault__InsufficientBalance(
                msg.sender, token, amount, balance
            );
        }

        _burn(msg.sender, id, amount);

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
     * @dev Update delta accounting (transient storage)
     * @notice This updates the transient delta, not the persistent vault balance
     * @param user The user whose delta to update
     * @param token The token to update
     * @param deltaChange The change to apply (positive to credit, negative to debit)
     */
    function _updateDeltaAccounting(address user, address token, int256 deltaChange)
        internal
        virtual
    {
        if (deltaChange == 0) return;

        int256 oldDelta = _getTDelta(user, token);
        int256 newDelta = oldDelta + deltaChange;

        // Update negative delta counter based on transitions
        if (oldDelta < 0 && newDelta >= 0) {
            // Was negative, now non-negative: decrement counter
            _setNegativeDeltaCount(_getNegativeDeltaCount() - 1);
        } else if (oldDelta >= 0 && newDelta < 0) {
            // Was non-negative, now negative: increment counter
            _setNegativeDeltaCount(_getNegativeDeltaCount() + 1);
        }

        _setTDelta(user, token, newDelta);
    }

    /**
     * @dev Internal helper to debit user's actual vault balance (persistent storage)
     * @notice This debits the persistent vault balance, not the transient delta
     */
    function _debitPersistentVault(address user, address token, uint256 amount)
        internal
        virtual
    {
        if (amount == 0) return;

        uint256 id = uint256(uint160(token));
        uint256 balance = balanceOf(user, id);
        if (balance < amount) {
            revert TychoVault__InsufficientBalance(
                user, token, amount, balance
            );
        }
        _burn(user, id, amount);
    }

    /**
     * @dev Settle all transient deltas to persistent storage
     * @param user The user whose deltas should be settled
     * @param inputToken The expected input token
     * @param inputAmount The expected input amount
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

        // Check that there are no negative deltas
        if (negativeCount > 0) {
            // We aren't sure exactly which token(s) caused the negative count, since
            // we don't track this information for gas purposes.
            revert TychoVault__UnexpectedNegativeDelta(negativeCount);
        }

        // Calculate surplus output (delta minus amount being sent to receiver)
        int256 outputDelta = _getTDelta(user, outputToken);
        if (outputDelta > 0) {
            int256 surplus = outputDelta - int256(outputAmount);
            // Only credit surplus if above dust threshold
            if (surplus > 0 && uint256(surplus) > DUST_THRESHOLD) {
                uint256 id = uint256(uint160(outputToken));
                _mint(user, id, uint256(surplus));
            }
        }

        // Also settle router's delta (from fees) to persistent vault
        // Router's delta should be fully credited since it's not being sent to receiver
        if (user != address(this)) {
            int256 routerDelta = _getTDelta(address(this), outputToken);
            if (routerDelta > 0 && uint256(routerDelta) > DUST_THRESHOLD) {
                uint256 id = uint256(uint160(outputToken));
                _mint(address(this), id, uint256(routerDelta));
            }
        }
    }
}
