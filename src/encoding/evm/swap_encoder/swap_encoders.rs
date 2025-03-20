use std::str::FromStr;

use alloy_primitives::{Address, Bytes as AlloyBytes};
use alloy_sol_types::SolValue;
use tycho_core::Bytes;

use crate::encoding::{
    errors::EncodingError,
    evm::{
        approvals::protocol_approvals_manager::ProtocolApprovalsManager,
        utils::{bytes_to_address, get_static_attribute, pad_to_fixed_size},
    },
    models::{EncodingContext, Swap},
    swap_encoder::SwapEncoder,
};

/// Encodes a swap on a Uniswap V2 pool through the given executor address.
///
/// # Fields
/// * `executor_address` - The address of the executor contract that will perform the swap.
/// * `swap_selector` - The selector of the swap function in the executor contract.
#[derive(Clone)]
pub struct UniswapV2SwapEncoder {
    executor_address: String,
}

impl UniswapV2SwapEncoder {
    fn get_zero_to_one(sell_token_address: Address, buy_token_address: Address) -> bool {
        sell_token_address < buy_token_address
    }
}

impl SwapEncoder for UniswapV2SwapEncoder {
    fn new(executor_address: String) -> Self {
        Self { executor_address }
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

    fn clone_box(&self) -> Box<dyn SwapEncoder> {
        Box::new(self.clone())
    }
}

/// Encodes a swap on a Uniswap V3 pool through the given executor address.
///
/// # Fields
/// * `executor_address` - The address of the executor contract that will perform the swap.
/// * `swap_selector` - The selector of the swap function in the executor contract.
#[derive(Clone)]
pub struct UniswapV3SwapEncoder {
    executor_address: String,
}

impl UniswapV3SwapEncoder {
    fn get_zero_to_one(sell_token_address: Address, buy_token_address: Address) -> bool {
        sell_token_address < buy_token_address
    }
}

impl SwapEncoder for UniswapV3SwapEncoder {
    fn new(executor_address: String) -> Self {
        Self { executor_address }
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
        let pool_fee_bytes = get_static_attribute(&swap, "fee")?;

        let pool_fee_u24 = pad_to_fixed_size::<3>(&pool_fee_bytes)
            .map_err(|_| EncodingError::FatalError("Failed to extract fee bytes".to_string()))?;

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
    fn clone_box(&self) -> Box<dyn SwapEncoder> {
        Box::new(self.clone())
    }
}

/// Encodes a swap on a Uniswap V4 pool through the given executor address.
///
/// # Fields
/// * `executor_address` - The address of the executor contract that will perform the swap.
/// * `swap_selector` - The selector of the swap function in the executor contract.
/// * `callback_selector` - The selector of the callback function in the executor contract.
#[derive(Clone)]
pub struct UniswapV4SwapEncoder {
    executor_address: String,
}

impl UniswapV4SwapEncoder {
    fn get_zero_to_one(sell_token_address: Address, buy_token_address: Address) -> bool {
        sell_token_address < buy_token_address
    }
}

impl SwapEncoder for UniswapV4SwapEncoder {
    fn new(executor_address: String) -> Self {
        Self { executor_address }
    }

