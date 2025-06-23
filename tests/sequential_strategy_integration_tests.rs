mod common;
use std::{collections::HashMap, str::FromStr};

use alloy::hex::encode;
use num_bigint::{BigInt, BigUint};
use tycho_common::{models::protocol::ProtocolComponent, Bytes};
use tycho_execution::encoding::{
    evm::utils::write_calldata_to_file,
    models::{Solution, Swap, UserTransferType},
};

use crate::common::{
    encoding::encode_tycho_router_call, eth, eth_chain, get_signer, get_tycho_router_encoder, usdc,
    wbtc, weth,
};

#[test]
fn test_sequential_swap_strategy_encoder() {
    // Note: This test does not assert anything. It is only used to obtain integration
    // test data for our router solidity test.
    //
    // Performs a sequential swap from WETH to USDC though WBTC using USV2 pools
    //
    //   WETH ───(USV2)──> WBTC ───(USV2)──> USDC

    let weth = weth();
    let wbtc = wbtc();
    let usdc = usdc();

    let swap_weth_wbtc = Swap {
        component: ProtocolComponent {
            id: "0xBb2b8038a1640196FbE3e38816F3e67Cba72D940".to_string(),
            protocol_system: "uniswap_v2".to_string(),
            ..Default::default()
        },
        token_in: weth.clone(),
        token_out: wbtc.clone(),
        split: 0f64,
        user_data: None,
    };
    let swap_wbtc_usdc = Swap {
        component: ProtocolComponent {
            id: "0x004375Dff511095CC5A197A54140a24eFEF3A416".to_string(),
            protocol_system: "uniswap_v2".to_string(),
            ..Default::default()
        },
        token_in: wbtc.clone(),
        token_out: usdc.clone(),
        split: 0f64,
        user_data: None,
    };
    let encoder = get_tycho_router_encoder(UserTransferType::TransferFromPermit2);

    let solution = Solution {
        exact_out: false,
        given_token: weth,
        given_amount: BigUint::from_str("1_000000000000000000").unwrap(),
        checked_token: usdc,
        checked_amount: BigUint::from_str("26173932").unwrap(),
        sender: Bytes::from_str("0xcd09f75E2BF2A4d11F3AB23f1389FcC1621c0cc2").unwrap(),
        receiver: Bytes::from_str("0xcd09f75E2BF2A4d11F3AB23f1389FcC1621c0cc2").unwrap(),
        swaps: vec![swap_weth_wbtc, swap_wbtc_usdc],
        ..Default::default()
    };

    let encoded_solution = encoder
        .encode_solutions(vec![solution.clone()])
        .unwrap()[0]
        .clone();

    let calldata = encode_tycho_router_call(
        eth_chain().id,
        encoded_solution,
        &solution,
        UserTransferType::TransferFromPermit2,
        eth(),
        Some(get_signer()),
    )
    .unwrap()
    .data;

    let hex_calldata = encode(&calldata);
    write_calldata_to_file("test_sequential_swap_strategy_encoder", hex_calldata.as_str());
}

