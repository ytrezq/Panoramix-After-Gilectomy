# The Graph

- Scope: 36 addresses on Ethereum and Arbitrum: legacy protocol (GRT, staking,
  GNS, Curation, RewardsManager, DisputeManager, gateways, Controller...), Horizon
  (HorizonStaking, GraphPayments, PaymentsEscrow, GraphTallyCollector,
  SubgraphService), the Rewards Eligibility Oracle, billing (Billing,
  BillingConnector, BanxaWrapper) and a GraphTokenLockWallet.
- Copied at default branches (no deployment tags): graphprotocol/contracts (pnpm
  monorepo: contracts, horizon, subgraph-service, issuance (REO), token-distribution
  ...), graphprotocol/billing-contracts (found by code search),
  graphprotocol/token-distribution (archived; named by the scope description).
- Left out: rewards-eligibility-oracle (Python service). Not found under these
  names: Governor (a multisig), LegacyDisputeManager, LegacyServiceRegistry.
- Workspace packages (@graphprotocol/interfaces, horizon, contracts) are linked
  in the packages' node_modules; npm dependencies (pnpm catalog included) copied.
