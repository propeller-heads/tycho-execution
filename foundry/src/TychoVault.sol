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
error TychoVault__UnexpectedInputDelta(int256 inputDelta);

/**
 * @title TychoVault - ERC6909-compliant multi-token vault
 * @dev Implements ERC6909 for managing user token balances within the router.
 * Users can deposit tokens, use them for swaps, and withdraw them.
 * Leftover funds from swaps are automatically credited to user balances.
 */
abstract contract TychoVault is ERC6909, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Vault balances - using our own mapping to avoid expensive Transfer events from ERC6909
    mapping(address => mapping(uint256 => uint256)) private _vaultBalances;

    // Transient storage slots for tracking deltas during swap sequences
    // keccak256("TychoVault#NEGATIVE_DELTA_COUNT")
    uint256 private constant _NEGATIVE_DELTA_COUNT_SLOT =
        0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b;

    event VaultDeposit(
        address indexed user, address indexed token, uint256 amount
    );
    event VaultWithdrawal(
        address indexed user, address indexed token, uint256 amount
    );

    /**
     * @dev Override balanceOf to use our own mapping instead of ERC6909's
     * This avoids expensive Transfer events on _mint and _burn
     */
    function balanceOf(address owner, uint256 id)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _vaultBalances[owner][id];
    }

    /**
     * @dev Override _update to use our own mapping and avoid emitting Transfer events
     * This is called by all balance-changing operations (transfer, approve, etc.)
     */
    function _update(address from, address to, uint256 id, uint256 amount)
        internal
        virtual
        override
    {
        if (from != address(0)) {
            _vaultBalances[from][id] -= amount;
        }
        if (to != address(0)) {
            _vaultBalances[to][id] += amount;
        }
        // Note: We intentionally do NOT emit Transfer events to save gas
    }

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
     * @dev Internal helper to get transient storage slot for a token delta
     * @notice Only needs token since transient storage is scoped to current transaction's sender
     */
    function _getDeltaSlot(address token)
        private
        pure
        returns (uint256 slot)
    {
        // Generate unique slot: keccak256(token, "TychoVault#DELTA")
        slot = uint256(
            keccak256(abi.encodePacked(token, "TychoVault#DELTA"))
        );
    }

    /**
     * @dev Get the current delta from transient storage
     * @notice Retrieves delta for current transaction's sender
     */
    // Assembly required for transient storage operations (tload)
    // slither-disable-next-line assembly
    function _getTDelta(address token)
        private
        view
        returns (int256 delta)
    {
        uint256 slot = _getDeltaSlot(token);
        assembly {
            delta := tload(slot)
        }
    }

    /**
     * @dev Set the delta in transient storage
     * @notice Sets delta for current transaction's sender
     */
    // Assembly required for transient storage operations (tstore)
    // slither-disable-next-line assembly
    function _setTDelta(address token, int256 delta) private {
        uint256 slot = _getDeltaSlot(token);
        assembly {
            tstore(slot, delta)
        }
    }

    /**
     * @dev Get negative delta count from transient storage
     */
    // Assembly required for transient storage operations (tload)
    // slither-disable-next-line assembly
    function _getNegativeDeltaCount() private view returns (uint256 count) {
        assembly {
            count := tload(_NEGATIVE_DELTA_COUNT_SLOT)
        }
    }

    /**
     * @dev Set negative delta count in transient storage
     */
    // Assembly required for transient storage operations (tstore)
    // slither-disable-next-line assembly
    function _setNegativeDeltaCount(uint256 count) private {
        assembly {
            tstore(_NEGATIVE_DELTA_COUNT_SLOT, count)
        }
    }

    /**
     * @dev Update delta accounting (transient storage)
     * @notice This updates the transient delta for the current sender, not the persistent vault balance
     * @param token The token to update
     * @param deltaChange The change to apply (positive to credit, negative to debit)
     */
    function _updateDeltaAccounting(
        address token,
        int256 deltaChange
    ) internal virtual {
        if (deltaChange == 0) return;

        int256 oldDelta = _getTDelta(token);
        int256 newDelta = oldDelta + deltaChange;

        // Update negative delta counter based on transitions
        if (oldDelta < 0 && newDelta >= 0) {
            // Was negative, now non-negative: decrement counter
            _setNegativeDeltaCount(_getNegativeDeltaCount() - 1);
        } else if (oldDelta >= 0 && newDelta < 0) {
            // Was non-negative, now negative: increment counter
            _setNegativeDeltaCount(_getNegativeDeltaCount() + 1);
        }

        _setTDelta(token, newDelta);
    }

    /**
     * @dev Internal helper to debit user's actual vault balance (persistent storage)
     * @notice This debits the persistent vault balance, not the transient delta
     */
    function _debitVault(address user, address token, uint256 amount)
        internal
        virtual
    {
        if (amount == 0) return;

        uint256 id = uint256(uint160(token));
        uint256 balance = balanceOf(user, id);
        if (balance < amount) {
            revert TychoVault__InsufficientBalance(user, token, amount, balance);
        }
        _burn(user, id, amount);
    }

    function _creditVault(address user, address token, uint256 amount)
        internal
        virtual
    {
        if (amount == 0) return;
        uint256 id = uint256(uint160(token));
        _mint(user, id, amount);
    }

    /**
     * @dev Finalize all transient deltas to persistent storage
     * @dev Verifies that only the input token has a negative delta and burns the vault balance
     * @param user The user whose deltas should be finalized
     * @param inputToken The expected input token
     * @param inputAmount The expected input amount
     */
    function _finalizeBalances(
        address user,
        address inputToken,
        uint256 inputAmount
    ) internal {
        uint256 negativeCount = _getNegativeDeltaCount();

        // Check that there is only one negative delta: the input token
        if (negativeCount > 1) {
            revert TychoVault__UnexpectedNegativeDelta(negativeCount);
        } else if (negativeCount == 1) {
            int256 inputDelta = _getTDelta(inputToken);
            if (inputDelta != -int256(inputAmount)) {
                revert TychoVault__UnexpectedInputDelta(inputDelta);
            }
            uint256 id = uint256(uint160(inputToken));
            _burn(user, id, uint256(-inputDelta));
        }
    }

    /**
     * @dev Gets balance of a token for a given address. Supports both native ETH and ERC20 tokens.
     */
    function _balanceOf(address token, address owner)
        internal
        view
        virtual
        returns (uint256)
    {
        return token == address(0)
            ? owner.balance
            : IERC20(token).balanceOf(owner);
    }
}
