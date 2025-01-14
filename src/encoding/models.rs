use lazy_static::lazy_static;
use num_bigint::BigUint;
use std::env;
use std::str::FromStr;
use tycho_core::{dto::ProtocolComponent, Bytes};

lazy_static! {
    pub static ref PROPELLER_ROUTER_ADDRESS: Bytes = Bytes::from_str(
        &env::var("ROUTER_ADDRESS").expect("Missing ROUTER_ADDRESS in environment"),
    )
    .expect("Invalid ROUTER_ADDRESS");
}

pub struct Solution {
    pub orders: Vec<Order>,
}

pub struct Order {
    /// True if the order is an exact output order.
    pub exact_out: bool,
    /// The token being sold (exact in) or bought (exact out).
    pub given_token: Bytes,
    /// Amount of the given token.
    pub given_amount: BigUint,
    /// The token being bought (exact in) or sold (exact out).
    checked_token: Bytes,
    /// Amount of the checked token.
    pub check_amount: BigUint,
    /// Address of the sender.
    pub sender: Bytes,
    /// Address of the receiver.
    pub receiver: Bytes,
    /// List of swaps to fulfill the order.
    pub swaps: Vec<Swap>,
    /// Whether to include router calldata (true) or just swap data (false).
    add_router_calldata: bool,
    // if not set, then the Propeller Router will be used
    pub router_address: Option<Bytes>,
    // if set, it will be applied to check_amount
    pub slippage: Option<f64>,
    // if set, the corresponding native action will be executed
    pub native_action: Option<NativeAction>,
}

#[derive(Clone)]
pub enum NativeAction {
    Wrap,
    Unwrap,
}

#[derive(Clone)]
pub struct Swap {
    /// Protocol component from tycho indexer
    pub component: ProtocolComponent,
    /// Token being input into the pool.
    pub token_in: Bytes,
    /// Token being output from the pool.
    pub token_out: Bytes,
    /// Fraction of the amount to be swapped in this operation.
    pub split: f64,
}

pub struct EncodingContext {
    pub receiver: Bytes,
    pub exact_out: bool,
    pub router_address: Bytes,
}

pub enum ActionType {
    SingleExactIn = 1,
    SingleExactOut = 2,
    SequentialExactIn = 3,
    SequentialExactOut = 4,
    SplitIn = 5,
}
