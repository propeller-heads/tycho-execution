use std::str::FromStr;

use num_bigint::BigUint;
use tycho_core::{models::Chain, Bytes};

use crate::encoding::{
    errors::EncodingError,
    evm::constants::{native_address, wrapped_address},
    models::{NativeAction, Solution, Transaction},
    strategy_encoder::StrategyEncoderRegistry,
    tycho_encoder::TychoEncoder,
};

pub struct EVMTychoEncoder<S: StrategyEncoderRegistry> {
    strategy_selector: S,
    router_address: Bytes,
    native_address: Bytes,
    wrapped_address: Bytes,
}

impl<S: StrategyEncoderRegistry> EVMTychoEncoder<S> {
    pub fn new(
        strategy_selector: S,
        router_address: String,
        chain: Chain,
    ) -> Result<Self, EncodingError> {
        let router_address = Bytes::from_str(&router_address)
            .map_err(|_| EncodingError::FatalError("Invalid router address".to_string()))?;
        let native_address = native_address(chain);
        let wrapped_address = wrapped_address(chain);
        if chain != Chain::Ethereum {
            return Err(EncodingError::InvalidInput(
                "Currently only Ethereum is supported".to_string(),
            ));
        }
        Ok(EVMTychoEncoder { strategy_selector, router_address, native_address, wrapped_address })
    }
}

impl<S: StrategyEncoderRegistry> EVMTychoEncoder<S> {
    fn validate_solution(&self, solution: &Solution) -> Result<(), EncodingError> {
        if solution.exact_out {
            return Err(EncodingError::FatalError(
                "Currently only exact input solutions are supported".to_string(),
            ));
        }
        if solution.swaps.is_empty() {
            return Err(EncodingError::FatalError("No swaps found in solution".to_string()));
        }
        if let Some(native_action) = solution.clone().native_action {
            if native_action == NativeAction::Wrap {
                if solution.given_token != self.native_address {
                    return Err(EncodingError::FatalError(
                        "Native token must be the input token in order to wrap".to_string(),
                    ));
                }
                if let Some(first_swap) = solution.swaps.first() {
                    if first_swap.token_in != self.wrapped_address {
                        return Err(EncodingError::FatalError(
                            "Wrapped token must be the first swap's input in order to wrap"
                                .to_string(),
                        ));
                    }
                }
            } else if native_action == NativeAction::Unwrap {
                if solution.checked_token != self.native_address {
                    return Err(EncodingError::FatalError(
                        "Native token must be the output token in order to unwrap".to_string(),
                    ));
                }
                if let Some(last_swap) = solution.swaps.last() {
                    if last_swap.token_out != self.wrapped_address {
                        return Err(EncodingError::FatalError(
                            "Wrapped token must be the last swap's output in order to unwrap"
                                .to_string(),
                        ));
                    }
                }
            }
        }
        Ok(())
    }
}

impl<S: StrategyEncoderRegistry> TychoEncoder<S> for EVMTychoEncoder<S> {
    fn encode_router_calldata(
        &self,
        solutions: Vec<Solution>,
    ) -> Result<Vec<Transaction>, EncodingError> {
        let mut transactions: Vec<Transaction> = Vec::new();
        for solution in solutions.iter() {
            self.validate_solution(solution)?;

            let router_address = solution
                .router_address
                .clone()
                .unwrap_or(self.router_address.clone());

            let strategy = self
                .strategy_selector
                .get_encoder(solution)?;
            let (contract_interaction, target_address) =
                strategy.encode_strategy(solution.clone(), router_address)?;

            let value = match solution.native_action.as_ref() {
                Some(NativeAction::Wrap) => solution.given_amount.clone(),
                _ => BigUint::ZERO,
            };

            transactions.push(Transaction {
                value,
                data: contract_interaction,
                to: target_address,
            });
        }
        Ok(transactions)
    }
}

#[cfg(test)]
mod tests {
    use tycho_core::{dto::ProtocolComponent, models::Chain};

    use super::*;
    use crate::encoding::{
        models::Swap, strategy_encoder::StrategyEncoder, swap_encoder::SwapEncoder,
    };

    struct MockStrategyRegistry {
        strategy: Box<dyn StrategyEncoder>,
    }

