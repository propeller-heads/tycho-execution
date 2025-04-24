#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use alloy::{
        node_bindings,
        primitives::{Address, FixedBytes, U256},
        providers::{ext::AnvilApi, ProviderBuilder},
        signers::local::PrivateKeySigner,
        sol,
    };

    sol!(
        #[sol(rpc)]
        TychoRouter,
        "foundry/out/TychoRouter.sol/TychoRouter.json"
    );

    sol!(
        #[sol(rpc)]
        UniswapV2Executor,
        "foundry/out/UniswapV2Executor.sol/UniswapV2Executor.json"
    );

    #[tokio::test]
    async fn test() {
        // Spin up a forked Anvil node.
        // Ensure `anvil` is available in $PATH.
        let rpc_url = "https://reth-ethereum.ithaca.xyz/rpc";
        let anvil = node_bindings::Anvil::new()
            .fork(rpc_url)
            .fork_block_number(22082754)
            .try_spawn()
            .unwrap();
        let signer: PrivateKeySigner = anvil.keys()[0].clone().into();

        let provider = ProviderBuilder::new()
            .wallet(signer)
            .connect_http(anvil.endpoint_url());

        // Get node info using the Anvil API.
        let info = provider
            .anvil_node_info()
            .await
            .unwrap();

        println!("Node info: {:#?}", info);
        let permit2_address =
            Address::from_str("0x000000000022D473030F116dDEE9F6B43aC78BA3").unwrap();
        let router_contract = TychoRouter::deploy(
            &provider,
            permit2_address,
            Address::from_str("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2").unwrap(),
        )
        .await
        .expect("Failed to deploy contract");
        println!("Deployed contract at address: {}", router_contract.address());

        let univ2_executor = UniswapV2Executor::deploy(
            &provider,
            Address::from_str("0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f").unwrap(),
            FixedBytes::from_str(
                "0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f",
            )
            .unwrap(),
            permit2_address,
            U256::from(30),
        )
        .await
        .expect("Failed to deploy contract");
        println!("Deployed univ2 executor contract at address: {}", univ2_executor.address());

        let result = router_contract
            .setExecutors(vec![*univ2_executor.address()])
            .send()
            .await;

        match result {
            Ok(_) => {
                println!("Executors set successfully");
            }
            Err(err) => {
                // TODO: figure out how to decode
                let decoded_err = err
                    .as_decoded_interface_error::<Errors::ErrorsErrors>()
                    .unwrap();
                println!("Error setting executors: {:?}", decoded_err);
            }
        }

        // let executors = router_contract
        //     .executors(*univ2_executor.address())
        //     .call()
        //     .await
        //     .unwrap();
        // println!("Executors: {:?}", executors);
    }
}
