# Lido

- Scope: 19 GitHub repositories (links name no ref), docs.lido.fi/deployed-contracts,
  and the Lido websites/apps (not EVM).
- Copied at their default branch's HEAD: core, aave-delivery-infrastructure,
  governance-crosschain-bridges, lido-l2, lido-l2-with-steth,
  mev-boost-relay-allowed-list (Vyper), circuit-breaker, community-staking-module,
  easy-track, stonks, lido-vesting-escrow (Vyper), dual-governance, aragon-apps.
- Left out (off-chain, no EVM sources): onchain-mon (Go), lido-council-daemon,
  lido-keys-api, validator-ejector (TypeScript), lido-oracle, oz-merkle-tree (Python).
- Deployed addresses are on docs.lido.fi/deployed-contracts; default branches may be
  ahead of what is deployed (no per-deployment tags used).
- core's npm dependencies are copied, @aragon/apps-lido (a GitHub archive URL) as
  a clone of that repository at the archive's ref.
- circuit-breaker has no license file: copied on its open SPDX headers.
