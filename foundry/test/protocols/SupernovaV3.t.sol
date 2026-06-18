// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../TychoRouterTestSetup.sol";

/// @title Supernova V3 (Algebra Integral) executor reuse test
/// @notice Verifies that the existing UniswapV3Executor can drive a swap
///         on a Supernova V3 / Algebra Integral pool **without any new
///         Solidity contract**.
///
/// The hypothesis being tested:
/// - `IAlgebraPool.swap(address,bool,int256,uint160,bytes)` shares the
///   exact same 4-byte selector as `IUniswapV3Pool.swap(...)`.
/// - Algebra pools call back via `algebraSwapCallback(int256,int256,bytes)`
///   which has a different selector than `uniswapV3SwapCallback` but the
///   identical argument layout.
/// - `TychoRouter.fallback` is selector-agnostic — it forwards any unknown
///   callback to whichever executor is currently mid-swap (tracked in
///   transient storage). So `UniswapV3Executor.handleCallback` ends up
///   handling the Algebra callback, and the byte offsets it reads happen
///   to be identical to what Algebra produces.
///
/// If this test passes, Supernova V3 ships with **zero new Solidity** —
/// just the Rust encoder + a JSON registry entry pointing at the existing
/// UniswapV3Executor address.
///
/// We use `singleSwap` (non-Permit2) and a freshly minted EOA via
/// `makeAccount` to avoid colliding with mainnet addresses that have
/// become contracts at the fork block (the default `ALICE` constant from
/// the Tycho test setup is one such collision at block 24768374).
///
/// See `src/encoding/evm/swap_encoder/supernova_v3.rs` for the matching
/// Rust `SwapEncoder` and a longer-form rationale on why this works
/// without a dedicated executor.
contract TychoRouterForSupernovaV3Test is TychoRouterTestSetup {
    // Supernova V3 USDC/USDT pool. token0 = USDC, token1 = USDT.
    address constant SUPERNOVA_USDC_USDT_POOL =
        0x2beb35e78C9427899353c41C96bCc96C5647ec63;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /// @dev Discovered at run time in `setUp()` so the suite always
    ///      runs against the current mainnet head. A small buffer is
    ///      subtracted so RPCs that lag the canonical head by a block
    ///      or two don't error out.
    uint256 private _dynamicForkBlock;

    function getForkBlock() public view override returns (uint256) {
        // If `setUp` hasn't run yet (e.g. forge is computing the test
        // selector before any state is initialised), fall back to a
        // known-good pin so we don't return zero.
        return _dynamicForkBlock == 0 ? 24827000 : _dynamicForkBlock;
    }

    function setUp() public virtual override {
        // Briefly fork at chain head to discover the latest block
        // number. We then store it so the *real* setUp (called via
        // `super.setUp()` below) picks it up via `getForkBlock()`.
        vm.createSelectFork(vm.rpcUrl(getChain()));
        // Subtract a small safety buffer — some archive RPCs lag the
        // canonical head by a few blocks.
        _dynamicForkBlock = block.number - 5;
        super.setUp();
    }

    /// @dev USDC -> USDT (zeroForOne = true since USDC sorts below USDT)
    function testSingleSupernovaV3UsdcToUsdt() public {
        (address user, ) = makeAddrAndKey("supernova_user");

        uint256 amountIn = 100 * 10 ** 6; // 100 USDC
        deal(USDC, user, amountIn);

        vm.startPrank(user);
        IERC20(USDC).approve(tychoRouterAddr, amountIn);

        bytes memory protocolData = encodeSupernovaV3Swap(
            USDC,
            USDT,
            SUPERNOVA_USDC_USDT_POOL,
            true /* zeroForOne */
        );
        bytes memory swap =
            encodeSingleSwap(address(usv3Executor), protocolData);

        // 5% slippage envelope is plenty for a stable-stable pair.
        uint256 minOut = 95 * 10 ** 6;

        uint256 balanceBefore = IERC20(USDT).balanceOf(user);

        uint256 amountOut = tychoRouter.singleSwap(
            amountIn, USDC, USDT, minOut, user, noClientFee(), swap
        );

        vm.stopPrank();

        uint256 received = IERC20(USDT).balanceOf(user) - balanceBefore;

        emit log_named_uint("USDC sold      ", amountIn);
        emit log_named_uint("USDT bought    ", received);
        emit log_named_uint("router amountOut", amountOut);

        assertEq(received, amountOut, "balance delta != reported amountOut");
        assertGt(received, minOut, "received less than minOut");
        assertApproxEqRel(
            received,
            amountIn,
            0.05e18, // within 5%
            "stable-stable swap diverged unexpectedly"
        );
    }

    /// @dev USDT -> USDC (zeroForOne = false)
    function testSingleSupernovaV3UsdtToUsdc() public {
        (address user, ) = makeAddrAndKey("supernova_user");

        uint256 amountIn = 100 * 10 ** 6; // 100 USDT
        deal(USDT, user, amountIn);

        vm.startPrank(user);
        // USDT's `approve(address,uint256)` returns *nothing* (it's the
        // famous non-standard ERC20). The IERC20 interface wrapper
        // expects a bool, sees zero bytes, and reverts. Use a raw call
        // and ignore the (empty) return data.
        (bool ok, ) = USDT.call(
            abi.encodeWithSelector(
                IERC20.approve.selector, tychoRouterAddr, amountIn
            )
        );
        require(ok, "USDT approve failed");

        bytes memory protocolData = encodeSupernovaV3Swap(
            USDT,
            USDC,
            SUPERNOVA_USDC_USDT_POOL,
            false /* zeroForOne (USDT > USDC) */
        );
        bytes memory swap =
            encodeSingleSwap(address(usv3Executor), protocolData);

        uint256 minOut = 95 * 10 ** 6;
        uint256 balanceBefore = IERC20(USDC).balanceOf(user);

        uint256 amountOut = tychoRouter.singleSwap(
            amountIn, USDT, USDC, minOut, user, noClientFee(), swap
        );

        vm.stopPrank();

        uint256 received = IERC20(USDC).balanceOf(user) - balanceBefore;

        emit log_named_uint("USDT sold      ", amountIn);
        emit log_named_uint("USDC bought    ", received);
        emit log_named_uint("router amountOut", amountOut);

        assertEq(received, amountOut, "balance delta != reported amountOut");
        assertGt(received, minOut, "received less than minOut");
        assertApproxEqRel(received, amountIn, 0.05e18, "swap diverged");
    }

    // ─────────────────────────────────────────────────────────────────
    //  Native ETH ↔ WETH wrap/unwrap tests
    //
    //  Algebra/Supernova pools (like Uniswap V3 pools) only accept WETH
    //  — they have no native-ETH path. To swap native ETH through a
    //  Supernova pool, the caller has to:
    //
    //    1. Send `msg.value` of ETH along with the call.
    //    2. Use a SEQUENTIAL swap whose first hop is the WethExecutor
    //       (which `wraps` ETH→WETH and leaves the WETH at the router).
    //    3. The second hop is then the regular Supernova/UniswapV3
    //       hop using the WETH/<token> Supernova pool.
    //
    //  For an ETH-out swap, the order is reversed: token → WETH (Supernova
    //  hop) followed by WethExecutor unwrap → native ETH (sent to user).
    //
    //  This is exactly the same pattern RouterV2 implements with
    //  `swapExactETHForTokens` (`wETH.deposit{value:amountIn}` then swap)
    //  and `swapExactTokensForETH` (swap into router, then `wETH.withdraw`).
    //  In Tycho the wrap/unwrap is its own swap "hop" via WethExecutor —
    //  which the Rust `TychoRouterEncoder` auto-inserts whenever a
    //  `Solution` has ETH at the boundary but no explicit WETH bridge.
    //
    //  We don't currently have a confirmed Supernova WETH/<token> pool
    //  address that's known to have liquidity at our fork block, so the
    //  middle-hop in the tests below uses the well-known Uniswap V3
    //  USDC/WETH 0.05% pool. Because Supernova V3 reuses the **same**
    //  `UniswapV3Executor` (this is the whole point of this PR), every
    //  byte of the path that the executor sees is identical to a real
    //  Supernova hop. To swap the middle-hop pool for an actual Supernova
    //  WETH pool when one becomes available, change the
    //  `MIDDLE_HOP_POOL` constant below — nothing else in the test
    //  needs to move.
    // ─────────────────────────────────────────────────────────────────

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    /// Stand-in for a Supernova V3 WETH/<token> pool. Currently the
    /// Uniswap V3 USDC/WETH 0.05% pool, which is selector- and
    /// callback-compatible with Supernova. Replace with an actual
    /// Supernova pool when one is identified.
    address constant MIDDLE_HOP_POOL =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    /// @dev `WethExecutor` swap data — single byte: `0x01` = wrap
    ///      ETH→WETH, `0x00` = unwrap WETH→ETH.
    function encodeWethSwap(bool isWrapping)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(isWrapping ? 1 : 0));
    }

    /// ETH → WETH (WethExecutor wrap) → USDC (Supernova-compatible
    /// `UniswapV3Executor` hop). Sends native ETH as `msg.value` and
    /// uses `tokenIn = address(0)` to tell the router this is a
    /// native-ETH input swap.
    function testSupernovaEthInWrap() public {
        (address user, ) = makeAddrAndKey("supernova_user");

        uint256 amountIn = 1 ether;
        deal(user, amountIn);

        vm.startPrank(user);

        // Hop 0: WethExecutor — wraps `msg.value` ETH into WETH inside
        // the router. Output stays at the router for hop 1.
        bytes memory wrapData = encodeWethSwap(true);

        // Hop 1: UniswapV3Executor on the WETH/USDC pool. WETH > USDC
        // address-wise, so zeroForOne = false (token0 is USDC).
        bytes memory poolData = encodeSupernovaV3Swap(
            WETH, USDC, MIDDLE_HOP_POOL, false /* zeroForOne */
        );

        bytes[] memory swaps = new bytes[](2);
        swaps[0] = encodeSequentialSwap(address(wethExecutor), wrapData);
        swaps[1] = encodeSequentialSwap(address(usv3Executor), poolData);

        uint256 usdcBefore = IERC20(USDC).balanceOf(user);

        // 1 ETH at ~$3000 should give back at least 1500 USDC even with
        // brutal slippage. We're not asserting on the exact rate.
        uint256 minOut = 1_500 * 10 ** 6;

        uint256 amountOut = tychoRouter.sequentialSwap{value: amountIn}(
            amountIn,
            address(0), // tokenIn = native ETH
            USDC,
            minOut,
            user,
            noClientFee(),
            pleEncode(swaps)
        );

        vm.stopPrank();

        uint256 usdcReceived = IERC20(USDC).balanceOf(user) - usdcBefore;

        emit log_named_uint("ETH sold       ", amountIn);
        emit log_named_uint("USDC bought    ", usdcReceived);
        emit log_named_uint("router amountOut", amountOut);

        assertEq(
            usdcReceived, amountOut, "balance delta != reported amountOut"
        );
        assertGt(usdcReceived, minOut, "received less than minOut");
        // Router must not retain WETH or ETH from the wrap hop.
        assertEq(
            IERC20(WETH).balanceOf(tychoRouterAddr),
            0,
            "router retained WETH from wrap"
        );
        assertEq(
            tychoRouterAddr.balance, 0, "router retained ETH from wrap"
        );
        // User's ETH balance is fully consumed.
        assertEq(user.balance, 0, "user retained ETH that should have been sold");
    }

    /// USDC → WETH (Supernova-compatible UniswapV3Executor hop) → ETH
    /// (WethExecutor unwrap). Output is native ETH delivered to the
    /// user via `_safeTransferETH`-style callback in the router.
    function testSupernovaEthOutUnwrap() public {
        (address user, ) = makeAddrAndKey("supernova_user");

        uint256 amountIn = 5_000 * 10 ** 6; // 5,000 USDC
        deal(USDC, user, amountIn);

        vm.startPrank(user);
        IERC20(USDC).approve(tychoRouterAddr, amountIn);

        // Hop 0: UniswapV3Executor on USDC/WETH pool. USDC < WETH,
        // so zeroForOne = true (selling token0 USDC for token1 WETH).
        bytes memory poolData = encodeSupernovaV3Swap(
            USDC, WETH, MIDDLE_HOP_POOL, true /* zeroForOne */
        );

        // Hop 1: WethExecutor — unwraps the WETH the router received
        // back into native ETH and forwards it to the receiver.
        bytes memory unwrapData = encodeWethSwap(false);

        bytes[] memory swaps = new bytes[](2);
        swaps[0] = encodeSequentialSwap(address(usv3Executor), poolData);
        swaps[1] = encodeSequentialSwap(address(wethExecutor), unwrapData);

        // ~5,000 USDC ≈ 1.5 ETH at ~$3000. Use a generous floor.
        uint256 minOut = 0.5 ether;

        uint256 ethBefore = user.balance;

        uint256 amountOut = tychoRouter.sequentialSwap(
            amountIn,
            USDC,
            address(0), // tokenOut = native ETH
            minOut,
            user,
            noClientFee(),
            pleEncode(swaps)
        );

        vm.stopPrank();

        uint256 ethReceived = user.balance - ethBefore;

        emit log_named_uint("USDC sold      ", amountIn);
        emit log_named_uint("ETH  bought    ", ethReceived);
        emit log_named_uint("router amountOut", amountOut);

        assertEq(
            ethReceived, amountOut, "balance delta != reported amountOut"
        );
        assertGt(ethReceived, minOut, "received less than minOut");
        assertEq(
            IERC20(WETH).balanceOf(tychoRouterAddr),
            0,
            "router retained WETH from unwrap"
        );
        assertEq(
            tychoRouterAddr.balance,
            0,
            "router retained ETH from unwrap"
        );
    }

    /// Three-hop ETH-input swap that actually exercises the **real
    /// Supernova V3** USDC/USDT pool in the middle:
    ///
    ///   ETH ──(WethExecutor wrap)──> WETH
    ///       ──(UniswapV3 USDC/WETH)──> USDC
    ///       ──(Supernova USDC/USDT)──> USDT
    ///
    /// This is the test that ties everything in this file together —
    /// it proves that an ETH-input swap can route *through* a Supernova
    /// pool inside a multi-hop sequential plan, using the existing
    /// `WethExecutor` for the ETH boundary and the existing
    /// `UniswapV3Executor` (aliased as `vm:supernova_v3`) for the
    /// Supernova hop. No new Solidity contracts are involved.
    function testSupernovaEthRoundTripViaSupernovaPool() public {
        (address user, ) = makeAddrAndKey("supernova_user");

        uint256 amountIn = 1 ether;
        deal(user, amountIn);

        vm.startPrank(user);

        // Hop 0: ETH → WETH wrap
        bytes memory wrapData = encodeWethSwap(true);

        // Hop 1: WETH → USDC on the Uniswap V3 USDC/WETH pool
        bytes memory wethToUsdc = encodeSupernovaV3Swap(
            WETH, USDC, MIDDLE_HOP_POOL, false /* zeroForOne (USDC < WETH) */
        );

        // Hop 2: USDC → USDT on the **real** Supernova V3 pool.
        // This is the hop that proves Supernova execution works.
        bytes memory usdcToUsdt = encodeSupernovaV3Swap(
            USDC,
            USDT,
            SUPERNOVA_USDC_USDT_POOL,
            true /* zeroForOne (USDC < USDT) */
        );

        bytes[] memory swaps = new bytes[](3);
        swaps[0] = encodeSequentialSwap(address(wethExecutor), wrapData);
        swaps[1] = encodeSequentialSwap(address(usv3Executor), wethToUsdc);
        swaps[2] = encodeSequentialSwap(address(usv3Executor), usdcToUsdt);

        // 1 ETH ≈ $3000 ⇒ floor of 1500 USDT is conservative.
        uint256 minOut = 1_500 * 10 ** 6;

        uint256 usdtBefore = IERC20(USDT).balanceOf(user);

        uint256 amountOut = tychoRouter.sequentialSwap{value: amountIn}(
            amountIn,
            address(0), // tokenIn = native ETH
            USDT,
            minOut,
            user,
            noClientFee(),
            pleEncode(swaps)
        );

        vm.stopPrank();

        uint256 usdtReceived = IERC20(USDT).balanceOf(user) - usdtBefore;

        emit log_named_uint("ETH sold        ", amountIn);
        emit log_named_uint("USDT bought     ", usdtReceived);
        emit log_named_uint("router amountOut ", amountOut);

        assertEq(
            usdtReceived, amountOut, "balance delta != reported amountOut"
        );
        assertGt(usdtReceived, minOut, "received less than minOut");
        // Router holds nothing of either intermediate token after the
        // multi-hop completes.
        assertEq(
            IERC20(WETH).balanceOf(tychoRouterAddr),
            0,
            "router retained WETH"
        );
        assertEq(
            IERC20(USDC).balanceOf(tychoRouterAddr),
            0,
            "router retained USDC"
        );
        assertEq(tychoRouterAddr.balance, 0, "router retained ETH");
    }

    /// @notice Build the same 64-byte payload that
    /// `SupernovaV3SwapEncoder` (Rust) produces.
    ///
    /// Layout (must match `UniswapV3Executor._decodeData`):
    ///   [ 0..20)  tokenIn
    ///   [20..40)  tokenOut
    ///   [40..43)  fee placeholder (3 zero bytes — Algebra dynamic fee,
    ///             unused on the routing path)
    ///   [43..63)  pool address
    ///   [63..64)  zeroForOne
    function encodeSupernovaV3Swap(
        address tokenIn,
        address tokenOut,
        address pool,
        bool zeroForOne
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            tokenIn, tokenOut, uint24(0), pool, zeroForOne
        );
    }
}

