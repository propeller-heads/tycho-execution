use std::{collections::HashMap, str::FromStr, sync::Arc};

use alloy::primitives::Address;
use serde::Deserialize;
use tokio::{
    runtime::{Handle, Runtime},
    task::block_in_place,
};
use tycho_common::{
    models::{protocol::GetAmountOutParams, Chain},
    Bytes,
};

use crate::encoding::{
    errors::EncodingError,
    evm::{
        approvals::protocol_approvals_manager::ProtocolApprovalsManager,
        utils::{bytes_to_address, get_runtime},
    },
    models::{EncodingContext, Swap},
    swap_encoder::SwapEncoder,
};

/// Allowance structure from Liquorice API
#[derive(Debug, Clone, Deserialize)]
struct LiquoriceAllowance {
    #[allow(dead_code)]
    token: String,
    spender: String,
    #[allow(dead_code)]
    amount: String,
}

/// Encodes a swap on Liquorice (RFQ) through the given executor address.
///
/// Liquorice uses a Request-for-Quote model where quotes are obtained off-chain
/// and settled on-chain. The executor receives pre-encoded calldata from the API.
///
/// # Fields
/// * `executor_address` - The address of the executor contract that will perform the swap.
/// * `native_token_address` - The chain's native token address.
#[derive(Clone)]
pub struct LiquoriceSwapEncoder {
    executor_address: Bytes,
    native_token_address: Bytes,
    runtime_handle: Handle,
    #[allow(dead_code)]
    runtime: Option<Arc<Runtime>>,
}

impl SwapEncoder for LiquoriceSwapEncoder {
    fn new(
        executor_address: Bytes,
        chain: Chain,
        _config: Option<HashMap<String, String>>,
    ) -> Result<Self, EncodingError> {
        // No protocol-specific config needed for Liquorice
        // The target contract comes from the quote itself
        let native_token_address = chain.native_token().address;
        let (runtime_handle, runtime) = get_runtime()?;
        Ok(Self {
            executor_address,
            native_token_address,
            runtime_handle,
            runtime,
        })
    }

    fn encode_swap(
        &self,
        swap: &Swap,
        encoding_context: &EncodingContext,
    ) -> Result<Vec<u8>, EncodingError> {
        let token_in = bytes_to_address(swap.token_in())?;
        let token_out = bytes_to_address(swap.token_out())?;

        // Get protocol state and request signed quote
        let protocol_state = swap
            .get_protocol_state()
            .as_ref()
            .ok_or_else(|| {
                EncodingError::FatalError("protocol_state is required for Liquorice".to_string())
            })?;

        let estimated_amount_in = swap
            .get_estimated_amount_in()
            .clone()
            .ok_or(EncodingError::FatalError(
                "Estimated amount in is mandatory for a Liquorice swap".to_string(),
            ))?;

        let sender = encoding_context
            .router_address
            .clone()
            .ok_or(EncodingError::FatalError(
                "The router address is needed to perform a Liquorice swap".to_string(),
            ))?;

        let params = GetAmountOutParams {
            amount_in: estimated_amount_in.clone(),
            token_in: swap.token_in().clone(),
            token_out: swap.token_out().clone(),
            sender,
            receiver: encoding_context.receiver.clone(),
        };

        let signed_quote = block_in_place(|| {
            self.runtime_handle.block_on(async {
                protocol_state
                    .as_indicatively_priced()?
                    .request_signed_quote(params)
                    .await
            })
        })?;

        // Extract required fields from quote
        let target_contract = signed_quote
            .quote_attributes
            .get("target_contract")
            .ok_or(EncodingError::FatalError(
                "Liquorice quote must have a target_contract attribute".to_string(),
            ))?;

        let liquorice_calldata = signed_quote
            .quote_attributes
            .get("calldata")
            .ok_or(EncodingError::FatalError(
                "Liquorice quote must have a calldata attribute".to_string(),
            ))?;

        let base_token_amount = signed_quote
            .quote_attributes
            .get("base_token_amount")
            .ok_or(EncodingError::FatalError(
                "Liquorice quote must have a base_token_amount attribute".to_string(),
            ))?;

        // Get partial fill offset (defaults to 0 if not present, meaning no partial fill support)
        let partial_fill_offset: u8 = signed_quote
            .quote_attributes
            .get("partial_fill_offset")
            .map(|b| {
                // Take the last byte (u8 value)
                b.last().copied().unwrap_or(0)
            })
            .unwrap_or(0);

        // Parse original base token amount (U256 encoded as 32 bytes)
        let original_base_token_amount = if base_token_amount.len() == 32 {
            base_token_amount.to_vec()
        } else {
            // Pad to 32 bytes if needed
            let mut padded = vec![0u8; 32];
            let start = 32 - base_token_amount.len();
            padded[start..].copy_from_slice(base_token_amount);
            padded
        };

        // Parse allowances from quote
        let allowances: Vec<LiquoriceAllowance> = signed_quote
            .quote_attributes
            .get("allowances")
            .map(|bytes| {
                let json_str = String::from_utf8_lossy(bytes);
                serde_json::from_str(&json_str).unwrap_or_default()
            })
            .unwrap_or_default();

        // Check which allowances need approval
        let executor_address = bytes_to_address(&self.executor_address)?;
        let approvals_manager = ProtocolApprovalsManager::new()?;

        let mut allowance_data: Vec<(Address, bool)> = Vec::new();
        for allowance in &allowances {
            let spender = Address::from_str(&allowance.spender).map_err(|_| {
                EncodingError::FatalError(format!(
                    "Invalid allowance spender address: {}",
                    allowance.spender
                ))
            })?;

            // Check if approval is needed from executor to spender
            let approval_needed = if *swap.token_in() == self.native_token_address {
                false
            } else {
                approvals_manager.approval_needed(token_in, executor_address, spender)?
            };

            allowance_data.push((spender, approval_needed));
        }

        let receiver = bytes_to_address(&encoding_context.receiver)?;
        let target = bytes_to_address(target_contract)?;

        // Encode packed data for the executor
        // Format: token_in | token_out | transfer_type | partial_fill_offset |
        //         original_base_token_amount | num_allowances |
        //         [allowance_spender | approval_needed]... |
        //         target_contract | receiver | liquorice_calldata
        let mut encoded = Vec::new();

        // Fixed fields
        encoded.extend_from_slice(token_in.as_slice()); // 20 bytes
        encoded.extend_from_slice(token_out.as_slice()); // 20 bytes
        encoded.push(encoding_context.transfer_type as u8); // 1 byte
        encoded.push(partial_fill_offset); // 1 byte
        encoded.extend_from_slice(&original_base_token_amount); // 32 bytes

        // Allowances
        encoded.push(allowance_data.len() as u8); // 1 byte
        for (spender, approval_needed) in &allowance_data {
            encoded.extend_from_slice(spender.as_slice()); // 20 bytes
            encoded.push(*approval_needed as u8); // 1 byte
        }

        // Target and receiver
        encoded.extend_from_slice(target.as_slice()); // 20 bytes
        encoded.extend_from_slice(receiver.as_slice()); // 20 bytes

        // Calldata (variable length)
        encoded.extend_from_slice(liquorice_calldata);

        Ok(encoded)
    }

