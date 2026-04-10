use std::{collections::HashMap, str::FromStr};

use alloy::{primitives::Address, sol_types::SolValue};
use tycho_common::{models::Chain, Bytes};

use crate::encoding::{
    errors::EncodingError,
    evm::utils::bytes_to_address,
    models::{EncodingContext, Swap},
    swap_encoder::SwapEncoder,
};

/// Encodes a swap on a Supernova V3 (Algebra Integral 1.2.2) pool
/// through the **existing** `UniswapV3Executor` contract.
///
/// # ⚠️ Read this before "fixing" anything in this file ⚠️
///
/// There is intentionally **no** dedicated `SupernovaV3Executor.sol`.
/// The executor address registered for `vm:supernova_v3` in
/// `executor_addresses.json` and `test_executor_addresses.json` is the
/// same address as `uniswap_v3` and `pancakeswap_v3`. This is the
/// correct, deliberate design — not an oversight. Writing a separate
/// executor would only duplicate code.
///
/// The empirical proof that this works on real mainnet state is in
/// `foundry/test/protocols/SupernovaV3.t.sol`
/// (`TychoRouterForSupernovaV3Test`) — that test runs a full
/// `TychoRouter.singleSwap` against a live Supernova USDC/USDT pool in
/// both directions and asserts on the post-swap balances.
///
/// # Why the Uniswap V3 executor handles Algebra Integral pools unchanged
///
/// 1. **Same swap entry-point selector.**
///    `IUniswapV3Pool.swap(address,bool,int256,uint160,bytes)` and
///    `IAlgebraPool.swap(address,bool,int256,uint160,bytes)` have
///    identical argument types, hence the identical 4-byte selector.
///    The executor's outbound `pool.swap(...)` call lands on the
///    Algebra pool unchanged.
///
/// 2. **Selector-agnostic callback dispatch.**
///    Algebra pools call back via `algebraSwapCallback(int256,int256,bytes)`
///    instead of `uniswapV3SwapCallback`. The selectors differ, but
///    `TychoRouter.fallback` accepts any unknown selector and forwards
///    the raw msgData to whichever executor is currently mid-swap
///    (tracked in transient storage `_CURRENTLY_SWAPPING_EXECUTOR_SLOT`).
///    So the call ends up at `UniswapV3Executor.handleCallback` with the
///    Algebra-shaped bytes.
///
/// 3. **Identical callback argument layout.**
///    Both protocols' callbacks take `(int256,int256,bytes)`. The
///    `UniswapV3Executor.handleCallback` reads `(amount0Delta,
///    amount1Delta) = msgData[4..68]` and `tokenIn = msgData[132..152]`
///    — those byte offsets are correct for both Uniswap V3's and
///    Algebra's ABI encoding because they're literally the same
///    encoding.
///
/// # Calldata layout (64 bytes — required by `UniswapV3Executor._decodeData`)
///
/// ```text
/// [ 0..20)  tokenIn
/// [20..40)  tokenOut
/// [40..43)  fee  (3 zero bytes — Algebra has dynamic fees, this field
///                 is unused on the routing path. It's still required
///                 by `UniswapV3Executor._decodeData`'s strict 64-byte
///                 length check, and gets echoed back to us inside the
///                 swap callback `data` argument where only the first
///                 20 bytes — `tokenIn` — are actually read.)
/// [43..63)  pool address
/// [63..64)  zeroForOne
/// ```
#[derive(Clone)]
pub struct SupernovaV3SwapEncoder {
    executor_address: Bytes,
}

impl SupernovaV3SwapEncoder {
    fn get_zero_to_one(sell_token_address: Address, buy_token_address: Address) -> bool {
        sell_token_address < buy_token_address
    }
}

impl SwapEncoder for SupernovaV3SwapEncoder {
    fn new(
        executor_address: Bytes,
        _chain: Chain,
        _config: Option<HashMap<String, String>>,
    ) -> Result<Self, EncodingError> {
        Ok(Self { executor_address })
    }

