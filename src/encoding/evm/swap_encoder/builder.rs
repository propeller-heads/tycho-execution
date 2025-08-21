use std::collections::HashMap;

use tycho_common::models::Chain;

use crate::encoding::{
    errors::EncodingError,
    evm::swap_encoder::swap_encoders::{
        BalancerV2SwapEncoder, BalancerV3SwapEncoder, BebopSwapEncoder, CurveSwapEncoder,
        EkuboSwapEncoder, HashflowSwapEncoder, MaverickV2SwapEncoder, UniswapV2SwapEncoder,
        UniswapV3SwapEncoder, UniswapV4SwapEncoder,
    },
    swap_encoder::SwapEncoder,
};

/// Builds a `SwapEncoder` for the given protocol system and executor address.
pub struct SwapEncoderBuilder {
    protocol_system: String,
    executor_address: String,
    chain: Chain,
    config: Option<HashMap<String, String>>,
}

impl SwapEncoderBuilder {
    pub fn new(
        protocol_system: &str,
        executor_address: &str,
        chain: Chain,
        config: Option<HashMap<String, String>>,
    ) -> Self {
        SwapEncoderBuilder {
            protocol_system: protocol_system.to_string(),
            executor_address: executor_address.to_string(),
            chain,
            config,
        }
    }

    pub fn build(self) -> Result<Box<dyn SwapEncoder>, EncodingError> {
        match self.protocol_system.as_str() {
            "uniswap_v2" => Ok(Box::new(UniswapV2SwapEncoder::new(
                self.executor_address,
                self.chain,
                self.config,
            )?)),
            "sushiswap_v2" => Ok(Box::new(UniswapV2SwapEncoder::new(
                self.executor_address,
                self.chain,
                self.config,
            )?)),
            "pancakeswap_v2" => Ok(Box::new(UniswapV2SwapEncoder::new(
                self.executor_address,
                self.chain,
                self.config,
            )?)),
            "vm:balancer_v2" => Ok(Box::new(BalancerV2SwapEncoder::new(
                self.executor_address,
                self.chain,
                self.config,
            )?)),
            "uniswap_v3" => Ok(Box::new(UniswapV3SwapEncoder::new(
                self.executor_address,
                self.chain,
                self.config,
            )?)),
            "pancakeswap_v3" => Ok(Box::new(UniswapV3SwapEncoder::new(
                self.executor_address,
                self.chain,
                self.config,
            )?)),
            "uniswap_v4" => Ok(Box::new(UniswapV4SwapEncoder::new(
                self.executor_address,
                self.chain,
                self.config,
            )?)),
            "ekubo_v2" => {
                Ok(Box::new(EkuboSwapEncoder::new(self.executor_address, self.chain, self.config)?))
            }
            "vm:curve" => {
                Ok(Box::new(CurveSwapEncoder::new(self.executor_address, self.chain, self.config)?))
            }
            "vm:maverick_v2" => Ok(Box::new(MaverickV2SwapEncoder::new(
                self.executor_address,
                self.chain,
                self.config,
            )?)),
            "vm:balancer_v3" => Ok(Box::new(BalancerV3SwapEncoder::new(
                self.executor_address,
                self.chain,
                self.config,
            )?)),
            "rfq:bebop" => {
                Ok(Box::new(BebopSwapEncoder::new(self.executor_address, self.chain, self.config)?))
            }
            "rfq:hashflow" => Ok(Box::new(HashflowSwapEncoder::new(
                self.executor_address,
                self.chain,
                self.config,
            )?)),
            _ => Err(EncodingError::FatalError(format!(
                "Unknown protocol system: {}",
                self.protocol_system
            ))),
        }
    }
}
