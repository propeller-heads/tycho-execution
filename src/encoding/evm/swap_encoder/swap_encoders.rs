use std::str::FromStr;

use alloy_primitives::{Address, Bytes as AlloyBytes};
use alloy_sol_types::SolValue;

use crate::encoding::{
    errors::EncodingError,
    evm::{
        approvals::protocol_approvals_manager::ProtocolApprovalsManager, utils::bytes_to_address,
    },
    models::{EncodingContext, Swap},
    swap_encoder::SwapEncoder,
};

/// Encodes a swap on a Uniswap V2 pool through the given executor address.
///
/// # Fields
/// * `executor_address` - The address of the executor contract that will perform the swap.
/// * `executor_selector` - The selector of the swap function in the executor contract.
#[derive(Clone)]
pub struct UniswapV2SwapEncoder {
    executor_address: String,
    executor_selector: String,
}

impl UniswapV2SwapEncoder {
    fn get_zero_to_one(sell_token_address: Address, buy_token_address: Address) -> bool {
        sell_token_address < buy_token_address
    }
}

impl SwapEncoder for UniswapV2SwapEncoder {
    fn new(executor_address: String) -> Self {
        Self { executor_address, executor_selector: "swap(uint256,bytes)".to_string() }
    }

    fn encode_swap(
        &self,
        swap: Swap,
        encoding_context: EncodingContext,
    ) -> Result<Vec<u8>, EncodingError> {
        let token_in_address = bytes_to_address(&swap.token_in)?;
        let token_out_address = bytes_to_address(&swap.token_out)?;

        let zero_to_one = Self::get_zero_to_one(token_in_address, token_out_address);
        let component_id = Address::from_str(&swap.component.id)
            .map_err(|_| EncodingError::FatalError("Invalid USV2 component id".to_string()))?;

        // Token in address is always needed to perform a manual transfer from the router,
        // since no optimizations are performed that send from one pool to the next
        let args = (
            token_in_address,
            component_id,
            bytes_to_address(&encoding_context.receiver)?,
            zero_to_one,
        );

        Ok(args.abi_encode_packed())
    }

    fn executor_address(&self) -> &str {
        &self.executor_address
    }

    fn executor_selector(&self) -> &str {
        &self.executor_selector
    }

    fn clone_box(&self) -> Box<dyn SwapEncoder> {
        Box::new(self.clone())
    }
}

/// Encodes a swap on a Uniswap V3 pool through the given executor address.
///
/// # Fields
/// * `executor_address` - The address of the executor contract that will perform the swap.
/// * `executor_selector` - The selector of the swap function in the executor contract.
#[derive(Clone)]
pub struct UniswapV3SwapEncoder {
    executor_address: String,
    executor_selector: String,
}

impl UniswapV3SwapEncoder {
    fn get_zero_to_one(sell_token_address: Address, buy_token_address: Address) -> bool {
        sell_token_address < buy_token_address
    }
}

impl SwapEncoder for UniswapV3SwapEncoder {
    fn new(executor_address: String) -> Self {
        Self { executor_address, executor_selector: "swap(uint256,bytes)".to_string() }
    }

    fn encode_swap(
        &self,
        swap: Swap,
        encoding_context: EncodingContext,
    ) -> Result<Vec<u8>, EncodingError> {
        let token_in_address = bytes_to_address(&swap.token_in)?;
        let token_out_address = bytes_to_address(&swap.token_out)?;

        let zero_to_one = Self::get_zero_to_one(token_in_address, token_out_address);
        let component_id = Address::from_str(&swap.component.id)
            .map_err(|_| EncodingError::FatalError("Invalid USV3 component id".to_string()))?;
        let mut pool_fee_bytes = swap
            .component
            .static_attributes
            .get("pool_fee")
            .ok_or_else(|| {
                EncodingError::FatalError(
                    "Pool fee not found in Uniswap v3 static attributes".to_string(),
                )
            })?
            .as_ref()
            .to_vec();

        // Reverse to get be bytes, since this is encoded as le bytes
        pool_fee_bytes.reverse();

        let pool_fee_u24: [u8; 3] = pool_fee_bytes[pool_fee_bytes.len() - 3..]
            .try_into()
            .map_err(|_| {
                EncodingError::FatalError(
                    "Pool fee static attribute must be at least 3 bytes".to_string(),
                )
            })?;

        let args = (
            token_in_address,
            token_out_address,
            pool_fee_u24,
            bytes_to_address(&encoding_context.receiver)?,
            component_id,
            zero_to_one,
        );

        Ok(args.abi_encode_packed())
    }

    fn executor_address(&self) -> &str {
        &self.executor_address
    }
    fn executor_selector(&self) -> &str {
        &self.executor_selector
    }
    fn clone_box(&self) -> Box<dyn SwapEncoder> {
        Box::new(self.clone())
    }
}

/// Encodes a swap on a Balancer V2 pool through the given executor address.
///
/// # Fields
/// * `executor_address` - The address of the executor contract that will perform the swap.
/// * `executor_selector` - The selector of the swap function in the executor contract.
#[derive(Clone)]
pub struct BalancerV2SwapEncoder {
    executor_address: String,
    executor_selector: String,
    vault_address: String,
}