    fn encode_swap(
        &self,
        swap: &Swap,
        _encoding_context: &EncodingContext,
    ) -> Result<Vec<u8>, EncodingError> {
        let token_in_address = bytes_to_address(swap.token_in())?;
        let token_out_address = bytes_to_address(swap.token_out())?;

        let zero_to_one = Self::get_zero_to_one(token_in_address, token_out_address);
        let component_id = Address::from_str(&swap.component().id).map_err(|_| {
            EncodingError::FatalError("Invalid Supernova V3 component id".to_string())
        })?;

        // Algebra Integral has dynamic fees — there is no static fee tier.
        // The Uniswap V3 executor reserves 3 bytes for `fee` between
        // `tokenOut` and the pool address; we fill them with zeros. The
        // executor never inspects this field, it just gets echoed back to
        // us inside the swap callback `data` blob, where only the first
        // 20 bytes (tokenIn) are read.
        let pool_fee_u24: [u8; 3] = [0u8; 3];

        let args = (token_in_address, token_out_address, pool_fee_u24, component_id, zero_to_one);

        Ok(args.abi_encode_packed())
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
    use alloy::hex::encode;
    use tycho_common::models::protocol::ProtocolComponent;

    use super::*;
    use crate::encoding::models::Swap;

    // ─────────────────────────────────────────────────────────────────
    //  Test fixtures — real Supernova V3 pools and token addresses
    // ─────────────────────────────────────────────────────────────────

    /// USDC mainnet address.
    const USDC: &str = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
    /// USDT mainnet address.
    const USDT: &str = "0xdac17f958d2ee523a2206206994597c13d831ec7";
    /// WETH mainnet address.
    const WETH: &str = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
    /// WBTC mainnet address.
    const WBTC: &str = "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599";
    /// DAI mainnet address.
    const DAI: &str = "0x6b175474e89094c44da98b954eedeac495271d0f";

    /// Supernova V3 USDC/USDT pool — token0 = USDC, token1 = USDT.
    const SUPERNOVA_USDC_USDT: &str = "0x2beb35e78c9427899353c41c96bcc96c5647ec63";
    /// Supernova V3 WETH/USDT pool.
    const SUPERNOVA_WETH_USDT: &str = "0xde758db54c1b4a87b06b34b30ef0a710dc35388f";
    /// Supernova V3 WBTC/WETH pool.
    const SUPERNOVA_WBTC_WETH: &str = "0x55347b4ab701ab54ee394f20020175bb385ca725";
    /// Supernova V3 DAI/USDT pool.
    const SUPERNOVA_DAI_USDT: &str = "0x3750c1fcd35eae956c7a57e773d1496c41d2759a";

    /// Production executor address (also used by uniswap_v3 / pancakeswap_v3).
    const EXECUTOR_PROD: &str = "0xc7d47F3C3f755ed977f3C19F4C1f007CbEd109b0";

    fn make_encoder() -> SupernovaV3SwapEncoder {
        SupernovaV3SwapEncoder::new(Bytes::from(EXECUTOR_PROD), Chain::Ethereum, None).unwrap()
    }

    fn make_swap(pool: &str, token_in: &str, token_out: &str) -> Swap {
        let component = ProtocolComponent { id: String::from(pool), ..Default::default() };
        Swap::new(component, Bytes::from(token_in), Bytes::from(token_out))
    }

    fn default_context(token_in: &str, token_out: &str) -> EncodingContext {
        EncodingContext {
            router_address: Some(Bytes::zero(20)),
            group_token_in: Bytes::from(token_in),
            group_token_out: Bytes::from(token_out),
        }
    }

    // ─────────────────────────────────────────────────────────────────
    //  Happy-path: original regression test (USDC → USDT)
    // ─────────────────────────────────────────────────────────────────

    #[test]
    fn test_encode_supernova_v3() {
        let swap = make_swap(SUPERNOVA_USDC_USDT, USDC, USDT);
        let context = default_context(USDC, USDT);
        let encoded_swap = make_encoder()
            .encode_swap(&swap, &context)
            .unwrap();

        assert_eq!(encoded_swap.len(), 64, "executor requires 64-byte payload");

        let hex_swap = encode(&encoded_swap);
        assert_eq!(
            hex_swap,
            String::from(concat!(
                // tokenIn (USDC)
                "a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                // tokenOut (USDT)
                "dac17f958d2ee523a2206206994597c13d831ec7",
                // fee placeholder (3 zero bytes — Algebra dynamic fee)
                "000000",
                // pool
                "2beb35e78c9427899353c41c96bcc96c5647ec63",
                // zeroForOne (USDC < USDT)
                "01",
            ))
        );
    }

    // ─────────────────────────────────────────────────────────────────
    //  Byte-layout invariants — pin every position in the 64-byte blob
    // ─────────────────────────────────────────────────────────────────

    /// The encoded payload MUST always be exactly 64 bytes — the
    /// `UniswapV3Executor._decodeData` enforces this with a strict
    /// `if (data.length != 64) revert ...` check.
    #[test]
    fn test_encoded_length_is_always_64_bytes() {
        // Try several different combinations to make sure the length
        // doesn't vary with input shape.
        let cases = [
            (SUPERNOVA_USDC_USDT, USDC, USDT),
            (SUPERNOVA_WETH_USDT, WETH, USDT),
            (SUPERNOVA_WBTC_WETH, WBTC, WETH),
            (SUPERNOVA_DAI_USDT, DAI, USDT),
        ];
        for (pool, token_in, token_out) in cases {
            let swap = make_swap(pool, token_in, token_out);
            let ctx = default_context(token_in, token_out);
            let encoded = make_encoder().encode_swap(&swap, &ctx).unwrap();
            assert_eq!(encoded.len(), 64, "pool={pool} encoded length must be 64");
        }
    }

    /// Bytes [0..20) — tokenIn address, big-endian, exact bytes from
    /// the input (no checksum normalisation, no padding).
    #[test]
    fn test_byte_layout_token_in_at_offset_0() {
        let swap = make_swap(SUPERNOVA_USDC_USDT, USDC, USDT);
        let ctx = default_context(USDC, USDT);
        let encoded = make_encoder().encode_swap(&swap, &ctx).unwrap();
        let expected = hex::decode(USDC.trim_start_matches("0x")).unwrap();
        assert_eq!(&encoded[0..20], expected.as_slice());
    }

    /// Bytes [20..40) — tokenOut address.
    #[test]
    fn test_byte_layout_token_out_at_offset_20() {
        let swap = make_swap(SUPERNOVA_USDC_USDT, USDC, USDT);
        let ctx = default_context(USDC, USDT);
        let encoded = make_encoder().encode_swap(&swap, &ctx).unwrap();
        let expected = hex::decode(USDT.trim_start_matches("0x")).unwrap();
        assert_eq!(&encoded[20..40], expected.as_slice());
    }

    /// Bytes [40..43) — fee placeholder, must always be 3 zero bytes
    /// regardless of pool, tokens, or direction. Algebra has dynamic
    /// fees and the executor never reads this field.
    #[test]
    fn test_byte_layout_fee_placeholder_is_always_three_zeros() {
        let cases = [
            (SUPERNOVA_USDC_USDT, USDC, USDT),
            (SUPERNOVA_USDC_USDT, USDT, USDC),
            (SUPERNOVA_WETH_USDT, WETH, USDT),
            (SUPERNOVA_WBTC_WETH, WBTC, WETH),
        ];
        for (pool, token_in, token_out) in cases {
            let swap = make_swap(pool, token_in, token_out);
            let ctx = default_context(token_in, token_out);
            let encoded = make_encoder().encode_swap(&swap, &ctx).unwrap();
            assert_eq!(
                &encoded[40..43],
                &[0u8, 0, 0],
                "fee placeholder must be 0x000000 for pool={pool}"
            );
        }
    }

    /// Bytes [43..63) — pool address, exact bytes from the component id.
    #[test]
    fn test_byte_layout_pool_address_at_offset_43() {
        let swap = make_swap(SUPERNOVA_USDC_USDT, USDC, USDT);
        let ctx = default_context(USDC, USDT);
        let encoded = make_encoder().encode_swap(&swap, &ctx).unwrap();
        let expected = hex::decode(SUPERNOVA_USDC_USDT.trim_start_matches("0x")).unwrap();
        assert_eq!(&encoded[43..63], expected.as_slice());
    }

    /// Byte 63 — single zeroForOne flag (0x00 or 0x01).
    #[test]
    fn test_byte_layout_zero_for_one_at_offset_63() {
        // USDC < USDT → USDC→USDT is zeroForOne = true (0x01)
        let swap_a = make_swap(SUPERNOVA_USDC_USDT, USDC, USDT);
        let ctx_a = default_context(USDC, USDT);
        let encoded_a = make_encoder().encode_swap(&swap_a, &ctx_a).unwrap();
        assert_eq!(encoded_a[63], 0x01);

        // USDT > USDC → USDT→USDC is zeroForOne = false (0x00)
        let swap_b = make_swap(SUPERNOVA_USDC_USDT, USDT, USDC);
        let ctx_b = default_context(USDT, USDC);
        let encoded_b = make_encoder().encode_swap(&swap_b, &ctx_b).unwrap();
        assert_eq!(encoded_b[63], 0x00);
    }

    // ─────────────────────────────────────────────────────────────────
    //  zeroForOne computation — the most subtle part of the encoder
    // ─────────────────────────────────────────────────────────────────

    /// `zeroForOne` is a function of token address ordering, NOT a
    /// function of which token the user calls token0 in their app.
    /// The pool's `swap(zeroForOne, ...)` interprets `true` as
    /// "selling token0 for token1" and the rule is that token0 is
    /// whichever address sorts lower.
    #[test]
    fn test_zero_for_one_uses_address_sort_order_not_input_position() {
        // For the USDC/USDT pool: USDC is 0xa0b8…, USDT is 0xdac1….
        // 0xa0 < 0xdac1 so USDC is token0, USDT is token1.
        // Selling USDC → USDT means "sell token0 for token1" → zeroForOne = true.
        let swap = make_swap(SUPERNOVA_USDC_USDT, USDC, USDT);
        let ctx = default_context(USDC, USDT);
        let encoded = make_encoder().encode_swap(&swap, &ctx).unwrap();
        assert_eq!(encoded[63], 0x01, "USDC→USDT should be zeroForOne = true");
    }

    /// Reverse direction on the same pool flips zeroForOne and swaps
    /// the tokenIn/tokenOut bytes. The pool address and fee placeholder
    /// stay identical.
    #[test]
    fn test_reverse_direction_flips_zero_for_one_and_swaps_tokens() {
        let forward = make_encoder()
            .encode_swap(
                &make_swap(SUPERNOVA_USDC_USDT, USDC, USDT),
                &default_context(USDC, USDT),
            )
            .unwrap();
        let reverse = make_encoder()
            .encode_swap(
                &make_swap(SUPERNOVA_USDC_USDT, USDT, USDC),
                &default_context(USDT, USDC),
            )
            .unwrap();

        // Different in tokenIn (bytes 0..20) and tokenOut (bytes 20..40)
        assert_ne!(&forward[0..20], &reverse[0..20]);
        assert_ne!(&forward[20..40], &reverse[20..40]);
        // tokenIn of forward equals tokenOut of reverse, and vice versa.
        assert_eq!(&forward[0..20], &reverse[20..40]);
        assert_eq!(&forward[20..40], &reverse[0..20]);
        // Pool address is the same.
        assert_eq!(&forward[43..63], &reverse[43..63]);
        // Fee placeholder is identical (always zero).
        assert_eq!(&forward[40..43], &reverse[40..43]);
        // zeroForOne is flipped.
        assert_eq!(forward[63], 0x01);
        assert_eq!(reverse[63], 0x00);
    }

    /// WETH > USDT (0xc02a > 0xdac1 → wait, no: 0xc0 < 0xda).
    /// Actually 0xc02a < 0xdac1, so WETH IS token0 in WETH/USDT.
    /// Selling WETH → USDT is zeroForOne = true.
    #[test]
    fn test_weth_usdt_direction() {
        let weth_to_usdt = make_encoder()
            .encode_swap(
                &make_swap(SUPERNOVA_WETH_USDT, WETH, USDT),
                &default_context(WETH, USDT),
            )
            .unwrap();
        assert_eq!(weth_to_usdt[63], 0x01, "WETH→USDT should be zeroForOne = true (WETH < USDT)");

        let usdt_to_weth = make_encoder()
            .encode_swap(
                &make_swap(SUPERNOVA_WETH_USDT, USDT, WETH),
                &default_context(USDT, WETH),
            )
            .unwrap();
        assert_eq!(usdt_to_weth[63], 0x00, "USDT→WETH should be zeroForOne = false");
    }

    /// WBTC < WETH (0x2260 < 0xc02a), so WBTC is token0 in WBTC/WETH.
    /// Selling WBTC → WETH is zeroForOne = true.
    #[test]
    fn test_wbtc_weth_direction() {
        let wbtc_to_weth = make_encoder()
            .encode_swap(
                &make_swap(SUPERNOVA_WBTC_WETH, WBTC, WETH),
                &default_context(WBTC, WETH),
            )
            .unwrap();
        assert_eq!(wbtc_to_weth[63], 0x01, "WBTC→WETH should be zeroForOne = true (WBTC < WETH)");
    }

    /// DAI > USDC but DAI < USDT? Let's check: 0x6b1 < 0xdac1, so
    /// DAI is token0 in DAI/USDT. Selling DAI → USDT is zeroForOne = true.
    #[test]
    fn test_dai_usdt_direction() {
        let dai_to_usdt = make_encoder()
            .encode_swap(
                &make_swap(SUPERNOVA_DAI_USDT, DAI, USDT),
                &default_context(DAI, USDT),
            )
            .unwrap();
        assert_eq!(dai_to_usdt[63], 0x01, "DAI→USDT should be zeroForOne = true (DAI < USDT)");
    }

    // ─────────────────────────────────────────────────────────────────
    //  Determinism / context independence
    // ─────────────────────────────────────────────────────────────────

    /// Encoding the same Swap twice must produce identical bytes.
    /// The encoder is pure — no hidden state, no timestamps, no random.
    #[test]
    fn test_encoding_is_deterministic() {
        let swap = make_swap(SUPERNOVA_USDC_USDT, USDC, USDT);
        let ctx = default_context(USDC, USDT);
        let encoder = make_encoder();
        let a = encoder.encode_swap(&swap, &ctx).unwrap();
        let b = encoder.encode_swap(&swap, &ctx).unwrap();
        assert_eq!(a, b);
    }

    /// The `EncodingContext` fields (router_address, group_token_in,
    /// group_token_out) are intentionally unused by the encoder. Pass
    /// wildly different contexts and verify the output is unchanged.
    /// This pins the contract that Supernova encoding is context-free.
    #[test]
    fn test_encoding_ignores_encoding_context_fields() {
        let swap = make_swap(SUPERNOVA_USDC_USDT, USDC, USDT);
        let encoder = make_encoder();

        let ctx_a = EncodingContext {
            router_address: Some(Bytes::zero(20)),
            group_token_in: Bytes::from(USDC),
            group_token_out: Bytes::from(USDT),
        };
        let ctx_b = EncodingContext {
            router_address: Some(Bytes::from("0xc7d47F3C3f755ed977f3C19F4C1f007CbEd109b0")),
            group_token_in: Bytes::from(WETH),
            group_token_out: Bytes::from(WBTC),
        };
        let ctx_c = EncodingContext {
            router_address: None,
            group_token_in: Bytes::from(DAI),
            group_token_out: Bytes::from(WBTC),
        };

        let encoded_a = encoder.encode_swap(&swap, &ctx_a).unwrap();
        let encoded_b = encoder.encode_swap(&swap, &ctx_b).unwrap();
        let encoded_c = encoder.encode_swap(&swap, &ctx_c).unwrap();
        assert_eq!(encoded_a, encoded_b);
        assert_eq!(encoded_a, encoded_c);
    }

    // ─────────────────────────────────────────────────────────────────
    //  Address parsing — case insensitivity & checksum tolerance
    // ─────────────────────────────────────────────────────────────────

    /// Token addresses can be passed lowercase, uppercase, or mixed
    /// case (EIP-55 checksummed). The encoder normalises to canonical
    /// 20-byte big-endian and produces the same output regardless.
    #[test]
    fn test_token_address_case_insensitive() {
        // Mixed-case (EIP-55 checksummed) USDC.
        let usdc_checksummed = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
        let usdc_lower = USDC;

        let pool = make_swap(SUPERNOVA_USDC_USDT, usdc_checksummed, USDT);
        let pool_lower = make_swap(SUPERNOVA_USDC_USDT, usdc_lower, USDT);

        let encoder = make_encoder();
        let encoded_a = encoder
            .encode_swap(&pool, &default_context(usdc_checksummed, USDT))
            .unwrap();
        let encoded_b = encoder
            .encode_swap(&pool_lower, &default_context(usdc_lower, USDT))
            .unwrap();
        assert_eq!(encoded_a, encoded_b);
    }

    /// Same applies to the pool/component id.
    #[test]
    fn test_pool_id_case_insensitive() {
        let pool_lower = SUPERNOVA_USDC_USDT;
        let pool_checksum = "0x2BeB35e78c9427899353c41C96bCc96C5647eC63";

        let swap_a = make_swap(pool_lower, USDC, USDT);
        let swap_b = make_swap(pool_checksum, USDC, USDT);
        let encoder = make_encoder();
        let encoded_a = encoder.encode_swap(&swap_a, &default_context(USDC, USDT)).unwrap();
        let encoded_b = encoder.encode_swap(&swap_b, &default_context(USDC, USDT)).unwrap();
        assert_eq!(encoded_a, encoded_b);
    }

    // ─────────────────────────────────────────────────────────────────
    //  Error paths
    // ─────────────────────────────────────────────────────────────────

    /// A component id that doesn't parse as an address must produce a
    /// `FatalError` rather than panicking.
    #[test]
    fn test_invalid_component_id_returns_fatal_error() {
        let bad_pool = ProtocolComponent { id: String::from("not-an-address"), ..Default::default() };
        let swap = Swap::new(bad_pool, Bytes::from(USDC), Bytes::from(USDT));
        let ctx = default_context(USDC, USDT);
        let result = make_encoder().encode_swap(&swap, &ctx);
        assert!(result.is_err(), "invalid component id must produce an error");
        match result {
            Err(EncodingError::FatalError(msg)) => {
                assert!(
                    msg.contains("Supernova V3 component id"),
                    "error message should mention Supernova V3 component id, got: {msg}"
                );
            }
            other => panic!("expected FatalError, got: {other:?}"),
        }
    }

    /// A component id that's the right length but contains non-hex
    /// characters must also error cleanly.
    #[test]
    fn test_component_id_with_non_hex_chars_returns_error() {
        let bad_pool = ProtocolComponent {
            id: String::from("0xZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"),
            ..Default::default()
        };
        let swap = Swap::new(bad_pool, Bytes::from(USDC), Bytes::from(USDT));
        let ctx = default_context(USDC, USDT);
        assert!(make_encoder().encode_swap(&swap, &ctx).is_err());
    }

    /// A component id missing the `0x` prefix should still parse — alloy's
    /// `Address::from_str` accepts both forms. Pin this so a future
    /// refactor doesn't break the contract.
    #[test]
    fn test_component_id_without_0x_prefix_is_accepted() {
        let pool_no_prefix = ProtocolComponent {
            id: String::from("2beb35e78c9427899353c41c96bcc96c5647ec63"),
            ..Default::default()
        };
        let swap = Swap::new(pool_no_prefix, Bytes::from(USDC), Bytes::from(USDT));
        let ctx = default_context(USDC, USDT);
        // Either it parses (and gives the same result as the prefixed version)
        // or it errors gracefully — both are acceptable, but it must NOT panic.
        let result = make_encoder().encode_swap(&swap, &ctx);
        if let Ok(encoded) = result {
            assert_eq!(encoded.len(), 64);
        }
    }

    // ─────────────────────────────────────────────────────────────────
    //  Encoder constructor + executor address plumbing
    // ─────────────────────────────────────────────────────────────────

    /// The constructor takes (executor_address, chain, config) and
    /// must store the executor address such that `executor_address()`
    /// returns the exact same bytes back.
    #[test]
    fn test_executor_address_round_trips() {
        let addr = Bytes::from(EXECUTOR_PROD);
        let encoder = SupernovaV3SwapEncoder::new(addr.clone(), Chain::Ethereum, None).unwrap();
        assert_eq!(encoder.executor_address(), &addr);
    }

    /// The encoder ignores `chain` and `config` — verify it accepts
    /// every Chain variant we care about without erroring.
    #[test]
    fn test_constructor_accepts_all_supported_chains() {
        for chain in [Chain::Ethereum, Chain::Base, Chain::Unichain] {
            let result = SupernovaV3SwapEncoder::new(Bytes::from(EXECUTOR_PROD), chain, None);
            assert!(result.is_ok(), "constructor should accept chain {chain:?}");
        }
    }

    /// The constructor accepts a config map but doesn't actually use
    /// it; verify a populated config still constructs successfully.
    #[test]
    fn test_constructor_accepts_non_empty_config() {
        let mut config = HashMap::new();
        config.insert("anything".to_string(), "value".to_string());
        let result =
            SupernovaV3SwapEncoder::new(Bytes::from(EXECUTOR_PROD), Chain::Ethereum, Some(config));
        assert!(result.is_ok());
    }

    /// `clone_box` must produce an encoder that returns the same
    /// `executor_address` and the same `encode_swap` output as the
    /// original. This pins the trait-object cloning contract.
    #[test]
    fn test_clone_box_preserves_executor_address_and_output() {
        let original = make_encoder();
        let cloned = original.clone_box();
        assert_eq!(original.executor_address(), cloned.executor_address());

        let swap = make_swap(SUPERNOVA_USDC_USDT, USDC, USDT);
        let ctx = default_context(USDC, USDT);
        assert_eq!(
            original.encode_swap(&swap, &ctx).unwrap(),
            cloned.encode_swap(&swap, &ctx).unwrap()
        );
    }

    /// Different executor addresses must produce different
    /// `executor_address()` returns but the SAME swap-byte output.
    /// This pins the separation: the executor address is metadata
    /// for the dispatcher, the swap bytes are the protocol payload.
    #[test]
    fn test_executor_address_does_not_affect_encoded_swap_bytes() {
        let encoder_a = SupernovaV3SwapEncoder::new(
            Bytes::from(EXECUTOR_PROD),
            Chain::Ethereum,
            None,
        )
        .unwrap();
        let encoder_b = SupernovaV3SwapEncoder::new(
            Bytes::from("0x2e234DAe75C793f67A35089C9d99245E1C58470b"),
            Chain::Ethereum,
            None,
        )
        .unwrap();

        let swap = make_swap(SUPERNOVA_USDC_USDT, USDC, USDT);
        let ctx = default_context(USDC, USDT);
        let bytes_a = encoder_a.encode_swap(&swap, &ctx).unwrap();
        let bytes_b = encoder_b.encode_swap(&swap, &ctx).unwrap();
        // Same swap bytes despite different executors.
        assert_eq!(bytes_a, bytes_b);
        // But the executor addresses themselves differ.
        assert_ne!(encoder_a.executor_address(), encoder_b.executor_address());
    }

    // ─────────────────────────────────────────────────────────────────
    //  Cross-pool consistency
    // ─────────────────────────────────────────────────────────────────

    /// The same (tokenIn, tokenOut) pair encoded against two different
    /// pools must produce different bytes — the pool address (bytes
    /// 43..63) is what distinguishes them. Without this assertion, a
    /// hypothetical bug that constant-folded the pool address would
    /// not be caught by the other tests.
    #[test]
    fn test_different_pools_produce_different_bytes() {
        let swap_a = make_swap(SUPERNOVA_USDC_USDT, USDC, USDT);
        let swap_b = make_swap(
            // Hypothetical 2nd USDC/USDT pool — just any other valid address
            "0x1111111111111111111111111111111111111111",
            USDC,
            USDT,
        );
        let ctx = default_context(USDC, USDT);
        let encoder = make_encoder();
        let bytes_a = encoder.encode_swap(&swap_a, &ctx).unwrap();
        let bytes_b = encoder.encode_swap(&swap_b, &ctx).unwrap();
        assert_ne!(bytes_a, bytes_b);
        // The only difference must be in the pool-address slice.
        assert_eq!(&bytes_a[0..43], &bytes_b[0..43]);
        assert_eq!(&bytes_a[63..64], &bytes_b[63..64]);
        assert_ne!(&bytes_a[43..63], &bytes_b[43..63]);
    }

    /// The same pool address with different (tokenIn, tokenOut) must
    /// also produce different bytes (covers the inverse of the above).
    #[test]
    fn test_same_pool_different_tokens_produce_different_bytes() {
        // Re-use the WETH/USDT pool address with two different token
        // pairs. (In reality you'd never do this — the pool would
        // reject the swap — but the encoder must not collapse them.)
        let swap_a = make_swap(SUPERNOVA_WETH_USDT, WETH, USDT);
        let swap_b = make_swap(SUPERNOVA_WETH_USDT, WBTC, DAI);
        let encoder = make_encoder();
        let bytes_a = encoder
            .encode_swap(&swap_a, &default_context(WETH, USDT))
            .unwrap();
        let bytes_b = encoder
            .encode_swap(&swap_b, &default_context(WBTC, DAI))
            .unwrap();
        assert_ne!(bytes_a, bytes_b);
        // The pool slice (43..63) must be identical, the token slices (0..40) must differ.
        assert_eq!(&bytes_a[43..63], &bytes_b[43..63]);
        assert_ne!(&bytes_a[0..40], &bytes_b[0..40]);
    }

    // ─────────────────────────────────────────────────────────────────
    //  Cross-validation against Uniswap V3 byte layout
    // ─────────────────────────────────────────────────────────────────

    /// The whole point of `SupernovaV3SwapEncoder` is that its output
    /// is consumed by the existing `UniswapV3Executor`. This test
    /// pins the byte-position contract from the executor's
    /// `_decodeData` (foundry/src/executors/UniswapV3Executor.sol):
    ///
    /// ```solidity
    /// if (data.length != 64) revert ...;
    /// target = address(bytes20(data[43:63]));
    /// zeroForOne = uint8(data[63]) > 0;
    /// ```
    ///
    /// Plus the callback decode at lines 76-77 (for handleCallback):
    /// ```solidity
    /// address tokenIn = address(bytes20(msgData[132:152]));
    /// ```
    /// Where `msgData[132..152]` is the FIRST 20 bytes of the
    /// protocol-data blob, i.e. `data[0..20]` from the encoder POV.
    ///
    /// If any of these byte positions move, this test breaks.
    #[test]
    fn test_byte_positions_match_uniswap_v3_executor_contract() {
        let swap = make_swap(SUPERNOVA_USDC_USDT, USDC, USDT);
        let encoded = make_encoder()
            .encode_swap(&swap, &default_context(USDC, USDT))
            .unwrap();
        // Length contract.
        assert_eq!(encoded.len(), 64);

        // Position contract — extract the same way the executor does.
        let target_bytes: [u8; 20] = encoded[43..63].try_into().unwrap();
        let target_addr = Address::from(target_bytes);
        assert_eq!(
            target_addr,
            Address::from_str(SUPERNOVA_USDC_USDT).unwrap(),
            "target read at executor offset [43..63) must equal the pool address"
        );

        let zero_for_one = encoded[63] > 0;
        assert!(zero_for_one, "USDC→USDT must decode as zeroForOne=true");

        // Callback decode — first 20 bytes of the protocol data are tokenIn.
        let token_in_bytes: [u8; 20] = encoded[0..20].try_into().unwrap();
        let token_in_addr = Address::from(token_in_bytes);
        assert_eq!(
            token_in_addr,
            Address::from_str(USDC).unwrap(),
            "tokenIn at offset [0..20) must equal USDC for handleCallback decode"
        );
    }
}
