use std::{str::FromStr, sync::Arc};

use alloy::{
    primitives::{aliases::U48, Address, Bytes as AlloyBytes, TxKind, U160},
    providers::{Provider, RootProvider},
    rpc::types::{TransactionInput, TransactionRequest},
    signers::{local::PrivateKeySigner, SignerSync},
    transports::BoxTransport,
};
use alloy_primitives::{ChainId, U256};
use alloy_sol_types::{eip712_domain, sol, SolStruct, SolValue};
use chrono::Utc;
use tokio::runtime::Runtime;
use tycho_core::Bytes;

use crate::encoding::{
    errors::EncodingError,
    evm::{
        approvals::protocol_approvals_manager::get_client,
        utils::{biguint_to_u256, bytes_to_address, encode_input},
    },
    user_approvals_manager::{Approval, UserApprovalsManager},
};

/// Struct for managing Permit2 operations, including encoding approvals and fetching allowance
/// data.
pub struct Permit2 {
    address: Address,
    client: Arc<RootProvider<BoxTransport>>,
    runtime: Runtime,
    signer: PrivateKeySigner,
    chain_id: ChainId,
}

/// Type alias for representing allowance data as a tuple of (amount, expiration, nonce). Used for
/// decoding
type Allowance = (U160, U48, U48); // (amount, expiration, nonce)
/// Expiration period for permits, set to 30 days (in seconds).
const PERMIT_EXPIRATION: u64 = 30 * 24 * 60 * 60;
/// Expiration period for signatures, set to 30 minutes (in seconds).
const PERMIT_SIG_EXPIRATION: u64 = 30 * 60;
const MAX_UINT48: U48 = U48::MAX;
const MAX_UINT160: U160 = U160::MAX;
const MAX_UINT256: U256 = U256::MAX;

sol! {
     #[derive(Debug)]
    struct PermitSingle {
        PermitDetails details;
        address spender;
        uint256 sigDeadline;
    }

    #[derive(Debug)]
    struct PermitDetails {
        address token;
        uint160 amount;
        uint48 expiration;
        uint48 nonce;
    }
}

#[allow(dead_code)]
impl Permit2 {
    pub fn new(signer: PrivateKeySigner, chain_id: ChainId) -> Result<Self, EncodingError> {
        let runtime = Runtime::new()
            .map_err(|_| EncodingError::FatalError("Failed to create runtime".to_string()))?;
        let client = runtime.block_on(get_client())?;
        Ok(Self {
            address: Address::from_str("0x000000000022D473030F116dDEE9F6B43aC78BA3")
                .map_err(|_| EncodingError::FatalError("Permit2 address not valid".to_string()))?,
            client,
            runtime,
            signer,
            chain_id,
        })
    }

