# Tycho Router

Contain the TychoRouter contracts.

Currently, there are only contracts for the Ethereum Virtual Machine.

## Setup

Install foudryup and foundry
```
$ curl -L https://foundry.paradigm.xyz | bash
$ foundryup
```

Also install hardhat & dependencies. 
Node version v20.1.0 working with hardhat@2.16.1 is a confirmed setup. 
[Hardhat](https://github.com/nodejs/release#release-schedule) documentation of node support.
```
yarn
```

## Running tests

```
$ forge test -vvv --fork-url <RPC URL>
```

some usefull flags :
```
--v -> --vvvvv (the more "v" you add, the more information will be displayed)
--match-contract <regex pattern> (will run all the tests the contains the regex i.e: --match-contract testMultiswapV3_1)
--match-test <regex pattern> (will run all the tests the contains the regex. i.e: --match-test uniswapV2Call will run (test_uniswapV2Call_authorized(),test_uniswapV2Call_reject_non_usv2_caller(),test_uniswapV2Call_reject_unknown_sender())
--debug <function name>
```

https://book.getfoundry.sh/reference/forge/forge-test


## Code formatting

Run `forge fmt`.

