<p align="center"><a href="https://gammaswap.com" target="_blank" rel="noopener noreferrer"><img width="100" src="https://app.gammaswap.com/logo.svg" alt="Gammaswap logo"></a></p>

<p align="center">
  <a href="https://github.com/gammaswap/gs-token/actions/workflows/pr.yml">
    <img src="https://github.com/gammaswap/gs-token/actions/workflows/main.yml/badge.svg?branch=main" alt="Compile/Test/Publish">
  </a>
</p>

<h1 align="center">V1-Deployment</h1>

## Description
GammaSwap token used to secure liquidation and rebalancing logic in exchange for protocol fees

# Deployment Steps

1. Run 01-deploy-gs-token.ts in every chain
    (No need to set up mintGSTokenTo or initialGSTokenAmt in helper-hardhat-config.ts unless it's first deployment)
2. Update helper-hardhat-config.ts
    Set lzEid and lzEndpoing for new chain from LayerZero's docs
    Set addresses of GS Token deployed in every chain in helper-hardhat-config.ts in erc20Tokens section in networkConfigInfo
    Add the chain name to developmentLzPeers and productionLzPeers in helper-hardhat-config.ts
    Add gnosis multisig address as timelock proposer and executor
3. Run 02-deploy-set-lzpeers.ts to connect every token to every token in every chain where it is deployed.
    If it's the first deployment, it must be run for every chain.
4. Run 03-deploy-timelock-controller.ts to deploy timelockController for new GS token chain (use a short minDelay)
5. Run 05-transfer-gs-ownership.ts to transfer GS Token ownership to timelock-controller
6. Run 07-update-enforced-options.ts on all non-new chains to set the enforced options from all peers to new peer.
7. Run 08-deploy-timelock-set-lzpeers.ts to set LZ peers of non-new chains to new peer
8. Check that network has correct configurations using task lz-config.ts. Make sure DVNs and Libs are not dead.
   If they're not set or are dead then set the DVNs, SendLib, ReceiveLib, and Executor following the steps from section below.
8. Run 06-update-timelock-delay.ts, to set the timelock on the new chain to 1 day (set minDelay to 1 day in seconds)

# How to set DVNs, SendLib, ReceiveLib, and Executors

*The delegate of GS token has to also be the timelockController. Otherwise the timelockController
won't be able to set the configurations. Set the delegate using task lz-set-delegate.ts.

1. Fill in LZ configurations in helper-hardhat-config.ts.
    Get DVNs from https://docs.layerzero.network/v2/deployments/dvn-addresses
    Get Send/Rec/Exec Libs from https://docs.layerzero.network/v2/deployments/deployed-contracts
2. Make sure the DVN count, confirmations, and providers from send to receive chain match.
3. Run task lz-set-config.ts
4. Check configurations were set correctly (i.e. they match on both send and receive chain) using task lz-config.ts
