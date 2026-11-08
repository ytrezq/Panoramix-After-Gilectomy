# aave

- Scope: 83 smart-contract assets: 79 GitHub file links into 10 repositories (at the refs the links name), 3 Etherscan
  addresses (Aave v2 Lending Rate Oracle, WrappedTokenGatewayV2, Collector) and a Primacy of Impact placeholder.
- Copied, all from the scope links, at their refs: aave-dao/aave-v3-origin@main (34 files: Pool, configurators, logic
  libraries, tokens, rewards), aave/aave-v3-core@master (StableDebtToken), bgd-labs/aave-collector-unification@main
  (Collector), aave-dao/gho-origin@main (GHO, GSM, facilitators, flash minter, GhoOracle), bgd-labs/aave-stk-gov-v3@main
  (StakedAaveV3), bgd-labs/stake-token@main (StakeToken), aave/protocol-v2@master (20 Aave v2 files),
  bgd-labs/solidity-utils@7a7548c (TransparentUpgradeableProxy), bgd-labs/aave-governance-v3@main (governance, voting,
  payloads), aave/ccip@d5c6ced (GHO CCIP token pools in contracts/src/v0.8/ccip/pools/GHO/).
- aave/ccip is Aave's fork of Chainlink's CCIP monorepo: its whole contracts/ tree came along (not the Go node code).
- Left out: bgd-labs/aave-address-book (address library linked from the page) and smartcontractkit/ccip (upstream).
- Addresses: the Collector is aave-collector-unification; WrappedTokenGatewayV2 is closest to protocol-v2's
  contracts/misc/WETHGateway.sol (its own deployed source is not in these repositories); the v2 LendingRateOracle
  exists in protocol-v2 only as contracts/mocks/oracle/LendingRateOracle.sol.
