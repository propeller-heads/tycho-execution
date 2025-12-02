use std::{collections::HashSet, str::FromStr, sync::LazyLock};

use alloy::primitives::Address;
use serde_json::Value;

pub const DEFAULT_EXECUTORS_JSON: &str = include_str!("../../../config/executor_addresses.json");
pub const DEFAULT_ROUTERS_JSON: &str = include_str!("../../../config/router_addresses.json");
pub const PROTOCOL_SPECIFIC_CONFIG: &str =
    include_str!("../../../config/protocol_specific_addresses.json");

/// Lazily parse the Angstrom hook address from PROTOCOL_SPECIFIC_CONFIG
pub static ANGSTROM_HOOK_ADDRESS: LazyLock<Address> = LazyLock::new(|| {
    let config: Value = serde_json::from_str(PROTOCOL_SPECIFIC_CONFIG).unwrap_or_default();
    config
        .get("ethereum")
        .and_then(|eth| eth.get("uniswap_v4_hooks"))
        .and_then(|hooks| hooks.get("angstrom_hook_address"))
        .and_then(|addr| addr.as_str())
        .and_then(|s| Address::from_str(s).ok())
        .unwrap_or(Address::ZERO)
});

/// The number of blocks in the future for which to fetch Angstrom Attestations
///
/// It is important to note that fetching more blocks will send more attestations to the
/// Tycho Router, resulting in a higher gas usage. Fetching fewer blocks may result in attestations
/// expiring if the transaction is not sent fast enough.
pub const ANGSTROM_DEFAULT_BLOCKS_IN_FUTURE: u64 = 5;

/// These protocols support the optimization of grouping swaps.
///
/// This requires special encoding to send call data of multiple swaps to a single executor,
/// as if it were a single swap. The protocol likely uses flash accounting to save gas on token
/// transfers.
pub static GROUPABLE_PROTOCOLS: LazyLock<HashSet<&'static str>> = LazyLock::new(|| {
    let mut set = HashSet::new();
    set.insert("uniswap_v4");
    set.insert("uniswap_v4_hooks");
    set.insert("uniswap_v4_angstrom");
    set.insert("vm:balancer_v3");
    set.insert("ekubo_v2");
    set
});

/// These protocols need an external in transfer to the pool. This transfer can be from the router,
/// from the user or from the previous pool. Any protocols that are not defined here expect funds to
/// be in the router at the time of swap and do the transfer themselves from `msg.sender`
pub static IN_TRANSFER_REQUIRED_PROTOCOLS: LazyLock<HashSet<&'static str>> = LazyLock::new(|| {
    let mut set = HashSet::new();
    set.insert("uniswap_v2");
    set.insert("sushiswap_v2");
    set.insert("pancakeswap_v2");
    set.insert("uniswap_v3");
    set.insert("pancakeswap_v3");
    set.insert("uniswap_v4");
    set.insert("uniswap_v4_hooks");
    set.insert("uniswap_v4_angstrom");
    set.insert("ekubo_v2");
    set.insert("vm:maverick_v2");
    set.insert("vm:balancer_v3");
    set.insert("fluid_v1");
    set.insert("aerodrome_slipstreams");
    set
});

/// The protocols here are a subset of the ones defined in IN_TRANSFER_REQUIRED_PROTOCOLS. The in
/// transfer needs to be performed inside the callback logic. This means, the tokens can not be sent
/// directly from the previous pool into a pool of this protocol. The tokens need to be sent to the
/// router and only then transferred into the pool. This is the case for uniswap v3 because of the
/// callback logic. The only way for this to work it would be to call the second swap during the
/// callback of the first swap. This is currently not supported.
pub static CALLBACK_CONSTRAINED_PROTOCOLS: LazyLock<HashSet<&'static str>> = LazyLock::new(|| {
    let mut set = HashSet::new();
    set.insert("uniswap_v3");
    set.insert("pancakeswap_v3");
    set.insert("uniswap_v4");
    set.insert("uniswap_v4_hooks");
    set.insert("uniswap_v4_angstrom");
    set.insert("ekubo_v2");
    set.insert("vm:balancer_v3");
    set.insert("fluid_v1");
    set.insert("aerodrome_slipstreams");
    set
});

/// These groupable protocols use simple concatenation instead of PLE when forming swap groups.
pub static NON_PLE_ENCODED_PROTOCOLS: LazyLock<HashSet<&'static str>> = LazyLock::new(|| {
    let mut set = HashSet::new();
    set.insert("ekubo_v2");
    set
});
