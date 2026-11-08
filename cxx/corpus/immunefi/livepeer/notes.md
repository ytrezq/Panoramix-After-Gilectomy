# livepeer

- Scope: 23 smart-contract assets, explorer addresses: on Arbitrum the Livepeer protocol (Controller, BondingManager,
  BondingVotes, RoundsManager, TicketBroker, Minter, ServiceRegistry, LivepeerToken, SortedDoublyLL, LivepeerGovernor,
  Governor, Treasury, MerkleSnapshot, PollCreator, DelegatorPool, L2LPTGateway, L2LPTDataCache, L2Migrator); on
  Ethereum the bridge side (L1LPTGateway, L1Escrow, L1LPTDataCache, L1Migrator, BridgeMinter).
- No in-scope repository link; the page links livepeer/protocol and livepeer/arbitrum-lpt-bridge.
- Copied (default branches): livepeer/protocol @ delta (the protocol contracts, governance, treasury, polling,
  DelegatorPool...) and livepeer/arbitrum-lpt-bridge @ main (L1/L2 gateways, escrow, migrators, data caches,
  BridgeMinter).
- Every scope name matched a contract of these two repositories; the copies are the current heads.
