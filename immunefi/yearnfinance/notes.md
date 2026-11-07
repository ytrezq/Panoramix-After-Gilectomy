# Yearn Finance

- Scope: 47 Ethereum addresses (V3 vaults/factories 3.0.4 and 3.1.0, tokenized strategies, Accountant, Splitter and Auction
  factories, yCRV and its boosted staker, the yYB suite, the stYFI suite, YFI and Woofy tokens, yvUSD), matched by name:
  - yearn/yearn-vaults-v3 at tag v3.1.0 (5b698f94, AGPL-3.0; Vyper vault + factory) and yearn/tokenized-strategy at v3.1.0
    (8c8929f1, AGPL-3.0): the scope's "V3.1.0" contracts; the 3.0.4 ones were not copied (one ref per repository).
  - yearn/tokenized-strategy-periphery (master 1e334fbd; per-file licenses, 3 unlicensed files skipped): AuctionFactory.
  - yearn/yearn-boosted-staker (master a6aee4bc, AGPL-3.0): yCRV/yYB boosted stakers and reward distributors.
  - yearn/yearn-yb (master 16d73ac2; per-file, 1 skipped): yYB token (YToken), Locker, Operator.
- yearn/vault-periphery (master 9cc62d28: Accountant, SplitterFactory) and yearn/styfi (master 001dda50: all stYFI contracts,
  Vyper): no license file; copied per file from their `SPDX-License-Identifier: GNU AGPLv3` / Vyper `@license GNU AGPLv3`
  headers (18 and 16 files without an open license skipped, mostly tests and mocks).
- Recorded by reference only: yearn/woofy (f4a68023, Woofy.vy): no license at all.
- Not found: the YFI token (2020; yearn/ygov-finance and yearn/governance hold no sources), the yCRV token (docs link only
  Etherscan; yearn/yCRV is now a frontend, not recorded). yvUSD is a V3 vault instance.
- Default branches as of 2026-11-07; deployed versions not checked against Etherscan except via the version names.
