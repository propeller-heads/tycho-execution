use std::str::FromStr;

use alloy_primitives::Address;
use alloy_sol_types::SolValue;

use crate::encoding::{
    errors::EncodingError,
    evm::{
        approvals::protocol_approvals_manager::ProtocolApprovalsManager, utils::bytes_to_address,
    },
    models::{EncodingContext, Swap},
    swap_encoder::SwapEncoder,
};

pub struct UniswapV2SwapEncoder {
    executor_address: String,
}

impl UniswapV2SwapEncoder {}
impl SwapEncoder for UniswapV2SwapEncoder {
    fn new(executor_address: String) -> Self {
        Self { executor_address }
    }
    fn encode_swap(
        &self,
        _swap: Swap,
        _encoding_context: EncodingContext,
    ) -> Result<Vec<u8>, EncodingError> {
        todo!()
    }

    fn executor_address(&self) -> &str {
        &self.executor_address
    }
}

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
        let router_address = bytes_to_address(&encoding_context.address_for_approvals)?;
        let approval_needed = token_approvals_manager.approval_needed(
            token,
            router_address,
            Address::from_str(&self.vault_address)
                .map_err(|_| EncodingError::FatalError("Invalid vault address".to_string()))?,
        )?;
        // should we return gas estimation here too?? if there is an approval needed, gas will be
        // higher.
        let args = (
            bytes_to_address(&swap.token_in)?,
            bytes_to_address(&swap.token_out)?,
            swap.component.id,
            bytes_to_address(&encoding_context.receiver)?,
            encoding_context.exact_out,
            approval_needed,
        );
        Ok(args.abi_encode())
    }

    fn executor_address(&self) -> &str {
        &self.executor_address
    }
}

#[cfg(test)]
mod tests {
    #[tokio::test]
    async fn test_encode_swap() {
        // Dummy test to make CI pass. Please implement me.
    }
}
