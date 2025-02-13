use tycho_core::{dto::Chain, Bytes};

use crate::encoding::{errors::EncodingError, models::Solution, swap_encoder::SwapEncoder};

/// Encodes a solution using a specific strategy.
pub trait StrategyEncoder {
    fn encode_strategy(
        &self,
        to_encode: Solution,
    ) -> Result<(Vec<u8>, Bytes, Option<String>), EncodingError>;

    #[allow(clippy::borrowed_box)]
    fn get_swap_encoder(&self, protocol_system: &str) -> Option<&Box<dyn SwapEncoder>>;
    fn clone_box(&self) -> Box<dyn StrategyEncoder>;
}

/// Contains the supported strategies to encode a solution, and chooses the best strategy to encode
/// a solution based on the solution's attributes.
pub trait StrategyEncoderRegistry {
    fn new(
        chain: Chain,
        executors_file_path: Option<String>,
        signer_pk: Option<String>,
    ) -> Result<Self, EncodingError>
    where
        Self: Sized;

    /// Returns the strategy encoder that should be used to encode the given solution.
    #[allow(clippy::borrowed_box)]
    fn get_encoder(&self, solution: &Solution) -> Result<&Box<dyn StrategyEncoder>, EncodingError>;
}
