# Staked USDS

An implementation of a yield-bearing USDS token, which aims at ensuring that all staked-SKY-backed borrowing is funded by segregated risk capital.
Depositors, who in practice provide insurance funds to the system, take on several risks, such as stake engine bad debt accrual, or Sky governance risk (see `Trust Assumptions and Suppliers Considerations` below).

## Overview

Users can deposit USDS to mint stUSDS up to a defined global cap.

The stUSDS total value is determined by:
* Total deposited USDS and accrued yield.
* Amount of stake engine bad debt, which was written off when concluding past auctions.
* Past governance slashing operations. 

Although, from that total value, users can only redeem USDS limited by the withdrawable amount, which is determined by the current total value minus:
* Existing stake engine debt.
* Amount of USDS currently in auction (disregarding the liquidation penalty).

The stUSDS contract sets the stake engine debt ceiling dynamically, as part of its different actions.

Conversely, the stUSDS supply rate and stake engine borrow rate are set asynchronously through privileged configurations (`file()`).
Those configurations are managed through the StUsdsRateSetter contract, which allows governance-configured operators to set the params, with some security restrictions.

Similarly, the StUsdsRateSetter also sets the stUSDS supply cap and max debt ceiling, also with some governance-configured limitations.

The stUSDS contract supports ERC4626. It uses the ERC-1822 UUPS pattern for upgradeability and the ERC-1967 proxy storage slots standard.
It is important that the `StUsdsDeploy` library sequence be used for deploying.

#### OZ upgradeability validations

The OZ validations can be run alongside the existing tests:
`VALIDATE=true forge test --ffi --build-info --extra-output storageLayout`

## Referral Code

The `deposit` and `mint` functions accept an optional `uint16 referral` parameter that frontends can use to mark deposits as originating from them. Such deposits emit a `Referral(uint16 indexed referral, address indexed owner, uint256 assets, uint256 shares)` event. This could be used to implement a revshare campaign, in which case the off-chain calculation scheme will likely need to keep track of any `Transfer` and `Withdraw` events following a `Referral` for a given token owner.

## Notes, Disclaimers and Known Issues:

### Trust Assumptions and Suppliers Considerations:
* stUSDS suppliers should know they trust Sky governance completely. Governance could upgrade the contract, and possibly during the gov delay period all funds are borrowed, so withdrawing is not possible.
* The `cut` function (which slashes USDS out of the contract) was designed for being called by the stake engine Clipper when bad debt is accrued. However, as Sky governance is authed on the stUSDS contract, it has the ability to also call it directly. This does not change any trust assumption due to the previous comment.
* stUSDS suppliers should also be aware that operators of the Rate Setter (appointed by governance) can set rates in a way that all funds are borrowed, so it is up to governance to make sure that over time they aim to allow withdrawals.
* The stUSDS system does not use the debt ceiling Instant Access Module (aka autoline), but instead allows the deposit and withdraw code to set the `line` to any value under the max borrow line. This means that in specific situations the borrowed amount can move very fast. In practice, it implies that stUSDS depositors also take the risk for oracles reporting a very high price and allowing minting of "cheap" usds, which the autoline usually mitigates against with it's pacing.
* The desirable status in the system is that the non-withdrawable amount backs the stake engine debt, but there is nothing preventing stUSDS redeems of the other funds. There is a likely possibility that these other funds will be withdrawn when people speculate that bad debt will be created, or see that a governance action to slash is coming. If it's clear that slashing is going to happen then we can even expect all withdrawable funds to be pulled. This can create large swings in the deposit amount, and also prevent the bad debt from being better socialized. This needs to be taken into account by suppliers.
* Deposits could be griefed by other deposits (because of the cap). Withdrawals could be griefed by borrowers. Borrows could be griefed by suppliers. These scenarios are assumed to be mitigated by the option to use flashbots and by the economic cost of such griefing for a long period.
* Note that not being able to redeem all stUSDS instantly, and slashing due to bad debt accrual, might bring a risk of depeg/devaluation on other markets. 3rd-party integrations should be aware of this risk.
* Users need to be aware that at the initial phase when stUSDS is still being filled up with deposits to balance out the existing loans debt, the impact of a cut call could be much more damaging for these users' deposits. Also within this timeframe, users won't be able to withdraw at all.
* In the very rare case where `chi` was cut to an extremely low non-zero value (for example RAY/1000) it is advised not to deposit to the contract. Further deposits may suffer from rounding errors.

### Accounting:
* In general the system aims to maintain a status where the supplied funds including accruals always back the debt. However this is not guaranteed (for example because of stability fee accrual or past `cut` operations).
* The supply cap is assumed to mitigate against large protocol losses for temporary cases where  the combination of supply rate and deposits outweighs the borrow rates and borrows.
* It is assumed that in case of migration to a new stake engine and/or a new clipper, the accounting of both the old contracts and the new ones will be examined as part of the process.
* If after the stUSDS launch and LockstakeClipper replacement, there is still a remaining auction running from the previous clipper (which doesn't track `Due` value), that debt won't be taken into account for calculating the `line` setting.

### Rate Setter:
* The Rate Setter logic is based on [SPBEAM](https://github.com/sky-ecosystem/sp-beam). Its various security considerations are assumed here as well (e.g "Asymmetrical Risks Between Rate Increase and Decrease", "Considerations for Configurations"), see SPBEAM audit [reports](https://github.com/sky-ecosystem/sp-beam/tree/master/audits).
* There is no pacing mechanism for the Rate Setter's `cap` and `line` setting, as it is assumed that the combination of the max values and the rate pacing ("steps") are enough to protect against big losses.
* The Rate Setter operators off-chain algorithm is assumed to take into account manipulation attempts. For example, it can use an average past utilization, and possibly introduce some variance in its samples. If needed, it is assumed to be updated when manipulations are spotted.
* It is assumed that a max rate of 50% is enough (as supported in the [Conv](https://github.com/sky-ecosystem/rates-conv) module). If needed, the Rate Setter could be replaced to support higher rates.
* The Rate Setter needs to have one or more `buds` for all practical use cases. If more than one is added, it is assumed they are well coordinated.

## Shutdown

The implementation assumes Maker emergency shutdown can not be triggered. Any system shutdown should be orchestrated by Maker governance.

## Copyright

The original code was created by hexonaut (SavingsDai) and the MakerDAO devs (Pot).
Since it should belong to the MakerDAO community the Copyright for the code has been transferred to Dai Foundation

