# Derive (derive)

- Scope: 39 addresses on the Derive chain (explorer.lyra.finance): the matching system (Matching, DepositModule, TradeModule, TransferModule, WithdrawalModule) and the v2 core (SubAccounts, CashAsset, InterestRateModel, SecurityModule, DutchAuction, StandardManager and its viewer, PMRM/PMRMLib and BasePortfolioViewer per market, Base/Option/Perp assets, spot/forward/vol/rate/spot-diff feeds). No repository is linked in the scope.
- Copied (default branches; the repositories have no tags):
  - lyra-finance/v2-matching (f6c20f4): Matching and its modules; it pins v2-core (7736900), lyra-utils and OpenZeppelin as submodules, copied below lib/.
  - lyra-finance/v2-core (96796a6): the core contracts at their latest version (newer than the commit v2-matching pins).
- Not taken: lyra-finance/lyra-utils (a library, already present as a submodule of both), sigp/public-audits (audit PDF).
- The deployed versions were not tied to commits; several addresses per contract name are the per-market instances (ETH, BTC, ...).