    fn dai() -> Bytes {
        Bytes::from_str("0x6b175474e89094c44da98b954eedeac495271d0f").unwrap()
    }

    fn eth() -> Bytes {
        native_address(Chain::Ethereum)
    }

    fn weth() -> Bytes {
        wrapped_address(Chain::Ethereum)
    }

    impl StrategyEncoderRegistry for MockStrategyRegistry {
        fn new(
            _chain: Chain,
            _executors_file_path: &str,
            _signer_pk: Option<String>,
        ) -> Result<MockStrategyRegistry, EncodingError> {
            Ok(Self { strategy: Box::new(MockStrategy) })
        }

        fn get_encoder(
            &self,
            _solution: &Solution,
        ) -> Result<&Box<dyn StrategyEncoder>, EncodingError> {
            Ok(&self.strategy)
        }
    }

    struct MockStrategy;

    impl StrategyEncoder for MockStrategy {
        fn encode_strategy(
            &self,
            _solution: Solution,
            _router_address: Bytes,
        ) -> Result<(Vec<u8>, Bytes), EncodingError> {
            Ok((
                Bytes::from_str("0x1234")
                    .unwrap()
                    .to_vec(),
                Bytes::from_str("0xabcd").unwrap(),
            ))
        }

        fn get_swap_encoder(&self, _protocol_system: &str) -> Option<&Box<dyn SwapEncoder>> {
            None
        }
    }

    fn get_mocked_tycho_encoder() -> EVMTychoEncoder<MockStrategyRegistry> {
        let strategy_selector = MockStrategyRegistry::new(Chain::Ethereum, "", None).unwrap();
        EVMTychoEncoder::new(
            strategy_selector,
            "0x1234567890abcdef1234567890abcdef12345678".to_string(),
            Chain::Ethereum,
        )
        .unwrap()
    }

    #[test]
    fn test_encode_router_calldata() {
        let encoder = get_mocked_tycho_encoder();
        let eth_amount_in = BigUint::from(1000u32);
        let swap = Swap {
            component: ProtocolComponent {
                id: "0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11".to_string(),
                protocol_system: "uniswap_v2".to_string(),
                ..Default::default()
            },
            token_in: weth(),
            token_out: dai(),
            split: 0f64,
        };

        let solution = Solution {
            exact_out: false,
            given_amount: eth_amount_in.clone(),
            given_token: eth(),
            router_address: None,
            swaps: vec![swap],
            native_action: Some(NativeAction::Wrap),
            ..Default::default()
        };

        let transactions = encoder.encode_router_calldata(vec![solution]);

        assert!(transactions.is_ok());
        let transactions = transactions.unwrap();
        assert_eq!(transactions.len(), 1);
        assert_eq!(transactions[0].value, eth_amount_in);
        assert_eq!(transactions[0].data, Bytes::from_str("0x1234").unwrap());
        assert_eq!(transactions[0].to, Bytes::from_str("0xabcd").unwrap());
    }

    #[test]
    fn test_validate_fails_for_exact_out() {
        let encoder = get_mocked_tycho_encoder();
        let solution = Solution {
            exact_out: true, // This should cause an error
            ..Default::default()
        };
        let result = encoder.validate_solution(&solution);

        assert!(result.is_err());
        assert_eq!(
            result.err().unwrap(),
            EncodingError::FatalError(
                "Currently only exact input solutions are supported".to_string()
            )
        );
    }

