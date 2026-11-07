# Ondo Finance — RWA Contracts

Source code for Ondo Finance's Real World Asset (RWA) smart contracts, published
set by set as products are announced. All contracts here are deployed on-chain
and verified; this repository exists to make the source easy to read, build,
and audit in one place.

## Contents

| Set | Description |
| --- | --- |
| OUSG | Tokenized exposure to short-term US Treasury securities: the OUSG token and rOUSG (rebasing wrapper). Mint/redeem lives in xManager. |
| USDY | US Dollar Yield token: USDY variants (blocklist/sanctions/allowlist), rUSDY (rebasing wrapper), manager, and compliance components. |
| xManager | Nexus unified RWA mint/redeem system: instant managers (OUSG, USDY), token router, token sources/recipients, compliance, ID registry, oracles, rate limiter. |
| Global Markets | Tokenized equities platform: GMToken, USDon (+ manager/converter), token factory and registrars, token manager with issuance hours and sanity-check oracle, compliance, pause manager. |
| Portfolio Tokens | Baskets of Global Markets tokens: portfolio token manager (attestation-based mint/redeem), token factory and registrar, orchestrator (invests/divests into underlying GM tokens), vault, and fee engine. |
| Limit Orders | On-chain limit orders for Global Markets and Portfolio tokens: shared order base/library/storage and the GMTokenLimitOrder and PortfolioTokenLimitOrder executors. |
| Continuous Price Oracle | Price oracles for RWA tokens: ContinuousPriceOracle (price accrues at a continuously compounded yearly rate, with an optional scheduled next rate) and ScheduledOracleSwitch (forwards reads from an old oracle to a new one at a fixed cutover timestamp). |

Shared infrastructure (RWAHub base contracts, pricing, KYC client, interfaces)
and vendored third-party dependencies (`contracts/external/`) are included as
needed by each set.

## Building

Requires [Foundry](https://book.getfoundry.sh/) (built with forge 1.7.1).

```bash
forge build
```

## Provenance

Each published set has a manifest in `manifests/` recording the SHA-256 of every
file and the toolchain version used, so builds are reproducible and the source
can be checked byte-for-byte against on-chain verified contracts (e.g. with
`forge verify-bytecode`).

## Licensing

Files are licensed per their SPDX header. Ondo-authored contracts are licensed
under the Business Source License 1.1 (see `LICENSE`). `contracts/external/`
contains third-party code (OpenZeppelin, Chainlink, Circle, M^0, and others)
under their original licenses with headers preserved: OpenZeppelin files are MIT,
and `contracts/external/m0/ContinuousIndexingMath.sol` is GPL-3.0. Each file's
own header applies.

## Security

For security concerns, please contact: security@ondo.finance

Bug bounty program: https://immunefi.com/bug-bounty/ondofinance/information/
