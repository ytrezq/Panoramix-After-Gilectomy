# Ava Labs Avalanche (avalanche)

- Scope: AvalancheGo and libevm (Go node software, Blockchain/DLT assets: not copied), the ICM contracts (icm-services/icm-contracts, Solidity), and 25 bridged tokens on the Avalanche C-Chain (DAI.e, USDC.e, WETH.e, WBTC.e, BTC.b, LINK.e, ... on snowtrace).
- ava-labs/icm-services at main (ba08d13), scope icm-contracts: recorded by reference only, its root LICENSE is Ava Labs' Ecosystem License (not an open license; most headers say LicenseRef-Ecosystem).
- ava-labs/avalanche-bridge-resources (default branch, 97e5c93): SmartContracts/BridgeToken.sol (+ Roles.sol), the contract behind the bridged tokens; Sourcify matches BTC.b and WETH.e to BridgeToken.sol (solc 0.8.11 and 0.8.0). Found by search; the token addresses are listed in the same repository.
- Out-of-scope links not taken: go-ethereum, subnet-evm, coreth (node software), ava-labs/audits, avalanchego-internal.
- Not checked one by one: that every one of the 25 token addresses runs this BridgeToken version.
