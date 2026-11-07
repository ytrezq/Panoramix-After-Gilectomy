<p align="center">
    <a href="https://gammaswap.com" target="_blank" rel="noopener noreferrer">
        <img width="100" src="https://app.gammaswap.com/logo.svg" alt="Gammaswap logo">
    </a>
</p>

<p align="center">
  <a href="https://github.com/gammaswap/v1-deltaswap/actions/workflows/main.yml">
    <img src="https://github.com/gammaswap/v1-deltaswap/actions/workflows/main.yml/badge.svg?branch=main" alt="Compile/Test/Publish">
  </a>
</p>

<h1 align="center">V1-DeltaSwap</h1>

## Description
DeltaSwap is an AMM that employes the constant product market maker formula used by UniswapV2 but without or low trading fees on transactions with low market impact

## Note
Built with solidity version 0.8.19 because Arbitrum doesn't support 0.8.21

## Steps to Run GammaSwap Tests Locally

1. Run `yarn` to install GammaSwap dependencies
2. Run `yarn test` to run hardhat tests
3. Run `yarn fuzz` to run foundry tests 
   
    *must use second init code hash when running foundry tests.

## Note 
If code is updated print init code hash for hardhat tests from DeltaSwapFactory.spec.ts. Uncomment the part in the BeforeEach statement. This is the first init_code_hash shown in DeltaSwapLibrary.sol.
For foundry tests uncomment the part in DeltaSwapSetup.sol initDeltaSwap. This is the second init code hash.

The difference in initcode hashes for foundry tests and hardhat tests seems to be because of foundry inserting metadata into the solidity code, which makes the code compile to a different bytecode and unrecognized by the router contract.
The actual bytecode use in a live network would be the one in the first line of the DeltaSwapLibrary.sol file. The one produced by the Factory contract hardhat unit test.