    /// Fetches allowance data for a specific owner, spender, and token.
    fn get_existing_allowance(
        &self,
        owner: &Bytes,
        spender: &Bytes,
        token: &Bytes,
    ) -> Result<Allowance, EncodingError> {
        let args = (bytes_to_address(owner)?, bytes_to_address(token)?, bytes_to_address(spender)?);
        let data = encode_input("allowance(address,address,address)", args.abi_encode());
        let tx = TransactionRequest {
            to: Some(TxKind::from(self.address)),
            input: TransactionInput { input: Some(AlloyBytes::from(data)), data: None },
            ..Default::default()
        };

        let output = self
            .runtime
            .block_on(async { self.client.call(&tx).await });
        match output {
            Ok(response) => {
                let allowance: Allowance =
                    Allowance::abi_decode(&response, true).map_err(|_| {
                        EncodingError::FatalError(
                            "Failed to decode response for permit2 allowance".to_string(),
                        )
                    })?;
                Ok(allowance)
            }
            Err(err) => Err(EncodingError::RecoverableError(format!(
                "Call to permit 2 allowance method failed with error: {:?}",
                err
            ))),
        }
    }
}
impl UserApprovalsManager for Permit2 {
    /// Encodes multiple approvals into ABI-encoded data and signs them.
    fn encode_approvals(&self, approvals: Vec<Approval>) -> Result<Vec<Vec<u8>>, EncodingError> {
        let current_time = Utc::now()
            .naive_utc()
            .and_utc()
            .timestamp() as u64;

        let mut encoded_approvals = Vec::new();

        for approval in approvals {
            let (_, _, nonce) =
                self.get_existing_allowance(&approval.owner, &approval.spender, &approval.token)?;
            let expiration = U48::from(current_time + PERMIT_EXPIRATION);
            let sig_deadline = U256::from(current_time + PERMIT_SIG_EXPIRATION);
            let amount = U160::from(biguint_to_u256(&approval.amount));

            // validations
            assert!(MAX_UINT256 > sig_deadline, "signature deadline out of range");
            assert!(MAX_UINT48 > nonce, "nonce out of range");
            assert!(MAX_UINT160 > amount, "amount out of range");
            assert!(MAX_UINT48 > expiration, "expiration out of range");

            let details = PermitDetails {
                token: bytes_to_address(&approval.token)?,
                amount,
                expiration,
                nonce,
            };

            let permit_single = PermitSingle {
                details,
                spender: bytes_to_address(&approval.spender)?,
                sigDeadline: sig_deadline,
            };

            let domain = eip712_domain! {
                name: "Permit2",
                chain_id: self.chain_id,
                verifying_contract: self.address,
            };
            let hash = permit_single.eip712_signing_hash(&domain);
            let signature = self
                .signer
                .sign_hash_sync(&hash)
                .map_err(|e| {
                    EncodingError::FatalError(format!(
                        "Failed to sign permit2 approval with error: {}",
                        e
                    ))
                })?;
            let encoded =
                (bytes_to_address(&approval.owner)?, permit_single, signature.as_bytes().to_vec())
                    .abi_encode();
            encoded_approvals.push(encoded);
        }

        Ok(encoded_approvals)
    }
}