    fn encode_swap(
        &self,
        swap: Swap,
        encoding_context: EncodingContext,
    ) -> Result<Vec<u8>, EncodingError> {
        let fee = get_static_attribute(&swap, "key_lp_fee")?;

        let pool_fee_u24 = pad_to_fixed_size::<3>(&fee)
            .map_err(|_| EncodingError::FatalError("Failed to pad fee bytes".to_string()))?;

        let tick_spacing = get_static_attribute(&swap, "tick_spacing")?;

        let pool_tick_spacing_u24 = pad_to_fixed_size::<3>(&tick_spacing).map_err(|_| {
            EncodingError::FatalError("Failed to pad tick spacing bytes".to_string())
        })?;

        // Early check if this is not the first swap
        if encoding_context.group_token_in != swap.token_in {
            return Ok((bytes_to_address(&swap.token_out)?, pool_fee_u24, pool_tick_spacing_u24)
                .abi_encode_packed());
        }

        // This is the first swap, compute all necessary values
        let token_in_address = bytes_to_address(&swap.token_in)?;
        let token_out_address = bytes_to_address(&swap.token_out)?;
        let group_token_in_address = bytes_to_address(&encoding_context.group_token_in)?;
        let group_token_out_address = bytes_to_address(&encoding_context.group_token_out)?;

        let zero_to_one = Self::get_zero_to_one(token_in_address, token_out_address);
        let callback_executor =
            bytes_to_address(&Bytes::from_str(&self.executor_address).map_err(|_| {
                EncodingError::FatalError("Invalid UniswapV4 executor address".into())
            })?)?;

        let pool_params =
            (token_out_address, pool_fee_u24, pool_tick_spacing_u24).abi_encode_packed();

        let args = (
            group_token_in_address,
            group_token_out_address,
            zero_to_one,
            callback_executor,
            pool_params,
        );

        Ok(args.abi_encode_packed())
    }

    fn executor_address(&self) -> &str {
        &self.executor_address
    }

    fn clone_box(&self) -> Box<dyn SwapEncoder> {
        Box::new(self.clone())
    }
}

/// Encodes a swap on a Balancer V2 pool through the given executor address.
///
/// # Fields
/// * `executor_address` - The address of the executor contract that will perform the swap.
/// * `vault_address` - The address of the vault contract that will perform the swap.
#[derive(Clone)]
pub struct BalancerV2SwapEncoder {
    executor_address: String,
    vault_address: String,
}

impl SwapEncoder for BalancerV2SwapEncoder {
    fn new(executor_address: String) -> Self {
        Self {
            executor_address,
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
    fn clone_box(&self) -> Box<dyn SwapEncoder> {
        Box::new(self.clone())
    }
}

/// Encodes a swap on Sky through the given executor address.
///
/// # Fields
/// * `executor_address` - The address of the executor contract that will perform the swap.
#[derive(Clone)]
pub struct SkySwapEncoder {
    executor_address: String,
}

impl SkySwapEncoder {
    // Constants for Sky protocol component addresses
    const SDAI_VAULT_ADDRESS: &'static str = "0x83F20F44975D03b1b09e64809B757c47f942BEeA";
    const DAI_USDS_CONVERTER_ADDRESS: &'static str = "0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A";
    const DAI_LITE_PSM_ADDRESS: &'static str = "0xf6e72Db5454dd049d0788e411b06CfAF16853042";
    const USDS_PSM_WRAPPER_ADDRESS: &'static str = "0xA188EEC8F81263234dA3622A406892F3D630f98c";
    const SUSDS_ADDRESS: &'static str = "0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD";
    const MKR_SKY_CONVERTER_ADDRESS: &'static str = "0xBDcFCA946b6CDd965f99a839e4435Bcdc1bc470B";

    // Helper to determine component type
    fn get_component_type(component_id: &str) -> &'static str {
        match component_id.to_lowercase().as_str() {
            id if id.contains(
                Self::SDAI_VAULT_ADDRESS
                    .to_lowercase()
                    .as_str(),
            ) =>
            {
                "sdai_vault"
            }
            id if id.contains(
                Self::DAI_USDS_CONVERTER_ADDRESS
                    .to_lowercase()
                    .as_str(),
            ) =>
            {
                "dai_usds_converter"
            }
            id if id.contains(
                Self::DAI_LITE_PSM_ADDRESS
                    .to_lowercase()
                    .as_str(),
            ) =>
            {
                "dai_lite_psm"
            }
            id if id.contains(
                Self::USDS_PSM_WRAPPER_ADDRESS
                    .to_lowercase()
                    .as_str(),
            ) =>
            {
                "usds_psm_wrapper"
            }
            id if id.contains(
                Self::SUSDS_ADDRESS
                    .to_lowercase()
                    .as_str(),
            ) =>
            {
                "susds_vault"
            }
            id if id.contains(
                Self::MKR_SKY_CONVERTER_ADDRESS
                    .to_lowercase()
                    .as_str(),
            ) =>
            {
                "mkr_sky_converter"
            }
            _ => "unknown",
        }
    }
}

impl SwapEncoder for SkySwapEncoder {
    fn new(executor_address: String) -> Self {
        Self { executor_address }
    }