    #[test]
    fn test_validate_passes_for_wrap() {
        let encoder = get_mocked_tycho_encoder();
        let swap = Swap {
            component: ProtocolComponent {
                id: "0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11".to_string(),
                protocol_system: "uniswap_v2".to_string(),
                ..Default::default()
            },
            token_in: weth(),
            token_out: dai(),
            split: 0f64,
        };

        let solution = Solution {
            exact_out: false,
            given_token: eth(),
            checked_token: dai(),
            check_amount: None,
            swaps: vec![swap],
            native_action: Some(NativeAction::Wrap),
            ..Default::default()
        };

        let result = encoder.validate_solution(&solution);

        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_fails_for_wrap_wrong_input() {
        let encoder = get_mocked_tycho_encoder();
        let swap = Swap {
            component: ProtocolComponent {
                id: "0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11".to_string(),
                protocol_system: "uniswap_v2".to_string(),
                ..Default::default()
            },
            token_in: weth(),
            token_out: dai(),
            split: 0f64,
        };

        let solution = Solution {
            exact_out: false,
            given_token: weth(),
            swaps: vec![swap],
            native_action: Some(NativeAction::Wrap),
            ..Default::default()
        };

        let result = encoder.validate_solution(&solution);

        assert!(result.is_err());
        assert_eq!(
            result.err().unwrap(),
            EncodingError::FatalError("Native token must be the input token in order to wrap".to_string())
        );
    }

    #[test]
    fn test_validate_fails_for_wrap_wrong_first_swap() {
        let encoder = get_mocked_tycho_encoder();
        let swap = Swap {
            component: ProtocolComponent {
                id: "0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11".to_string(),
                protocol_system: "uniswap_v2".to_string(),
                ..Default::default()
            },
            token_in: eth(),
            token_out: dai(),
            split: 0f64,
        };

        let solution = Solution {
            exact_out: false,
            given_token: eth(),
            swaps: vec![swap],
            native_action: Some(NativeAction::Wrap),
            ..Default::default()
        };

        let result = encoder.validate_solution(&solution);

        assert!(result.is_err());
        assert_eq!(
            result.err().unwrap(),
            EncodingError::FatalError(
                "Wrapped token must be the first swap's input in order to wrap".to_string()
            )
        );
    }

    #[test]
    fn test_validate_fails_no_swaps() {
        let encoder = get_mocked_tycho_encoder();
        let solution = Solution {
            exact_out: false,
            given_token: eth(),
            swaps: vec![],
            native_action: Some(NativeAction::Wrap),
            ..Default::default()
        };

        let result = encoder.validate_solution(&solution);

        assert!(result.is_err());
        assert_eq!(
            result.err().unwrap(),
            EncodingError::FatalError("No swaps found in solution".to_string())
        );
    }

    #[test]
    fn test_validate_passes_for_unwrap() {
        let encoder = get_mocked_tycho_encoder();
        let swap = Swap {
            component: ProtocolComponent {
                id: "0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11".to_string(),
                protocol_system: "uniswap_v2".to_string(),
                ..Default::default()
            },
            token_in: dai(),
            token_out: weth(),
            split: 0f64,
        };

        let solution = Solution {
            exact_out: false,
            checked_token: eth(),
            check_amount: None,
            swaps: vec![swap],
            native_action: Some(NativeAction::Unwrap),
            ..Default::default()
        };

        let result = encoder.validate_solution(&solution);

        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_fails_for_unwrap_wrong_output() {
        let encoder = get_mocked_tycho_encoder();
        let swap = Swap {
            component: ProtocolComponent {
                id: "0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11".to_string(),
                protocol_system: "uniswap_v2".to_string(),
                ..Default::default()
            },
            token_in: dai(),
            token_out: weth(),
            split: 0f64,
        };

        let solution = Solution {
            exact_out: false,
            given_token: dai(),
            checked_token: weth(),
            swaps: vec![swap],
            native_action: Some(NativeAction::Unwrap),
            ..Default::default()
        };

        let result = encoder.validate_solution(&solution);

        assert!(result.is_err());
        assert_eq!(
            result.err().unwrap(),
            EncodingError::FatalError(
                "Native token must be the output token in order to unwrap".to_string()
            )
        );
    }

    #[test]
    fn test_validate_fails_for_unwrap_wrong_last_swap() {
        let encoder = get_mocked_tycho_encoder();
        let swap = Swap {
            component: ProtocolComponent {
                id: "0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11".to_string(),
                protocol_system: "uniswap_v2".to_string(),
                ..Default::default()
            },
            token_in: dai(),
            token_out: eth(),
            split: 0f64,
        };

        let solution = Solution {
            exact_out: false,
            checked_token: eth(),
            swaps: vec![swap],
            native_action: Some(NativeAction::Unwrap),
            ..Default::default()
        };

        let result = encoder.validate_solution(&solution);

        assert!(result.is_err());
        assert_eq!(
            result.err().unwrap(),
            EncodingError::FatalError(
                "Wrapped token must be the last swap's output in order to unwrap".to_string()
            )
        );
    }
}