// ─────────────────────────────────────────────────────────────────────
//  Pure Solidity unit tests — no fork required, run in milliseconds
// ─────────────────────────────────────────────────────────────────────
//
//  These tests pin the byte layout produced by `encodeSupernovaV3Swap`
//  cross-language with the Rust `SupernovaV3SwapEncoder`. Both sides
//  must produce identical 64-byte blobs for the same inputs — if they
//  diverge, the executor will decode garbage and the router will
//  silently route swaps to the wrong pool.
//
//  The test fixtures here mirror the Rust constants in
//  `src/encoding/evm/swap_encoder/supernova_v3.rs::tests`. If you
//  change one side, change the other and re-run both:
//      cargo test --features evm supernova_v3
//      forge test --match-contract SupernovaV3EncodingUnitTest
//
//  This contract does NOT inherit from `TychoRouterTestSetup`, so it
//  doesn't fork mainnet and runs as a pure unit test.

contract SupernovaV3EncodingUnitTest is Test {
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address constant SUPERNOVA_USDC_USDT =
        0x2beb35e78C9427899353c41C96bCc96C5647ec63;
    address constant SUPERNOVA_WETH_USDT =
        0xDE758DB54c1b4a87B06b34B30EF0a710Dc35388F;
    address constant SUPERNOVA_WBTC_WETH =
        0x55347B4AB701Ab54eE394f20020175Bb385CA725;

    /// @notice Mirrors the Rust encoder exactly. Kept inline so this
    /// test contract is self-contained.
    function _encodeSupernovaV3Swap(
        address tokenIn,
        address tokenOut,
        address pool,
        bool zeroForOne
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            tokenIn, tokenOut, uint24(0), pool, zeroForOne
        );
    }

    // ─────────────────────────────────────────────────────────────────
    //  Length / position invariants
    // ─────────────────────────────────────────────────────────────────

    /// The encoded payload MUST always be exactly 64 bytes — the
    /// `UniswapV3Executor._decodeData` enforces this with a strict
    /// length check that reverts with `UniswapV3Executor__InvalidDataLength`.
    function test_encodedLengthIsAlways64Bytes() public pure {
        bytes memory a = _encodeSupernovaV3Swap(USDC, USDT, SUPERNOVA_USDC_USDT, true);
        bytes memory b = _encodeSupernovaV3Swap(WETH, USDT, SUPERNOVA_WETH_USDT, true);
        bytes memory c = _encodeSupernovaV3Swap(WBTC, WETH, SUPERNOVA_WBTC_WETH, true);
        assertEq(a.length, 64);
        assertEq(b.length, 64);
        assertEq(c.length, 64);
    }

    /// Bytes [0..20) — tokenIn address.
    function test_byteLayout_tokenInAtOffset0() public pure {
        bytes memory data = _encodeSupernovaV3Swap(USDC, USDT, SUPERNOVA_USDC_USDT, true);
        address decoded;
        assembly {
            // 32-byte word starting at data[32] (skip the length prefix),
            // shifted right by 12 bytes to extract the leftmost 20 bytes.
            decoded := shr(96, mload(add(data, 32)))
        }
        assertEq(decoded, USDC);
    }

    /// Bytes [20..40) — tokenOut address.
    function test_byteLayout_tokenOutAtOffset20() public pure {
        bytes memory data = _encodeSupernovaV3Swap(USDC, USDT, SUPERNOVA_USDC_USDT, true);
        address decoded;
        assembly {
            // Read 32 bytes starting at data[32 + 20] = data[52]
            decoded := shr(96, mload(add(data, 52)))
        }
        assertEq(decoded, USDT);
    }

    /// Bytes [40..43) — fee placeholder, must always be 3 zero bytes
    /// regardless of inputs. Algebra has dynamic fees and the
    /// executor never reads this field.
    function test_byteLayout_feePlaceholderIsAlwaysThreeZeros() public pure {
        // Try several inputs to make sure no input shape causes
        // accidental non-zero bytes here.
        bytes[3] memory cases;
        cases[0] = _encodeSupernovaV3Swap(USDC, USDT, SUPERNOVA_USDC_USDT, true);
        cases[1] = _encodeSupernovaV3Swap(USDT, USDC, SUPERNOVA_USDC_USDT, false);
        cases[2] = _encodeSupernovaV3Swap(WBTC, WETH, SUPERNOVA_WBTC_WETH, true);
        for (uint256 i = 0; i < cases.length; i++) {
            assertEq(uint8(cases[i][40]), 0, "fee[0] must be 0x00");
            assertEq(uint8(cases[i][41]), 0, "fee[1] must be 0x00");
            assertEq(uint8(cases[i][42]), 0, "fee[2] must be 0x00");
        }
    }

    /// Bytes [43..63) — pool address. This is THE byte slice the
    /// executor's `_decodeData` reads as `target`, so this test
    /// directly validates the contract that matters most.
    function test_byteLayout_poolAddressAtOffset43() public pure {
        bytes memory data = _encodeSupernovaV3Swap(USDC, USDT, SUPERNOVA_USDC_USDT, true);
        address decoded;
        assembly {
            // 32 + 43 = 75
            decoded := shr(96, mload(add(data, 75)))
        }
        assertEq(decoded, SUPERNOVA_USDC_USDT);
    }

    /// Byte 63 — single zeroForOne flag (0x00 or 0x01).
    function test_byteLayout_zeroForOneAtOffset63() public pure {
        bytes memory dataTrue = _encodeSupernovaV3Swap(USDC, USDT, SUPERNOVA_USDC_USDT, true);
        bytes memory dataFalse = _encodeSupernovaV3Swap(USDT, USDC, SUPERNOVA_USDC_USDT, false);
        assertEq(uint8(dataTrue[63]), 1, "zeroForOne=true must encode as 0x01");
        assertEq(uint8(dataFalse[63]), 0, "zeroForOne=false must encode as 0x00");
    }

    // ─────────────────────────────────────────────────────────────────
    //  Cross-language consistency with the Rust encoder
    // ─────────────────────────────────────────────────────────────────

    /// Hex-string equivalence with the Rust unit test
    /// `test_encode_supernova_v3` in
    /// `src/encoding/evm/swap_encoder/supernova_v3.rs`. If either
    /// side changes, both tests must be updated together.
    function test_crossLanguage_usdcToUsdtMatchesRustOutput() public pure {
        bytes memory data = _encodeSupernovaV3Swap(USDC, USDT, SUPERNOVA_USDC_USDT, true);
        // The expected hex matches the assertion in the Rust test exactly.
        bytes memory expected = abi.encodePacked(
            // tokenIn (USDC)
            hex"a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            // tokenOut (USDT)
            hex"dac17f958d2ee523a2206206994597c13d831ec7",
            // fee placeholder
            hex"000000",
            // pool
            hex"2beb35e78c9427899353c41c96bcc96c5647ec63",
            // zeroForOne (true)
            hex"01"
        );
        assertEq(data, expected);
    }

    /// Reverse direction (USDT → USDC) — also pinned cross-language.
    function test_crossLanguage_usdtToUsdcMatchesRustOutput() public pure {
        bytes memory data = _encodeSupernovaV3Swap(USDT, USDC, SUPERNOVA_USDC_USDT, false);
        bytes memory expected = abi.encodePacked(
            hex"dac17f958d2ee523a2206206994597c13d831ec7",
            hex"a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            hex"000000",
            hex"2beb35e78c9427899353c41c96bcc96c5647ec63",
            hex"00"
        );
        assertEq(data, expected);
    }

    // ─────────────────────────────────────────────────────────────────
    //  Direction sensitivity
    // ─────────────────────────────────────────────────────────────────

    /// Reverse direction must flip zeroForOne and swap tokenIn/tokenOut.
    /// The pool address and fee placeholder stay identical.
    function test_reverseDirectionFlipsZeroForOneAndSwapsTokens() public pure {
        bytes memory forward = _encodeSupernovaV3Swap(
            USDC, USDT, SUPERNOVA_USDC_USDT, true
        );
        bytes memory reverse = _encodeSupernovaV3Swap(
            USDT, USDC, SUPERNOVA_USDC_USDT, false
        );

        // tokenIn slot of forward == tokenOut slot of reverse
        for (uint256 i = 0; i < 20; i++) {
            assertEq(forward[i], reverse[20 + i]);
        }
        // tokenOut slot of forward == tokenIn slot of reverse
        for (uint256 i = 0; i < 20; i++) {
            assertEq(forward[20 + i], reverse[i]);
        }
        // Fee placeholder is identical.
        for (uint256 i = 40; i < 43; i++) {
            assertEq(forward[i], reverse[i]);
        }
        // Pool address is identical.
        for (uint256 i = 43; i < 63; i++) {
            assertEq(forward[i], reverse[i]);
        }
        // zeroForOne is flipped.
        assertEq(uint8(forward[63]), 1);
        assertEq(uint8(reverse[63]), 0);
    }

    // ─────────────────────────────────────────────────────────────────
    //  Pool / token differentiation
    // ─────────────────────────────────────────────────────────────────

    /// Different pools with the same tokens must produce different
    /// bytes. The pool slice (43..63) is what distinguishes them.
    function test_differentPoolsProduceDifferentBytes() public pure {
        bytes memory a = _encodeSupernovaV3Swap(USDC, USDT, SUPERNOVA_USDC_USDT, true);
        bytes memory b = _encodeSupernovaV3Swap(
            USDC, USDT, address(uint160(0x1111111111111111111111111111111111111111)), true
        );
        // Token + fee + zeroForOne slices identical.
        for (uint256 i = 0; i < 43; i++) {
            assertEq(a[i], b[i], "first 43 bytes should match");
        }
        assertEq(a[63], b[63], "zeroForOne should match");
        // Pool slice differs.
        bool anyDiff = false;
        for (uint256 i = 43; i < 63; i++) {
            if (a[i] != b[i]) {
                anyDiff = true;
                break;
            }
        }
        assertTrue(anyDiff, "pool address slice must differ");
    }

    /// Determinism — encoding the same inputs twice must produce
    /// byte-identical output.
    function test_encodingIsDeterministic() public pure {
        bytes memory a = _encodeSupernovaV3Swap(USDC, USDT, SUPERNOVA_USDC_USDT, true);
        bytes memory b = _encodeSupernovaV3Swap(USDC, USDT, SUPERNOVA_USDC_USDT, true);
        assertEq(a, b);
    }

    // ─────────────────────────────────────────────────────────────────
    //  Executor decode contract — replicate `_decodeData` exactly
    // ─────────────────────────────────────────────────────────────────

    /// Replicates `UniswapV3Executor._decodeData` exactly:
    ///   target = address(bytes20(data[43:63]));
    ///   zeroForOne = uint8(data[63]) > 0;
    ///
    /// If our encoder ever produces bytes that don't decode the same
    /// way as the executor reads them, every Supernova quote silently
    /// targets the wrong pool.
    function test_executorDecodeContract_targetAndZeroForOne() public pure {
        bytes memory data = _encodeSupernovaV3Swap(
            USDC, USDT, SUPERNOVA_USDC_USDT, true
        );
        // Replicate the executor's decode.
        require(data.length == 64, "length check");
        bytes20 targetBytes;
        for (uint256 i = 0; i < 20; i++) {
            targetBytes |= bytes20(data[43 + i]) >> (i * 8);
        }
        address target = address(targetBytes);
        bool zeroForOne = uint8(data[63]) > 0;

        assertEq(target, SUPERNOVA_USDC_USDT);
        assertTrue(zeroForOne);
    }

    /// Replicates the callback decode at
    /// `UniswapV3Executor.handleCallback` — `tokenIn` is read from the
    /// first 20 bytes of the protocol data.
    function test_executorDecodeContract_callbackTokenIn() public pure {
        bytes memory data = _encodeSupernovaV3Swap(
            USDC, USDT, SUPERNOVA_USDC_USDT, true
        );
        // First 20 bytes = tokenIn (this is what handleCallback reads).
        bytes20 tokenInBytes;
        for (uint256 i = 0; i < 20; i++) {
            tokenInBytes |= bytes20(data[i]) >> (i * 8);
        }
        address tokenIn = address(tokenInBytes);
        assertEq(tokenIn, USDC);
    }

    // ─────────────────────────────────────────────────────────────────
    //  Realistic-pool sanity checks (still pure, no fork)
    // ─────────────────────────────────────────────────────────────────

    function test_wbtcWethEncoding() public pure {
        bytes memory data = _encodeSupernovaV3Swap(
            WBTC, WETH, SUPERNOVA_WBTC_WETH, true
        );
        assertEq(data.length, 64);
        // tokenIn is WBTC
        bytes20 tin;
        for (uint256 i = 0; i < 20; i++) {
            tin |= bytes20(data[i]) >> (i * 8);
        }
        assertEq(address(tin), WBTC);
        // pool is WBTC/WETH
        bytes20 pool;
        for (uint256 i = 0; i < 20; i++) {
            pool |= bytes20(data[43 + i]) >> (i * 8);
        }
        assertEq(address(pool), SUPERNOVA_WBTC_WETH);
    }

    function test_wethUsdtEncoding() public pure {
        bytes memory data = _encodeSupernovaV3Swap(
            WETH, USDT, SUPERNOVA_WETH_USDT, true
        );
        assertEq(data.length, 64);
        bytes20 tin;
        for (uint256 i = 0; i < 20; i++) {
            tin |= bytes20(data[i]) >> (i * 8);
        }
        assertEq(address(tin), WETH);
    }

    function test_daiUsdtEncoding() public pure {
        bytes memory data = _encodeSupernovaV3Swap(
            DAI,
            USDT,
            0x3750C1fCD35eae956c7a57e773d1496c41d2759A,
            true
        );
        assertEq(data.length, 64);
        bytes20 tin;
        for (uint256 i = 0; i < 20; i++) {
            tin |= bytes20(data[i]) >> (i * 8);
        }
        assertEq(address(tin), DAI);
    }
}
