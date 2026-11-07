# Open Term Maple Loan

![Foundry CI](https://github.com/maple-labs/open-term-loan/actions/workflows/forge.yml/badge.svg)
[![GitBook - Documentation](https://img.shields.io/badge/GitBook-Documentation-orange?logo=gitbook&logoColor=white)](https://maplefinance.gitbook.io/maple/technical-resources/protocol-overview)
[![Foundry][foundry-badge]][foundry]
[![License: BUSL 1.1](https://img.shields.io/badge/License-BUSL%201.1-blue.svg)](https://github.com/maple-labs/open-term-loan/blob/main/LICENSE)

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Overview

This repo contains a set of contracts to facilitate on-chain Loans between Maple Finance Pools and institutional borrowers. These contracts contain logic to:
1. Deploy new Loans.
2. Perform Loan funding.
3. Draw down funds.
4. Manage collateral.
5. Calculate payment amounts and schedules (can handle amortized and interest-only payment structures).
6. Perform repossessions of collateral and remaining funds in a defaulted Loan.
7. Claim interest and principal from Loans.
8. Perform refinancing operations when a lender and borrower agree to new terms.
9. Upgrade Loan logic using upgradeability patterns.

## Dependencies/Inheritance

Contracts in this repo inherit and import code from:
- [`maple-labs/erc20`](https://github.com/maple-labs/erc20)
- [`maple-labs/erc20-helper`](https://github.com/maple-labs/erc20-helper)
- [`maple-labs/maple-proxy-factory`](https://github.com/maple-labs/maple-proxy-factory)

Contracts inherit and import code in the following ways:
- `MapleLoan` and `MapleLoanFeeManager` use `IERC20` and `ERC20Helper` for token interactions.
- `MapleLoan` inherits `MapleProxiedInternals` for proxy logic.
- `MapleLoanFactory` inherits `MapleProxyFactory` for proxy deployment and management.

Versions of dependencies can be checked with `git submodule status`.

## Setup

This project was built using [Foundry](https://book.getfoundry.sh/). Refer to installation instructions [here](https://github.com/foundry-rs/foundry#installation).

```sh
git clone git@github.com:maple-labs/open-term-loan.git
cd open-term-loan
forge install
```

## Running Tests
- To run all tests: `forge test`
- To run specific tests: `forge test --match <test_name>`

`./scripts/test.sh` is used to enable Foundry profile usage with the `-p` flag. Profiles are used to specify the number of fuzz runs.

## Audit Reports

### December 2022 Release

| Auditor | Report Link |
|---|---|
| Trail of Bits | [`2022-08-24 - Trail of Bits Report`](https://docs.google.com/viewer?url=https://github.com/maple-labs/maple-v2-audits/files/10246688/Maple.Finance.v2.-.Final.Report.-.Fixed.-.2022.pdf) |
| Spearbit | [`2022-10-17 - Spearbit Report`](https://docs.google.com/viewer?url=https://github.com/maple-labs/maple-v2-audits/files/10223545/Maple.Finance.v2.-.Spearbit.pdf) |
| Three Sigma | [`2022-10-24 - Three Sigma Report`](https://docs.google.com/viewer?url=https://github.com/maple-labs/maple-v2-audits/files/10223541/three-sigma_maple-finance_code-audit_v1.1.1.pdf) |

<br>

### June 2023 Release

| Auditor | Report Link |
|---|---|
| Spearbit Auditors via Cantina | [`2023-06-05 - Cantina Report`](https://docs.google.com/viewer?url=https://github.com/maple-labs/maple-v2-audits/files/11667848/cantina-maple.pdf) |
| Three Sigma | [`2023-04-10 - Three Sigma Report`](https://docs.google.com/viewer?url=https://github.com/maple-labs/maple-v2-audits/files/11663546/maple-v2-audit_three-sigma_2023.pdf) |

### August 2024 Release 
| Auditor | Report Link |
|---|---|
| 0xMacro | [`2024-08-14 - 0xMacro Report`](https://github.com/maple-labs/syrup-utils/blob/main/audits/0xMacro-Maple-Finance-Aug-2024.pdf) |
| Three Sigma | [`2024-08-23 - Three Sigma Report`](https://github.com/maple-labs/syrup-utils/blob/main/audits/ThreeSigma-Maple-Finance-Aug-2024.pdf) |

## Bug Bounty

For all information related to the ongoing bug bounty for these contracts run by [Immunefi](https://immunefi.com/), please visit this [site](https://immunefi.com/bounty/maple/).

## About Maple

[Maple Finance](https://maple.finance) is a decentralized corporate credit market. Maple provides capital to institutional borrowers through globally accessible fixed-income yield opportunities.

---

<p align="center">
  <img src="https://user-images.githubusercontent.com/44272939/196706799-fe96d294-f700-41e7-a65f-2d754d0a6eac.gif" height="100" />
</p>
