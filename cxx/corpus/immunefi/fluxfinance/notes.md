# fluxfinance

- Scope: 9 smart-contract assets, Ethereum addresses: Unitroller (Comptroller), the fTokens fDAI, fFRAX, fOUSG, fUSDC,
  fUSDT, OndoPriceOracle V2, GovernorBravoDelegator and Timelock.
- No in-scope repository link; the page links flux-finance/contracts and compound-finance/compound-protocol at
  a3214f6 (the Compound v2 code Flux forked).
- Copied: flux-finance/contracts @ main (default branch): the Compound v2 fork (Comptroller, cToken / cErc20 delegator
  and delegate, rate models, GovernorBravo, Timelock) in contracts/lending/compound, OndoPriceOracle / V2, KYC
  registry client, Ondo token contracts.
- Not copied separately: compound-finance/compound-protocol (the upstream; flux-finance/contracts carries its own copy,
  and compoundfinance's corpus entry already holds compound-protocol at that same commit).
