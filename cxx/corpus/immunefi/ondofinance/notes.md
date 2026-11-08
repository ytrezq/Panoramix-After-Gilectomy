# ondofinance

- Scope: 123 smart-contract assets, explorer addresses only: on Ethereum (54), BSC (35), Mantle, Arbitrum, Polygon,
  Sei, Plume, X Layer, Tempo, plus Solana, Aptos and Noble assets. EVM contracts: OUSG / rOUSG, USDY / rUSDY and their
  managers and oracles, the xManager stack (OndoCompliance, OndoIDRegistry, OndoOracle, OndoRateLimiter, OndoTokenRouter,
  sources / recipients, instant RWA managers), Ondo Global Markets (GMToken, GMTokenFactory/Manager, GMIssuerManager,
  USDon, PortfolioToken*), OndoOFT / OndoMintBurnAdapter bridges, KYCRegistry.
- No in-scope repository link; the only one on the page (ondoprotocol/usdy-noble) is a Cosmos/Noble module.
- Copied (found among ondoprotocol's public repositories, default branches): ondoprotocol/rwa-contracts (OUSG, rOUSG,
  USDY managers, rUSDY, xManager, globalMarkets: GM tokens, USDon, portfolio tokens, issuance hours) and
  ondoprotocol/usdy (the USDY token, USDYManager, RWAHub, allowlist / blocklist).
- Left out (not EVM): the Solana programs, the Aptos USDY and the Noble USDY.
- Not obviously covered: OndoOFT / RateLimiter (OFTs), OndoMintBurnAdapter, Messenger, Inspector,
  SyntheticSharesOracle, and the KYCRegistry itself on Polygon (only its interface and client are in rwa-contracts):
  no public repository found for those.
