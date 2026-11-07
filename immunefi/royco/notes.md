# Royco (royco)

- Scope: the RoycoFactory (same address on Ethereum, Arbitrum, Avalanche; "all markets and their components in scope"), Senior Royco USDC (srRoyUSDC), the Royco Vault Makina Strategy, a Multisig Strategy and a Multisig Safe on Ethereum, plus the dawn.royco.org app. No repository is linked in the scope.
- Repositories (default branches), recorded by reference only, nothing copied:
  - roycoprotocol/royco-dawn (d68947a): the factory and the markets; Sourcify's RoycoFactory implementation (0x34DB2f42..., solc 0.8.34) is src/factory/RoycoFactory.sol, the same blob from v1.2.1 to HEAD. Its LICENSE.md is not an open license and most headers say UNLICENSED.
  - roycoprotocol/royco-vault-makina-strategy (3ba424d): RoycoVaultMakinaStrategy (verified on Sourcify as src/RoycoVaultMakinaStrategy.sol); no license, UNLICENSED headers. It pulls the Concrete Earn v2 vault code as a submodule, likely the srRoyUSDC vault and the Multisig Strategy (both unverified on Sourcify).
- Not covered: the Multisig Safe (a Safe proxy; Safe's contracts are not in this program's repositories).
- Not taken: roycoprotocol/royco-day (a newer protocol line, linked for its audit; the factory deployed is royco-dawn's).