#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use alloy_primitives::{Uint, B256};
    use num_bigint::BigUint;

    use super::*;

    // These two implementations are to avoid comparing the expiration and sig_deadline fields
    // because they are timestamps
    impl PartialEq for PermitSingle {
        fn eq(&self, other: &Self) -> bool {
            if self.details != other.details {
                return false;
            }
            if self.spender != other.spender {
                return false;
            }
            true
        }
    }

    impl PartialEq for PermitDetails {
        fn eq(&self, other: &Self) -> bool {
            if self.token != other.token {
                return false;
            }
            if self.amount != other.amount {
                return false;
            }
            // Compare `nonce`
            if self.nonce != other.nonce {
                return false;
            }

            true
        }
    }

    #[test]
    fn test_get_allowance_data() {
        let signer = PrivateKeySigner::random();
        let manager = Permit2::new(signer, 1).unwrap();

        let token = Bytes::from_str("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48").unwrap();
        let owner = Bytes::from_str("0x2c6a3cd97c6283b95ac8c5a4459ebb0d5fd404f4").unwrap();
        let spender = Bytes::from_str("0xba12222222228d8ba445958a75a0704d566bf2c8").unwrap();

        let result = manager
            .get_existing_allowance(&owner, &spender, &token)
            .unwrap();
        assert_eq!(
            result,
            (Uint::<160, 3>::from(0), Uint::<48, 1>::from(0), Uint::<48, 1>::from(0))
        );
    }
    #[test]
    fn test_encode_approvals() {
        // Set up a mock private key for signing
        let private_key =
            B256::from_str("4c0883a69102937d6231471b5dbb6204fe512961708279feb1be6ae5538da033")
                .expect("Invalid private key");
        let signer = PrivateKeySigner::from_bytes(&private_key).expect("Failed to create signer");
        let permit2 = Permit2::new(signer, 1).expect("Failed to create Permit2");

        let owner = Bytes::from_str("0x2c6a3cd97c6283b95ac8c5a4459ebb0d5fd404f4").unwrap();
        let spender = Bytes::from_str("0xba12222222228d8ba445958a75a0704d566bf2c8").unwrap();
        let token = Bytes::from_str("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48").unwrap();
        let amount = BigUint::from(1000u64);
        let approvals =
            vec![Approval { owner, spender, token: token.clone(), amount: amount.clone() }];

        let encoded_approvals = permit2
            .encode_approvals(approvals)
            .unwrap();
        assert_eq!(encoded_approvals.len(), 1, "Expected 1 encoded approval");

        let encoded = &encoded_approvals[0];

        // Remove prefix and owner (first 64 bytes) and signature (last 65 bytes)
        let permit_single_encoded = &encoded[64..encoded.len() - 65];

        let decoded_permit_single = PermitSingle::abi_decode(permit_single_encoded, false)
            .expect("Failed to decode PermitSingle");

        let expected_details = PermitDetails {
            token: bytes_to_address(&token).unwrap(),
            amount: U160::from(biguint_to_u256(&amount)),
            expiration: U48::from(Utc::now().timestamp() as u64 + PERMIT_EXPIRATION),
            nonce: U48::from(0),
        };
        let expected_permit_single = PermitSingle {
            details: expected_details,
            spender: Address::from_str("0xba12222222228d8ba445958a75a0704d566bf2c8").unwrap(),
            sigDeadline: U256::from(Utc::now().timestamp() as u64 + PERMIT_SIG_EXPIRATION),
        };

        assert_eq!(
            decoded_permit_single, expected_permit_single,
            "Decoded PermitSingle does not match expected values"
        );
    }

    /// This test actually calls the permit method on the Permit2 contract to verify the encoded
    /// data works. It requires an Anvil fork, so please run with the following command: anvil
    /// --fork-url <RPC-URL> And set up the following env var as ETH_RPC_URL=127.0.0.1:8545
    /// Use an account from anvil to fill the anvil_account and anvil_private_key variables
    #[test]
    #[cfg_attr(not(feature = "fork-tests"), ignore)]
    fn test_permit() {
        let anvil_account = Bytes::from_str("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266").unwrap();
        let anvil_private_key =
            B256::from_str("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")
                .unwrap();

        let signer =
            PrivateKeySigner::from_bytes(&anvil_private_key).expect("Failed to create signer");
        let permit2 = Permit2::new(signer, 1).expect("Failed to create Permit2");

        let token = Bytes::from_str("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48").unwrap();
        let amount = BigUint::from(1000u64);

        // Approve token allowance for permit2 contract
        let approve_function_signature = "approve(address,uint256)";
        let args = (permit2.address, biguint_to_u256(&BigUint::from(1000000u64)));
        let data = encode_input(approve_function_signature, args.abi_encode());

        let tx = TransactionRequest {
            to: Some(TxKind::from(bytes_to_address(&token).unwrap())),
            input: TransactionInput { input: Some(AlloyBytes::from(data)), data: None },
            ..Default::default()
        };
        let receipt = permit2.runtime.block_on(async {
            let pending_tx = permit2
                .client
                .send_transaction(tx)
                .await
                .unwrap();
            // Wait for the transaction to be mined
            pending_tx.get_receipt().await.unwrap()
        });
        assert!(receipt.status(), "Approve transaction failed");

        let spender = Bytes::from_str("0xba12222222228d8ba445958a75a0704d566bf2c8").unwrap();
        let approvals = vec![Approval {
            owner: anvil_account.clone(),
            spender: spender.clone(),
            token: token.clone(),
            amount: amount.clone(),
        }];

        let encoded_approvals = permit2
            .encode_approvals(approvals)
            .unwrap();

        let encoded = &encoded_approvals[0];

        let function_signature =
            "permit(address,((address,uint160,uint48,uint48),address,uint256),bytes)";
        let data = encode_input(function_signature, encoded.to_vec());

        let tx = TransactionRequest {
            to: Some(TxKind::from(permit2.address)),
            input: TransactionInput { input: Some(AlloyBytes::from(data)), data: None },
            gas: Some(10_000_000u64),
            ..Default::default()
        };

        let result = permit2.runtime.block_on(async {
            let pending_tx = permit2
                .client
                .send_transaction(tx)
                .await
                .unwrap();
            pending_tx.get_receipt().await.unwrap()
        });
        assert!(result.status(), "Permit transaction failed");

        // Assert that the allowance was set correctly in the permit2 contract
        let (allowance_amount, _, nonce) = permit2
            .get_existing_allowance(&anvil_account, &spender, &token)
            .unwrap();
        assert_eq!(allowance_amount, U160::from(biguint_to_u256(&amount)));
        assert_eq!(nonce, U48::from(1));
    }
}