#[test]
fn test_sequential_swap_strategy_encoder_no_permit2() {
    // Performs a sequential swap from WETH to USDC though WBTC using USV2 pools
    //
    //   WETH ───(USV2)──> WBTC ───(USV2)──> USDC

    let weth = weth();
    let wbtc = wbtc();
    let usdc = usdc();

    let swap_weth_wbtc = Swap {
        component: ProtocolComponent {
            id: "0xBb2b8038a1640196FbE3e38816F3e67Cba72D940".to_string(),
            protocol_system: "uniswap_v2".to_string(),
            ..Default::default()
        },
        token_in: weth.clone(),
        token_out: wbtc.clone(),
        split: 0f64,
        user_data: None,
    };
    let swap_wbtc_usdc = Swap {
        component: ProtocolComponent {
            id: "0x004375Dff511095CC5A197A54140a24eFEF3A416".to_string(),
            protocol_system: "uniswap_v2".to_string(),
            ..Default::default()
        },
        token_in: wbtc.clone(),
        token_out: usdc.clone(),
        split: 0f64,
        user_data: None,
    };
    let encoder = get_tycho_router_encoder(UserTransferType::TransferFrom);

    let solution = Solution {
        exact_out: false,
        given_token: weth,
        given_amount: BigUint::from_str("1_000000000000000000").unwrap(),
        checked_token: usdc,
        checked_amount: BigUint::from_str("26173932").unwrap(),
        sender: Bytes::from_str("0xcd09f75E2BF2A4d11F3AB23f1389FcC1621c0cc2").unwrap(),
        receiver: Bytes::from_str("0xcd09f75E2BF2A4d11F3AB23f1389FcC1621c0cc2").unwrap(),
        swaps: vec![swap_weth_wbtc, swap_wbtc_usdc],
        ..Default::default()
    };

    let encoded_solution = encoder
        .encode_solutions(vec![solution.clone()])
        .unwrap()[0]
        .clone();

    let calldata = encode_tycho_router_call(
        eth_chain().id,
        encoded_solution,
        &solution,
        UserTransferType::TransferFrom,
        eth(),
        None,
    )
    .unwrap()
    .data;

    let hex_calldata = encode(&calldata);

    let expected = String::from(concat!(
        "e21dd0d3",                                                         /* function selector */
        "0000000000000000000000000000000000000000000000000de0b6b3a7640000", /* amount in */
        "000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", // token in
        "000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", // token ou
        "00000000000000000000000000000000000000000000000000000000018f61ec", /* min amount out */
        "0000000000000000000000000000000000000000000000000000000000000000", // wrap
        "0000000000000000000000000000000000000000000000000000000000000000", // unwrap
        "000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2", // receiver
        "0000000000000000000000000000000000000000000000000000000000000001", /* transfer from
                                                                             * needed */
        "0000000000000000000000000000000000000000000000000000000000000120", /* length ple
                                                                             * encode */
        "00000000000000000000000000000000000000000000000000000000000000a8",
        // swap 1
        "0052",                                     // swap length
        "5615deb798bb3e4dfa0139dfa1b3d433cc23b72f", // executor address
        "c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", // token in
        "bb2b8038a1640196fbe3e38816f3e67cba72d940", // component id
        "004375dff511095cc5a197a54140a24efef3a416", // receiver (next pool)
        "00",                                       // zero to one
        "00",                                       // transfer type TransferFrom
        // swap 2
        "0052",                                             // swap length
        "5615deb798bb3e4dfa0139dfa1b3d433cc23b72f",         // executor address
        "2260fac5e5542a773aa44fbcfedf7c193bc2c599",         // token in
        "004375dff511095cc5a197a54140a24efef3a416",         // component id
        "cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2",         // receiver (final user)
        "01",                                               // zero to one
        "02",                                               // transfer type None
        "000000000000000000000000000000000000000000000000", // padding
    ));

    assert_eq!(hex_calldata, expected);
    write_calldata_to_file(
        "test_sequential_swap_strategy_encoder_no_permit2",
        hex_calldata.as_str(),
    );
}