    fn encode_swap(
        &self,
        swap: Swap,
        encoding_context: EncodingContext,
    ) -> Result<Vec<u8>, EncodingError> {
        let token_in_address = bytes_to_address(&swap.token_in)?;
        let token_out_address = bytes_to_address(&swap.token_out)?;
        let component_id = Address::from_str(&swap.component.id)
            .map_err(|_| EncodingError::FatalError("Invalid Sky component id".to_string()))?;
        let receiver = bytes_to_address(&encoding_context.receiver)?;

        // Determine the component type
        let component_type = Self::get_component_type(&swap.component.id);

        // Create a base encoding with the common parameters
        let mut encoded = Vec::new();

        // Add token_in, token_out, component_id, and receiver to all encodings
        encoded.extend_from_slice(&token_in_address.abi_encode_packed());
        encoded.extend_from_slice(&token_out_address.abi_encode_packed());
        encoded.extend_from_slice(&component_id.abi_encode_packed());
        encoded.extend_from_slice(&receiver.abi_encode_packed());

        // Add component-specific parameters
        match component_type {
            "sdai_vault" | "susds_vault" => {
                // For vault components, we need to encode deposit/withdraw flag
                let is_deposit = token_in_address != component_id;
                encoded.push(if is_deposit { 1u8 } else { 0u8 });
            }
            "dai_lite_psm" | "usds_psm_wrapper" => {
                // For PSM components, might need to include fee information
                if let Ok(fee_bytes) = get_static_attribute(&swap, "fee") {
                    if let Ok(fee) = pad_to_fixed_size::<3>(&fee_bytes) {
                        encoded.extend_from_slice(&fee);
                    }
                } else {
                    // Default to zero fee if not specified
                    encoded.extend_from_slice(&[0u8, 0u8, 0u8]);
                }
            }
            _ => {
                // No additional parameters for other components
            }
        };

        Ok(encoded)
    }

    fn executor_address(&self) -> &str {
        &self.executor_address
    }