    fn executor_address(&self) -> &Bytes {
        &self.executor_address
    }

    fn clone_box(&self) -> Box<dyn SwapEncoder> {
        Box::new(self.clone())
    }
}

#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use alloy::hex::encode;
    use num_bigint::BigUint;
    use tycho_common::models::protocol::ProtocolComponent;

    use super::*;
    use crate::encoding::{
        evm::{
            swap_encoder::liquorice::LiquoriceSwapEncoder, testing_utils::MockRFQState,
            utils::biguint_to_u256,
        },
        models::TransferType,
    };

    #[test]
    fn test_encode_liquorice_single_fails_without_protocol_data() {
        let liquorice_component = ProtocolComponent {
            id: String::from("liquorice-rfq"),
            protocol_system: String::from("rfq:liquorice"),
            ..Default::default()
        };

        let token_in = Bytes::from("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"); // USDC
        let token_out = Bytes::from("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"); // WETH

        let swap = Swap::new(liquorice_component, token_in.clone(), token_out.clone())
            .estimated_amount_in(BigUint::from_str("3000000000").unwrap());

        let encoding_context = EncodingContext {
            receiver: Bytes::from("0xc5564C13A157E6240659fb81882A28091add8670"),
            exact_out: false,
            router_address: Some(Bytes::zero(20)),
            group_token_in: token_in.clone(),
            group_token_out: token_out.clone(),
            transfer_type: TransferType::Transfer,
            historical_trade: false,
        };

        let encoder = LiquoriceSwapEncoder::new(
            Bytes::from("0x543778987b293C7E8Cf0722BB2e935ba6f4068D4"),
            Chain::Ethereum,
            None,
        )
        .unwrap();

        encoder
            .encode_swap(&swap, &encoding_context)
            .expect_err("Should return an error if the swap has no protocol state");
    }

    #[test]
    fn test_encode_liquorice_single_with_protocol_state() {
        // 3000 USDC -> 1 WETH using a mocked RFQ state to get a quote
        let quote_amount_out = BigUint::from_str("1000000000000000000").unwrap();
        let liquorice_calldata = Bytes::from_str("0xdeadbeef1234567890").unwrap();
        let base_token_amount = biguint_to_u256(&BigUint::from(3000000000_u64))
            .to_be_bytes::<32>()
            .to_vec();

        let liquorice_component = ProtocolComponent {
            id: String::from("liquorice-rfq"),
            protocol_system: String::from("rfq:liquorice"),
            ..Default::default()
        };

        // Allowances JSON - one spender needing approval
        let allowances_json =
            r#"[{"token":"0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48","spender":"0x71D9750ECF0c5081FAE4E3EDC4253E52024b0B59","amount":"3000000000"}]"#;

        let liquorice_state = MockRFQState {
            quote_amount_out,
            quote_data: HashMap::from([
                (
                    "target_contract".to_string(),
                    Bytes::from_str("0x71D9750ECF0c5081FAE4E3EDC4253E52024b0B59").unwrap(),
                ),
                ("calldata".to_string(), liquorice_calldata.clone()),
                ("base_token_amount".to_string(), Bytes::from(base_token_amount.clone())),
                ("partial_fill_offset".to_string(), Bytes::from(vec![12u8])),
                ("allowances".to_string(), Bytes::from(allowances_json.as_bytes().to_vec())),
            ]),
        };

        let token_in = Bytes::from("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"); // USDC
        let token_out = Bytes::from("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"); // WETH

        let swap = Swap::new(liquorice_component, token_in.clone(), token_out.clone())
            .estimated_amount_in(BigUint::from_str("3000000000").unwrap())
            .protocol_state(Arc::new(liquorice_state));

        let encoding_context = EncodingContext {
            receiver: Bytes::from("0xc5564C13A157E6240659fb81882A28091add8670"),
            exact_out: false,
            router_address: Some(Bytes::zero(20)),
            group_token_in: token_in.clone(),
            group_token_out: token_out.clone(),
            transfer_type: TransferType::Transfer,
            historical_trade: false,
        };

        let encoder = LiquoriceSwapEncoder::new(
            Bytes::from("0x543778987b293C7E8Cf0722BB2e935ba6f4068D4"),
            Chain::Ethereum,
            None,
        )
        .unwrap();

        let encoded_swap = encoder
            .encode_swap(&swap, &encoding_context)
            .unwrap();
        let hex_swap = encode(&encoded_swap);

        // Expected format:
        // token_in (20) | token_out (20) | transfer_type (1) | partial_fill_offset (1) |
        // original_base_token_amount (32) | num_allowances (1) |
        // [spender (20) | approval_needed (1)]... |
        // target_contract (20) | receiver (20) | calldata (variable)
        let expected_swap = String::from(concat!(
            // token_in (USDC)
            "a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            // token_out (WETH)
            "c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
            // transfer_type
            "01",
            // partial_fill_offset
            "0c",
            // original_base_token_amount (3000000000 as U256)
            "00000000000000000000000000000000000000000000000000000000b2d05e00",
            // num_allowances
            "01",
            // allowance spender
            "71d9750ecf0c5081fae4e3edc4253e52024b0b59",
            // approval_needed
            "01",
            // target_contract
            "71d9750ecf0c5081fae4e3edc4253e52024b0b59",
            // receiver
            "c5564c13a157e6240659fb81882a28091add8670",
        ));
        assert_eq!(hex_swap, expected_swap + &liquorice_calldata.to_string()[2..]);
    }

    #[test]
    fn test_encode_liquorice_no_allowances() {
        // Test with empty allowances
        let quote_amount_out = BigUint::from_str("1000000000000000000").unwrap();
        let liquorice_calldata = Bytes::from_str("0xabcdef").unwrap();
        let base_token_amount = biguint_to_u256(&BigUint::from(1000000000_u64))
            .to_be_bytes::<32>()
            .to_vec();

        let liquorice_component = ProtocolComponent {
            id: String::from("liquorice-rfq"),
            protocol_system: String::from("rfq:liquorice"),
            ..Default::default()
        };

        let liquorice_state = MockRFQState {
            quote_amount_out,
            quote_data: HashMap::from([
                (
                    "target_contract".to_string(),
                    Bytes::from_str("0x71D9750ECF0c5081FAE4E3EDC4253E52024b0B59").unwrap(),
                ),
                ("calldata".to_string(), liquorice_calldata.clone()),
                ("base_token_amount".to_string(), Bytes::from(base_token_amount)),
                ("allowances".to_string(), Bytes::from("[]".as_bytes().to_vec())),
            ]),
        };

        let token_in = Bytes::from("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
        let token_out = Bytes::from("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");

        let swap = Swap::new(liquorice_component, token_in.clone(), token_out.clone())
            .estimated_amount_in(BigUint::from_str("1000000000").unwrap())
            .protocol_state(Arc::new(liquorice_state));

        let encoding_context = EncodingContext {
            receiver: Bytes::from("0xc5564C13A157E6240659fb81882A28091add8670"),
            exact_out: false,
            router_address: Some(Bytes::zero(20)),
            group_token_in: token_in.clone(),
            group_token_out: token_out.clone(),
            transfer_type: TransferType::Transfer,
            historical_trade: false,
        };

        let encoder = LiquoriceSwapEncoder::new(
            Bytes::from("0x543778987b293C7E8Cf0722BB2e935ba6f4068D4"),
            Chain::Ethereum,
            None,
        )
        .unwrap();

        let encoded_swap = encoder
            .encode_swap(&swap, &encoding_context)
            .unwrap();

        // Verify num_allowances is 0 (at byte position 74)
        assert_eq!(encoded_swap[74], 0);
    }
}
