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
     * @notice Get vault balance for a user and token
     * @param user The user address
     * @param token The token address
     * @return The vault balance
     */
    function vaultBalanceOf(address user, address token)
        external
        view
        returns (uint256)
    {
        return _vaultBalances[user][token];
    }

    /**
     * @dev Internal function to credit leftover funds to user's vault
     */
    function _creditUserVault(address user, address token, uint256 amount)
        internal
        virtual
    {
        if (amount == 0) return;
        _vaultBalances[user][token] += amount;
    }

    /**
     * @dev Internal helper to debit user's vault balance
     * @notice Used by TychoRouter's _debitVault override
     */
    function _debitUserVaultBalance(address user, address token, uint256 amount)
        internal
    {
        uint256 balance = _vaultBalances[user][token];
        if (balance < amount) {
            revert TychoVault__InsufficientBalance(user, token, amount, balance);
        }
        _vaultBalances[user][token] = balance - amount;
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
