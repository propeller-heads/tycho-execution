#![allow(dead_code)]
pub mod encoding;

use std::str::FromStr;

use alloy::{
    primitives::{B256, U256},
    signers::local::PrivateKeySigner,
};
use tycho_common::{models::Chain, Bytes};
use tycho_execution::encoding::{
    evm::encoder_builders::TychoRouterEncoderBuilder, models::UserTransferType,
    tycho_encoder::TychoEncoder,
};

pub fn router_address() -> Bytes {
    Bytes::from_str("0x3Ede3eCa2a72B3aeCC820E955B36f38437D01395").unwrap()
}

pub fn bob_address() -> Bytes {
    Bytes::from_str("0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e").unwrap()
}

pub fn alice_address() -> Bytes {
    Bytes::from_str("0xcd09f75E2BF2A4d11F3AB23f1389FcC1621c0cc2").unwrap()
}

pub fn eth_chain() -> Chain {
    Chain::Ethereum
}

pub fn eth() -> Bytes {
    Bytes::from_str("0x0000000000000000000000000000000000000000").unwrap()
}

pub fn weth() -> Bytes {
    Bytes::from_str("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2").unwrap()
}

pub fn usdc() -> Bytes {
    Bytes::from_str("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48").unwrap()
}

pub fn dai() -> Bytes {
    Bytes::from_str("0x6b175474e89094c44da98b954eedeac495271d0f").unwrap()
}

pub fn wbtc() -> Bytes {
    Bytes::from_str("0x2260fac5e5542a773aa44fbcfedf7c193bc2c599").unwrap()
}

pub fn pepe() -> Bytes {
    Bytes::from_str("0x6982508145454Ce325dDbE47a25d4ec3d2311933").unwrap()
}

pub fn usdt() -> Bytes {
    Bytes::from_str("0xdAC17F958D2ee523a2206206994597C13D831ec7").unwrap()
}

pub fn ondo() -> Bytes {
    Bytes::from_str("0xfAbA6f8e4a5E8Ab82F62fe7C39859FA577269BE3").unwrap()
}

pub fn get_signer() -> PrivateKeySigner {
    // Set up a mock private key for signing (Alice's pk in our contract tests)
    let private_key =
        "0x123456789abcdef123456789abcdef123456789abcdef123456789abcdef1234".to_string();

    let pk = B256::from_str(&private_key).unwrap();
    PrivateKeySigner::from_bytes(&pk).unwrap()
}

pub fn get_tycho_router_encoder(user_transfer_type: UserTransferType) -> Box<dyn TychoEncoder> {
    TychoRouterEncoderBuilder::new()
        .chain(Chain::Ethereum)
        .user_transfer_type(user_transfer_type)
        .executors_file_path("config/test_executor_addresses.json".to_string())
        .router_address(router_address())
        .build()
        .expect("Failed to build encoder")
}

/// Builds the complete Bebop calldata in the format expected by the encoder
/// Returns: [ partial_fill_offset (u8) | original_taker_amount (U256) | calldata (bytes (selector +
/// ABI encoded params)) ]
pub fn build_bebop_calldata(
    calldata: &[u8],
    partial_fill_offset: u8,
    original_taker_amount: U256,
) -> Bytes {
    let mut user_data = Vec::with_capacity(1 + 32 + calldata.len());
    user_data.push(partial_fill_offset);
    user_data.extend_from_slice(&original_taker_amount.to_be_bytes::<32>());
    user_data.extend_from_slice(calldata);

    Bytes::from(user_data)
}
