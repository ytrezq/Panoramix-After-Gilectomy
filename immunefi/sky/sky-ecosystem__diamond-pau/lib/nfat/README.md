# NFAT Facility

An NFAT Facility manages bespoke capital deployment deals between depositors (Primes) and borrowers (Halos).

- **Subscribe**: Depositors queue an asset (e.g. sUSDS) into the facility.
- **Withdraw**: Depositors can at any time withdraw queued funds not yet deployed.
- **Issue**: The operator deploys queued capital to the borrower and mints an ERC-721 Non-Fungible Allocation Token (NFAT) to the depositor, representing their claim on future repayments.
- **Repay**: The borrower repays into the facility against a given NFAT.
- **Collect**: The NFAT holder collects repayments (principal and interest).

Deal terms (APY, maturity, payment frequency, etc) are tracked off-chain; the contract handles only capital flows.

## Assumptions

It is assumed that only simple, regular ERC-20 tokens will be used as `gem`. In particular, the supported tokens are assumed to revert on failure (instead of returning false), not to execute any hook or apply any fee on transfer, and not to execute any rebasing logic.