impl SwapEncoder for BalancerV2SwapEncoder {
    fn new(executor_address: String) -> Self {
        Self {
            executor_address,
            executor_selector: "swap(uint256,bytes)".to_string(),
            vault_address: "0xba12222222228d8ba445958a75a0704d566bf2c8".to_string(),
        }
    }
    fn encode_swap(
        &self,
        swap: Swap,
        encoding_context: EncodingContext,
    ) -> Result<Vec<u8>, EncodingError> {
        let token_approvals_manager = ProtocolApprovalsManager::new()?;
        let token = bytes_to_address(&swap.token_in)?;
        let router_address = bytes_to_address(&encoding_context.router_address)?;
        let approval_needed = token_approvals_manager.approval_needed(
            token,
            router_address,
            Address::from_str(&self.vault_address)
                .map_err(|_| EncodingError::FatalError("Invalid vault address".to_string()))?,
        )?;

        let component_id = AlloyBytes::from_str(&swap.component.id)
            .map_err(|_| EncodingError::FatalError("Invalid component ID".to_string()))?;

        let args = (
            bytes_to_address(&swap.token_in)?,
            bytes_to_address(&swap.token_out)?,
            component_id,
            bytes_to_address(&encoding_context.receiver)?,
            approval_needed,
        );
        Ok(args.abi_encode_packed())
    }

    fn executor_address(&self) -> &str {
        &self.executor_address
    }
    fn executor_selector(&self) -> &str {
        &self.executor_selector
    }
    fn clone_box(&self) -> Box<dyn SwapEncoder> {
        Box::new(self.clone())
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use alloy::hex::encode;
    use tycho_core::{dto::ProtocolComponent, Bytes};

    use super::*;

    #[test]
    fn test_encode_uniswap_v2() {
        let usv2_pool = ProtocolComponent {
            id: String::from("0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"),
            ..Default::default()
        };
        let swap = Swap {
            component: usv2_pool,
            token_in: Bytes::from("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"),
            token_out: Bytes::from("0x6b175474e89094c44da98b954eedeac495271d0f"),
            split: 0f64,
        };
        let encoding_context = EncodingContext {
            receiver: Bytes::from("0x0000000000000000000000000000000000000001"),
            exact_out: false,
            router_address: Bytes::zero(20),
        };
        let encoder =
            UniswapV2SwapEncoder::new(String::from("0x543778987b293C7E8Cf0722BB2e935ba6f4068D4"));
        let encoded_swap = encoder
            .encode_swap(swap, encoding_context)
            .unwrap();
        let hex_swap = encode(&encoded_swap);
        assert_eq!(
            hex_swap,
            String::from(concat!(
                // in token
                "c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
                // component id
                "88e6a0c2ddd26feeb64f039a2c41296fcb3f5640",
                // receiver
                "0000000000000000000000000000000000000001",
                // zero for one
                "00",
            ))
        );
    }
    #[test]
    fn test_encode_uniswap_v3() {
        let encoded_pool_fee: [u8; 4] = 500u32.to_le_bytes();
        let mut static_attributes: HashMap<String, Bytes> = HashMap::new();
        static_attributes.insert("pool_fee".into(), Bytes::from(encoded_pool_fee[..3].to_vec()));

        let usv3_pool = ProtocolComponent {
            id: String::from("0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"),
            static_attributes,
            ..Default::default()
        };
        let swap = Swap {
            component: usv3_pool,
            token_in: Bytes::from("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"),
            token_out: Bytes::from("0x6b175474e89094c44da98b954eedeac495271d0f"),
            split: 0f64,
        };
        let encoding_context = EncodingContext {
            receiver: Bytes::from("0x0000000000000000000000000000000000000001"),
            exact_out: false,
            router_address: Bytes::zero(20),
        };
        let encoder =
            UniswapV3SwapEncoder::new(String::from("0x543778987b293C7E8Cf0722BB2e935ba6f4068D4"));
        let encoded_swap = encoder
            .encode_swap(swap, encoding_context)
            .unwrap();
        let hex_swap = encode(&encoded_swap);
        assert_eq!(
            hex_swap,
            String::from(concat!(
                // in token
                "c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
                // out token
                "6b175474e89094c44da98b954eedeac495271d0f",
                // fee
                "0001f4",
                // receiver
                "0000000000000000000000000000000000000001",
                // pool id
                "88e6a0c2ddd26feeb64f039a2c41296fcb3f5640",
                // zero for one
                "00",
            ))
        );
    }

    #[test]
    fn test_encode_balancer_v2() {
        let balancer_pool = ProtocolComponent {
            id: String::from("0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014"),
            protocol_system: String::from("vm:balancer_v2"),
            ..Default::default()
        };
        let swap = Swap {
            component: balancer_pool,
            token_in: Bytes::from("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"), // WETH
            token_out: Bytes::from("0xba100000625a3754423978a60c9317c58a424e3D"), // BAL
            split: 0f64,
        };
        let encoding_context = EncodingContext {
            // The receiver was generated with `makeAddr("bob") using forge`
            receiver: Bytes::from("0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e"),
            exact_out: false,
            router_address: Bytes::zero(20),
        };
        let encoder =
            BalancerV2SwapEncoder::new(String::from("0x543778987b293C7E8Cf0722BB2e935ba6f4068D4"));
        let encoded_swap = encoder
            .encode_swap(swap, encoding_context)
            .unwrap();
        let hex_swap = encode(&encoded_swap);
        println!("{}", hex_swap);

        assert_eq!(
            hex_swap,
            String::from(concat!(
                // token in
                "c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
                // token out
                "ba100000625a3754423978a60c9317c58a424e3d",
                // pool id
                "5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014",
                // receiver
                "1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e",
                // approval needed
                "01"
            ))
        );
    }
}
