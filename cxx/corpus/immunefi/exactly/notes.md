# Exactly (exactly)

- Scope: 22 Optimism addresses (Auditor, Markets for USDC, USDC.e, WETH, wstETH, OP, WBTC, interest-rate models, RewardsController, DebtManager, InstallmentsRouter, MarketETHRouter, EscrowedEXA, StakedEXA, TimelockController; the Exa app's ExaPlugin, WebAuthnOwnerPlugin, IssuerChecker, Refunder, ProposalManager) and Primacy of Impact. No repository is linked in the scope.
- Copied:
  - exactly/protocol at v0.2.25 (644b11c), its latest release tag (= default branch HEAD): the protocol and its periphery; TimelockController is OpenZeppelin's (in its node_modules).
  - exactly/exa, default branch (f341780), scope contracts/ (Foundry project): ExaPlugin, IssuerChecker, Refunder, ProposalManager, ...; WebauthnOwnerPlugin comes with the npm dependency exactly/webauthn-owner-plugin#9c0c38b under contracts/node_modules/.
- exa has no root license: its sources carry GPL-3.0/AGPL-3.0 headers (copied on those).
- Not taken: exactly/audits (reports). The deployed versions were not checked address by address.
