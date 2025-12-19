// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@interfaces/IExecutor.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@permit2/src/interfaces/IAllowanceTransfer.sol";
import "@openzeppelin/contracts/utils/Address.sol";

error RestrictTransferFrom__AddressZero();
error RestrictTransferFrom__ExceededTransferFromAllowance(
    uint256 allowedAmount, uint256 amountAttempted
);
error RestrictTransferFrom__DifferentTokenIn(
    address tokenIn, address tokenInStorage
);
error RestrictTransferFrom__UnknownTransferType();
error RestrictTransferFrom__InsufficientVaultBalance(
    address user, address token, uint256 requested, uint256 available
);

/**
 * @title RestrictTransferFrom - Restrict transferFrom upto allowed amount of token
 * @dev Restricts `transferFrom` (using `permit2` or regular `transferFrom`) upto
 * allowed amount of token in per swap, while ensuring that the `transferFrom` is
 * only performed on the input token upto input amount, from the msg.sender's wallet
 * that calls the main swap method. Reverts if `transferFrom`s are attempted above
 * this allowed amount.
 */
contract RestrictTransferFrom {
    using SafeERC20 for IERC20;

    IAllowanceTransfer public immutable permit2;
    // keccak256("RestrictTransferFrom#TOKEN_IN_SLOT")
    uint256 private constant _TOKEN_IN_SLOT =
        0x25712b2458c26c244401cacab2c4d40a337e6c15af51d98c87ca8c05ed74935f;
    // keccak256("RestrictTransferFrom#AMOUNT_ALLOWED_SLOT")
    uint256 private constant _AMOUNT_ALLOWED_SLOT =
        0x9042309497172c3d7a894cb22c754029d2b44522a8039afc41f7d5ad87a35cb5;
    // keccak256("RestrictTransferFrom#IS_PERMIT2_SLOT")
    uint256 private constant _IS_PERMIT2_SLOT =
        0x8b09772a37ddaa0009affae61f4c227f5ae294cb166289f28313bcce05ea5358;
    // keccak256("RestrictTransferFrom#SENDER_SLOT")
    uint256 private constant _SENDER_SLOT =
        0x6249046ac25ba4612871a1715b1abd1de7cf9c973c5045a9b08ce3f441ce6e3a;

    constructor(address _permit2) {
        if (_permit2 == address(0)) {
            revert RestrictTransferFrom__AddressZero();
        }
        permit2 = IAllowanceTransfer(_permit2);
    }

    /**
     * @dev Virtual function to update delta accounting - overridden by TychoRouter
     * @param deltaChange Positive to credit, negative to debit
     */
    function _updateDeltaAccounting(address user, address token, int256 deltaChange)
        internal
        virtual {
        // Empty implementation - only TychoRouter uses this
    }

    /**
     * @dev Virtual function to debit persistent vault balance - overridden by TychoRouter
     */
    function _debitPersistentVault(address user, address token, uint256 amount)
        internal
        virtual {
        // Empty implementation - only TychoRouter uses this
    }

    enum TransferType {
        TransferFromSender,
        TransferFromVault,
        FundsAlreadyInProtocol,
        ProtocolWillDebit,
        ProtocolWillDebitFromVault
    }

    /**
     * @dev This function is used to store the transfer information in the
     * contract's storage. This is done as the first step in the swap process in TychoRouter.
     */
    // slither-disable-next-line assembly
    function _tstoreTransferFromInfo(
        address tokenIn,
        uint256 amountIn,
        bool isPermit2,
        bool isTransferFromAllowed
    ) internal {
        uint256 amountAllowed = amountIn;
        if (!isTransferFromAllowed) {
            amountAllowed = 0;
        }
        assembly {
            tstore(_TOKEN_IN_SLOT, tokenIn)
            tstore(_AMOUNT_ALLOWED_SLOT, amountAllowed)
            tstore(_IS_PERMIT2_SLOT, isPermit2)
            tstore(_SENDER_SLOT, caller())
        }
    }

    /**
     * @dev This function is used to transfer the tokens from the sender to the receiver.
     * This function is called within the Executor contracts.
     * If the TransferType is TransferFrom, it will check if the amount is within the allowed amount and transfer those funds from the user.
     * If the TransferType is Transfer, it will transfer the funds from the TychoRouter to the receiver.
     * If the TransferType is TransferFromVault, it will debit the user's vault balance and transfer from the router (funds already there).
     * If the TransferType is None, it will debit the user's vault balance and expect the protocol to take care of any transfers.
     */
    // slither-disable-next-line assembly
    function _transfer(
        address receiver,
        TransferType transferType,
        address tokenIn,
        uint256 amount
    ) internal {
        if (transferType == TransferType.TransferFromSender) {
            address tokenInStorage;
            bool isPermit2;
            address sender;
            uint256 amountAllowed;
            // TODO double check this logic and add to the cases below where needed.
            //  This is still relevant to prevent badly encoded split swaps from taking
            //  more than the input amount out of the user's vault.
            assembly {
                tokenInStorage := tload(_TOKEN_IN_SLOT)
                amountAllowed := tload(_AMOUNT_ALLOWED_SLOT)
                isPermit2 := tload(_IS_PERMIT2_SLOT)
                sender := tload(_SENDER_SLOT)
            }
            if (amount > amountAllowed) {
                revert RestrictTransferFrom__ExceededTransferFromAllowance(
                    amountAllowed, amount
                );
            }
            if (tokenIn != tokenInStorage) {
                revert RestrictTransferFrom__DifferentTokenIn(
                    tokenIn, tokenInStorage
                );
            }
            amountAllowed -= amount;
            assembly {
                tstore(_AMOUNT_ALLOWED_SLOT, amountAllowed)
            }
            if (receiver == address(this)) {
              _updateDeltaAccounting(sender, tokenIn, int256(amount));
            }
            if (isPermit2) {
                // Permit2.permit is already called from the TychoRouter
                permit2.transferFrom(sender, receiver, uint160(amount), tokenIn);
            } else {
                // slither-disable-next-line arbitrary-send-erc20
                IERC20(tokenIn).safeTransferFrom(sender, receiver, amount);
            }
        } else if (transferType == TransferType.TransferFromVault) {
            address sender;
            assembly {
                sender := tload(_SENDER_SLOT)
            }
            // Debit the actual vault balance (persistent storage)
            _debitPersistentVault(sender, tokenIn, amount);

            // Credit the delta accounting (funds are now at the router) - positive amount to credit
            _updateDeltaAccounting(sender, tokenIn, int256(amount));

            // Transfer from router to receiver
            if (tokenIn == address(0)) {
                Address.sendValue(payable(receiver), amount);
            } else {
                IERC20(tokenIn).safeTransfer(receiver, amount);
            }
        } else if (transferType == TransferType.ProtocolWillDebit) {
            // Credit the delta accounting (funds are now at the router) - positive amount to credit
            _updateDeltaAccounting(sender, tokenIn, -int256(amount));
            // Protocol will pull funds from router via transferFrom
            // We don't transfer here, protocol does that
        } else if (transferType == TransferType.ProtocolWillDebitFromVault) {
            // TODO update the encoding to encode this type if Curve or Balancer is the
            //  first swap in the swap sequence.
            // Debit the actual vault balance (persistent storage)
            _debitPersistentVault(sender, tokenIn, int256(amount));
            // We don't credit the delta accounting since the funds land directly in
            // the protocol and don't pass through out router.
            // Protocol will pull funds from router via transferFrom
            // We don't transfer here, protocol does that
        } else if (transferType == TransferType.FundsAlreadyInProtocol) {
            // Funds were sent directly from the previous pool without passing through our router
            // Nothing to do here
            return;
        } else {
            revert RestrictTransferFrom__UnknownTransferType();
        }
    }
}
