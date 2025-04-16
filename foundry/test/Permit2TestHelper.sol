// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./Constants.sol";
import "@permit2/src/interfaces/ISignatureTransfer.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Permit2TestHelper is Constants {
    /**
     * @dev Handles the Permit2 approval process for Alice, allowing the TychoRouter contract
     *      to spend `amountIn` of `tokenIn` on her behalf.
     *
     * This function approves the Permit2 contract to transfer the specified token amount
     * and constructs a `PermitSingle` struct for the approval. It also generates a valid
     * EIP-712 signature for the approval using Alice's private key.
     *
     * @param tokenIn The address of the token being approved.
     * @param amountIn The amount of tokens to approve for transfer.
     * @return permitTransferFrom The `PermitTransferFrom` struct containing the approval details.
     * @return signature The EIP-712 signature for the approval.
     */
    function handlePermit2Approval(
        address tokenIn,
        address spender,
        uint256 amountIn
    )
        internal
        returns (ISignatureTransfer.PermitTransferFrom memory, bytes memory)
    {
        IERC20(tokenIn).approve(PERMIT2_ADDRESS, amountIn);
        ISignatureTransfer.PermitTransferFrom memory permitTransferFrom =
        ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: tokenIn,
                amount: uint160(amountIn)
            }),
            nonce: 0,
            deadline: uint48(block.timestamp + 1 days)
        });

        bytes memory signature =
            signPermit2(permitTransferFrom, ALICE_PK, spender);
        return (permitTransferFrom, signature);
    }

    /**
     * @dev Signs a Permit2 `permitTransferFrom` struct with the given private key.
     * @param permit The `PermitTransferFrom` struct to sign.
     * @param privateKey The private key of the signer.
     * @return The signature as a `bytes` array.
     */
    function signPermit2(
        ISignatureTransfer.PermitTransferFrom memory permit,
        uint256 privateKey,
        address spender
    ) internal view returns (bytes memory) {
        bytes32 _TOKEN_PERMISSIONS_TYPEHASH =
            keccak256("TokenPermissions(address token,uint256 amount)");

        bytes32 _PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
            "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
                ),
                keccak256("Permit2"),
                block.chainid,
                PERMIT2_ADDRESS
            )
        );

        bytes32 tokenPermissions =
            keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));
        bytes32 permitHash = keccak256(
            abi.encode(
                _PERMIT_TRANSFER_FROM_TYPEHASH,
                tokenPermissions,
                spender,
                permit.nonce,
                permit.deadline
            )
        );

        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", domainSeparator, permitHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        return abi.encodePacked(r, s, v);
    }
}
