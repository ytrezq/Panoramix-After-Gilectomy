# Granite Protocol (granite-protocol): not EVM

- Scope: Stacks contracts written in Clarity, on explorer.hiro.so (state-v1, liquidity-provider-v1, borrower-v1, liquidator-v1, linear-kinked-ir-v1, governance-v1, meta-governance-v1, pyth-adapter-v1, flash-loan-v1, constants, staking-reward-v1 and several deployment txids), plus the app.granite.world front end.
- The "other-evm" addresses in programs.json are Stacks transaction ids, not EVM addresses.
- GraniteProtocol/core-v1 (linked for its audits) holds Clarity only (35 .clar at HEAD fdcf750).
- Nothing copied.