    fn clone_box(&self) -> Box<dyn SwapEncoder> {
        Box::new(self.clone())
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use alloy::hex::encode;
    use num_bigint::BigInt;
    use tycho_core::{models::protocol::ProtocolComponent, Bytes};

    use super::*;

    #[test]
    fn test_encode_uniswap_v2() {
        let usv2_pool = ProtocolComponent {
            id: String::from("0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"),
            ..Default::default()
        };

        let token_in = Bytes::from("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");
        let token_out = Bytes::from("0x6b175474e89094c44da98b954eedeac495271d0f");
        let swap = Swap {
            component: usv2_pool,
            token_in: token_in.clone(),
            token_out: token_out.clone(),
            split: 0f64,
        };
        let encoding_context = EncodingContext {
            receiver: Bytes::from("0x0000000000000000000000000000000000000001"),
            exact_out: false,
            router_address: Bytes::zero(20),
            group_token_in: token_in.clone(),
            group_token_out: token_out.clone(),
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
        let fee = BigInt::from(500);
        let encoded_pool_fee = Bytes::from(fee.to_signed_bytes_be());
        let mut static_attributes: HashMap<String, Bytes> = HashMap::new();
        static_attributes.insert("fee".into(), Bytes::from(encoded_pool_fee.to_vec()));

        let usv3_pool = ProtocolComponent {
            id: String::from("0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"),
            static_attributes,
            ..Default::default()
        };
        let token_in = Bytes::from("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");
        let token_out = Bytes::from("0x6b175474e89094c44da98b954eedeac495271d0f");
        let swap = Swap {
            component: usv3_pool,
            token_in: token_in.clone(),
            token_out: token_out.clone(),
            split: 0f64,
        };
        let encoding_context = EncodingContext {
            receiver: Bytes::from("0x0000000000000000000000000000000000000001"),
            exact_out: false,
            router_address: Bytes::zero(20),
            group_token_in: token_in.clone(),
            group_token_out: token_out.clone(),
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
        let token_in = Bytes::from("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");
        let token_out = Bytes::from("0xba100000625a3754423978a60c9317c58a424e3D");
        let swap = Swap {
            component: balancer_pool,
            token_in: token_in.clone(),
            token_out: token_out.clone(),
            split: 0f64,
        };
        let encoding_context = EncodingContext {
            // The receiver was generated with `makeAddr("bob") using forge`
            receiver: Bytes::from("0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e"),
            exact_out: false,
            router_address: Bytes::zero(20),
            group_token_in: token_in.clone(),
            group_token_out: token_out.clone(),
        };
        let encoder =
            BalancerV2SwapEncoder::new(String::from("0x543778987b293C7E8Cf0722BB2e935ba6f4068D4"));
        let encoded_swap = encoder
            .encode_swap(swap, encoding_context)
            .unwrap();
        let hex_swap = encode(&encoded_swap);

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

    #[test]
    fn test_encode_uniswap_v4_simple_swap() {
        let fee = BigInt::from(100);
        let tick_spacing = BigInt::from(1);
        let token_in = Bytes::from("0x4c9EDD5852cd905f086C759E8383e09bff1E68B3"); // USDE
        let token_out = Bytes::from("0xdAC17F958D2ee523a2206206994597C13D831ec7"); // USDT

        let mut static_attributes: HashMap<String, Bytes> = HashMap::new();
        static_attributes.insert("key_lp_fee".into(), Bytes::from(fee.to_signed_bytes_be()));
        static_attributes
            .insert("tick_spacing".into(), Bytes::from(tick_spacing.to_signed_bytes_be()));

        let usv4_pool = ProtocolComponent {
            // Pool manager
            id: String::from("0x000000000004444c5dc75cB358380D2e3dE08A90"),
            static_attributes,
            ..Default::default()
        };
        let swap = Swap {
            component: usv4_pool,
            token_in: token_in.clone(),
            token_out: token_out.clone(),
            split: 0f64,
        };
        let encoding_context = EncodingContext {
            // The receiver address was taken from `address(uniswapV4Exposed)` in the
            // UniswapV4Executor.t.sol
            receiver: Bytes::from("0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f"),
            exact_out: false,
            // Same as the executor address
            router_address: Bytes::from("0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f"),

            group_token_in: token_in.clone(),
            group_token_out: token_out.clone(),
        };
        let encoder =
            UniswapV4SwapEncoder::new(String::from("0xF62849F9A0B5Bf2913b396098F7c7019b51A820a"));
        let encoded_swap = encoder
            .encode_swap(swap, encoding_context)
            .unwrap();
        let hex_swap = encode(&encoded_swap);
        println!("{}", hex_swap);

        assert_eq!(
            hex_swap,
            String::from(concat!(
                // group token in
                "4c9edd5852cd905f086c759e8383e09bff1e68b3",
                // group token out
                "dac17f958d2ee523a2206206994597c13d831ec7",
                // zero for one
                "01",
                // executor address
                "f62849f9a0b5bf2913b396098f7c7019b51a820a",
                // pool params:
                // - intermediary token
                "dac17f958d2ee523a2206206994597c13d831ec7",
                // - fee
                "000064",
                // - tick spacing
                "000001"
            ))
        );
    }

    #[test]
    fn test_encode_uniswap_v4_second_swap() {
        let fee = BigInt::from(3000);
        let tick_spacing = BigInt::from(60);
        let group_token_in = Bytes::from("0x4c9EDD5852cd905f086C759E8383e09bff1E68B3"); // USDE
        let token_in = Bytes::from("0xdAC17F958D2ee523a2206206994597C13D831ec7"); // USDT
        let token_out = Bytes::from("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599"); // WBTC

        let mut static_attributes: HashMap<String, Bytes> = HashMap::new();
        static_attributes.insert("key_lp_fee".into(), Bytes::from(fee.to_signed_bytes_be()));
        static_attributes
            .insert("tick_spacing".into(), Bytes::from(tick_spacing.to_signed_bytes_be()));

        let usv4_pool = ProtocolComponent {
            id: String::from("0x000000000004444c5dc75cB358380D2e3dE08A90"),
            static_attributes,
            ..Default::default()
        };

        let swap = Swap {
            component: usv4_pool,
            token_in: token_in.clone(),
            token_out: token_out.clone(),
            split: 0f64,
        };

        let encoding_context = EncodingContext {
            receiver: Bytes::from("0x0000000000000000000000000000000000000001"),
            exact_out: false,
            router_address: Bytes::zero(20),
            group_token_in: group_token_in.clone(),
            // Token out is the same as the group token out
            group_token_out: token_out.clone(),
        };

        let encoder =
            UniswapV4SwapEncoder::new(String::from("0x543778987b293C7E8Cf0722BB2e935ba6f4068D4"));
        let encoded_swap = encoder
            .encode_swap(swap, encoding_context)
            .unwrap();
        let hex_swap = encode(&encoded_swap);

        assert_eq!(
            hex_swap,
            String::from(concat!(
                // pool params:
                // - intermediary token (20 bytes)
                "2260fac5e5542a773aa44fbcfedf7c193bc2c599",
                // - fee (3 bytes)
                "000bb8",
                // - tick spacing (3 bytes)
                "00003c"
            ))
        );
    }

    #[test]
    fn test_encode_uniswap_v4_sequential_swap() {
        let usde_address = Bytes::from("0x4c9EDD5852cd905f086C759E8383e09bff1E68B3");
        let usdt_address = Bytes::from("0xdAC17F958D2ee523a2206206994597C13D831ec7");
        let wbtc_address = Bytes::from("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599");
        let router_address = Bytes::from("0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f");
        let receiver_address = router_address.clone();

        // The context is the same for both swaps, since the group token in and out are the same
        let context = EncodingContext {
            receiver: receiver_address.clone(),
            exact_out: false,
            router_address: router_address.clone(),
            group_token_in: usde_address.clone(),
            group_token_out: wbtc_address.clone(),
        };

        // Setup - First sequence: USDE -> USDT
        let usde_usdt_fee = BigInt::from(100);
        let usde_usdt_tick_spacing = BigInt::from(1);

        let mut usde_usdt_static_attributes: HashMap<String, Bytes> = HashMap::new();
        usde_usdt_static_attributes
            .insert("key_lp_fee".into(), Bytes::from(usde_usdt_fee.to_signed_bytes_be()));
        usde_usdt_static_attributes.insert(
            "tick_spacing".into(),
            Bytes::from(usde_usdt_tick_spacing.to_signed_bytes_be()),
        );

        let usde_usdt_component = ProtocolComponent {
            id: String::from("0x000000000004444c5dc75cB358380D2e3dE08A90"),
            static_attributes: usde_usdt_static_attributes,
            ..Default::default()
        };

        // Setup - Second sequence: USDT -> WBTC
        let usdt_wbtc_fee = BigInt::from(3000);
        let usdt_wbtc_tick_spacing = BigInt::from(60);

        let mut usdt_wbtc_static_attributes: HashMap<String, Bytes> = HashMap::new();
        usdt_wbtc_static_attributes
            .insert("key_lp_fee".into(), Bytes::from(usdt_wbtc_fee.to_signed_bytes_be()));
        usdt_wbtc_static_attributes.insert(
            "tick_spacing".into(),
            Bytes::from(usdt_wbtc_tick_spacing.to_signed_bytes_be()),
        );

        let usdt_wbtc_component = ProtocolComponent {
            id: String::from("0x000000000004444c5dc75cB358380D2e3dE08A90"),
            static_attributes: usdt_wbtc_static_attributes,
            ..Default::default()
        };

        let initial_swap = Swap {
            component: usde_usdt_component,
            token_in: usde_address.clone(),
            token_out: usdt_address.clone(),
            split: 0f64,
        };

        let second_swap = Swap {
            component: usdt_wbtc_component,
            token_in: usdt_address,
            token_out: wbtc_address.clone(),
            split: 0f64,
        };

        let encoder =
            UniswapV4SwapEncoder::new(String::from("0xF62849F9A0B5Bf2913b396098F7c7019b51A820a"));
        let initial_encoded_swap = encoder
            .encode_swap(initial_swap, context.clone())
            .unwrap();
        let second_encoded_swap = encoder
            .encode_swap(second_swap, context)
            .unwrap();

        let combined_hex =
            format!("{}{}", encode(&initial_encoded_swap), encode(&second_encoded_swap));

        assert_eq!(
            combined_hex,
            String::from(concat!(
                // group_token in
                "4c9edd5852cd905f086c759e8383e09bff1e68b3",
                // group_token out
                "2260fac5e5542a773aa44fbcfedf7c193bc2c599",
                // zero for one
                "01",
                // executor address
                "f62849f9a0b5bf2913b396098f7c7019b51a820a",
                // pool params:
                // - intermediary token USDT
                "dac17f958d2ee523a2206206994597c13d831ec7",
                // - fee
                "000064",
                // - tick spacing
                "000001",
                // - intermediary token WBTC
                "2260fac5e5542a773aa44fbcfedf7c193bc2c599",
                // - fee
                "000bb8",
                // - tick spacing
                "00003c"
            ))
        );
    }

    #[test]
    fn test_encode_sky_swap() {
        // Test for DAI-USDS Converter component
        let sky_component = ProtocolComponent {
            id: String::from("0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A"), /* DAI-USDS Converter
                                                                             * address */
            protocol_system: String::from("vm:sky"),
            ..Default::default()
        };

        // Use DAI and USDS as example tokens
        let token_in = Bytes::from("0x6B175474E89094C44Da98b954EedeAC495271d0F"); // DAI
        let token_out = Bytes::from("0xdC035D45d973E3EC169d2276DDab16f1e407384F"); // USDS

        let swap = Swap {
            component: sky_component,
            token_in: token_in.clone(),
            token_out: token_out.clone(),
            split: 0f64,
        };

        let encoding_context = EncodingContext {
            receiver: Bytes::from("0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e"),
            exact_out: false,
            router_address: Bytes::zero(20),
            group_token_in: token_in.clone(),
            group_token_out: token_out.clone(),
        };

        let encoder =
            SkySwapEncoder::new(String::from("0xBDcFCA946b6CDd965f99a839e4435Bcdc1bc470B"));
        let encoded_swap = encoder
            .encode_swap(swap, encoding_context)
            .unwrap();
        let hex_swap = encode(&encoded_swap);

        // For a converter component, we expect just the basic parameters
        assert_eq!(
            hex_swap,
            String::from(concat!(
                // token in (DAI)
                "6b175474e89094c44da98b954eedeac495271d0f",
                // token out (USDS)
                "dc035d45d973e3ec169d2276ddab16f1e407384f",
                // component id (DAI-USDS Converter)
                "3225737a9bbb6473cb4a45b7244aca2befdb276a",
                // receiver
                "1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e"
            ))
        );

        // Test for sDAI Vault component
        let sdai_component = ProtocolComponent {
            id: String::from("0x83F20F44975D03b1b09e64809B757c47f942BEeA"), // sDAI Vault address
            protocol_system: String::from("vm:sky"),
            ..Default::default()
        };

        let dai_token = Bytes::from("0x6B175474E89094C44Da98b954EedeAC495271d0F"); // DAI
        let sdai_token = Bytes::from("0x83F20F44975D03b1b09e64809B757c47f942BEeA"); // sDAI (same as vault address)

        // Test deposit (DAI -> sDAI)
        let deposit_swap = Swap {
            component: sdai_component.clone(),
            token_in: dai_token.clone(),
            token_out: sdai_token.clone(),
            split: 0f64,
        };

        let deposit_context = EncodingContext {
            receiver: Bytes::from("0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e"),
            exact_out: false,
            router_address: Bytes::zero(20),
            group_token_in: dai_token.clone(),
            group_token_out: sdai_token.clone(),
        };

        let encoded_deposit = encoder
            .encode_swap(deposit_swap, deposit_context)
            .unwrap();
        let hex_deposit = encode(&encoded_deposit);

        // For a vault deposit, we expect the basic parameters plus a deposit flag (1)
        assert_eq!(
            hex_deposit,
            String::from(concat!(
                // token in (DAI)
                "6b175474e89094c44da98b954eedeac495271d0f",
                // token out (sDAI)
                "83f20f44975d03b1b09e64809b757c47f942beea",
                // component id (sDAI Vault)
                "83f20f44975d03b1b09e64809b757c47f942beea",
                // receiver
                "1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e",
                // is_deposit flag
                "01"
            ))
        );

        // Test withdraw (sDAI -> DAI)
        let withdraw_swap = Swap {
            component: sdai_component,
            token_in: sdai_token.clone(),
            token_out: dai_token.clone(),
            split: 0f64,
        };

        let withdraw_context = EncodingContext {
            receiver: Bytes::from("0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e"),
            exact_out: false,
            router_address: Bytes::zero(20),
            group_token_in: sdai_token,
            group_token_out: dai_token,
        };

        let encoded_withdraw = encoder
            .encode_swap(withdraw_swap, withdraw_context)
            .unwrap();
        let hex_withdraw = encode(&encoded_withdraw);

        // For a vault withdrawal, we expect the basic parameters plus a deposit flag (0)
        assert_eq!(
            hex_withdraw,
            String::from(concat!(
                // token in (sDAI)
                "83f20f44975d03b1b09e64809b757c47f942beea",
                // token out (DAI)
                "6b175474e89094c44da98b954eedeac495271d0f",
                // component id (sDAI Vault)
                "83f20f44975d03b1b09e64809b757c47f942beea",
                // receiver
                "1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e",
                // is_deposit flag
                "00"
            ))
        );

        // Test for DAI Lite PSM component with fee
        let mut static_attributes: HashMap<String, Bytes> = HashMap::new();
        let fee = BigInt::from(100); // 1% fee
        static_attributes.insert("fee".into(), Bytes::from(fee.to_signed_bytes_be()));

        let psm_component = ProtocolComponent {
            id: String::from("0xf6e72Db5454dd049d0788e411b06CfAF16853042"), // DAI Lite PSM address
            protocol_system: String::from("vm:sky"),
            static_attributes,
            ..Default::default()
        };

        let dai_token = Bytes::from("0x6B175474E89094C44Da98b954EedeAC495271d0F"); // DAI
        let usdc_token = Bytes::from("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"); // USDC

        // Test DAI -> USDC swap
        let psm_swap = Swap {
            component: psm_component,
            token_in: dai_token.clone(),
            token_out: usdc_token.clone(),
            split: 0f64,
        };

        let psm_context = EncodingContext {
            receiver: Bytes::from("0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e"),
            exact_out: false,
            router_address: Bytes::zero(20),
            group_token_in: dai_token,
            group_token_out: usdc_token,
        };

        let encoded_psm = encoder
            .encode_swap(psm_swap, psm_context)
            .unwrap();
        let hex_psm = encode(&encoded_psm);

        // For a PSM component, we expect the basic parameters plus a fee
        assert_eq!(
            hex_psm,
            String::from(concat!(
                // token in (DAI)
                "6b175474e89094c44da98b954eedeac495271d0f",
                // token out (USDC)
                "a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                // component id (DAI Lite PSM)
                "f6e72db5454dd049d0788e411b06cfaf16853042",
                // receiver
                "1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e",
                // fee (1%)
                "000064"
            ))
        );
    }
}