#[test]
fn test_sequential_strategy_cyclic_swap() {
    // This test has start and end tokens that are the same
    // The flow is:
    // USDC -> WETH -> USDC  using two pools

    let weth = weth();
    let usdc = usdc();

    // Create two Uniswap V3 pools for the cyclic swap
    // USDC -> WETH (Pool 1)
    let swap_usdc_weth = Swap {
        component: ProtocolComponent {
            id: "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640".to_string(), /* USDC-WETH USV3
                                                                           * Pool 1 */
            protocol_system: "uniswap_v3".to_string(),
            static_attributes: {
                let mut attrs = HashMap::new();
                attrs
                    .insert("fee".to_string(), Bytes::from(BigInt::from(500).to_signed_bytes_be()));
                attrs
            },
            ..Default::default()
        },
        token_in: usdc.clone(),
        token_out: weth.clone(),
        split: 0f64,
        user_data: None,
    };

    // WETH -> USDC (Pool 2)
    let swap_weth_usdc = Swap {
        component: ProtocolComponent {
            id: "0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8".to_string(), /* USDC-WETH USV3
                                                                           * Pool 2 */
            protocol_system: "uniswap_v3".to_string(),
            static_attributes: {
                let mut attrs = HashMap::new();
                attrs.insert(
                    "fee".to_string(),
                    Bytes::from(BigInt::from(3000).to_signed_bytes_be()),
                );
                attrs
            },
            ..Default::default()
        },
        token_in: weth.clone(),
        token_out: usdc.clone(),
        split: 0f64,
        user_data: None,
    };

    let encoder = get_tycho_router_encoder(UserTransferType::TransferFromPermit2);

    let solution = Solution {
        exact_out: false,
        given_token: usdc.clone(),
        given_amount: BigUint::from_str("100000000").unwrap(), // 100 USDC (6 decimals)
        checked_token: usdc.clone(),
        checked_amount: BigUint::from_str("99389294").unwrap(), /* Expected output
                                                                 * from test */
        swaps: vec![swap_usdc_weth, swap_weth_usdc],
        sender: Bytes::from_str("0xcd09f75E2BF2A4d11F3AB23f1389FcC1621c0cc2").unwrap(),
        receiver: Bytes::from_str("0xcd09f75E2BF2A4d11F3AB23f1389FcC1621c0cc2").unwrap(),
        ..Default::default()
    };

    let encoded_solution = encoder
        .encode_solutions(vec![solution.clone()])
        .unwrap()[0]
        .clone();

    let calldata = encode_tycho_router_call(
        eth_chain().id,
        encoded_solution,
        &solution,
        UserTransferType::TransferFromPermit2,
        eth(),
        Some(get_signer()),
    )
    .unwrap()
    .data;
    let hex_calldata = alloy::hex::encode(&calldata);
    let expected_input = [
        "51bcc7b6",                                                         // selector
        "0000000000000000000000000000000000000000000000000000000005f5e100", // given amount
        "000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", // given token
        "000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", // checked token
        "0000000000000000000000000000000000000000000000000000000005ec8f6e", // min amount out
        "0000000000000000000000000000000000000000000000000000000000000000", // wrap action
        "0000000000000000000000000000000000000000000000000000000000000000", // unwrap action
        "000000000000000000000000cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2", // receiver
    ]
    .join("");

    let expected_swaps = [
        "00000000000000000000000000000000000000000000000000000000000000d6",  // length of ple encoded swaps without padding
        "0069",  // ple encoded swaps
        "2e234dae75c793f67a35089c9d99245e1c58470b", // executor address
        "a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", // token in
        "c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", // token out
        "0001f4",                                   // pool fee
        "3ede3eca2a72b3aecc820e955b36f38437d01395", // receiver
        "88e6a0c2ddd26feeb64f039a2c41296fcb3f5640", // component id
        "01",                                       // zero2one
        "00",                                       // transfer type TransferFrom
        "0069",                                     // ple encoded swaps
        "2e234dae75c793f67a35089c9d99245e1c58470b", // executor address
        "c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", // token in
        "a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", // token out
        "000bb8",                                   // pool fee
        "cd09f75e2bf2a4d11f3ab23f1389fcc1621c0cc2", // receiver
        "8ad599c3a0ff1de082011efddc58f1908eb6e6d8", // component id
        "00",                                       // zero2one
        "01",                                       // transfer type Transfer
        "00000000000000000000",                     // padding
    ]
        .join("");

    assert_eq!(hex_calldata[..456], expected_input);
    assert_eq!(hex_calldata[1224..], expected_swaps);
    write_calldata_to_file("test_sequential_strategy_cyclic_swap", hex_calldata.as_str());
}
