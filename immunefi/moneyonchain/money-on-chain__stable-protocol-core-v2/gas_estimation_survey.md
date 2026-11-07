# StableX multi-network gas survey.

This report compares gas costs for the StableX stablecoin protocol across candidate target networks.

It estimates both queuing and execution costs for all protocol operations and quantifies how much of each network’s block gas limit our transactions consume.

It also informs cost constraints for supporting multiple collaterals. This is an initial viability check, other requisites and costs such as oracles to use and cost of other protocol tasks are out of scope.

Target networks are Ethereum, Arbitrum, Polygon and BSC.

## Initial StableX configuration assumptions

StableX is expected to launch with 2 pegs (EUR, USD) and 2 to 4 collaterals (XAUT, WBTC, RBTC, tbills).

## Methodology

We simulate 100 executions of each operation and collect minimum, maximum, and average gas consumption.

For queuing, we simulate:

- A queue with 1 item, representing the worst case and most common scenario.

- A queue with 10 items, representing the best case. We do not expect queues to exceed 10 items, even under favorable conditions.

Gas prices are computed using each network’s minimum, average, median, and maximum gas prices over the past month, along with the most recent price of the fee token. ETH is used on Ethereum and Arbitrum, POL on Polygon, and BNB on BSC. All gas and pricing data is sourced from block explorers.

For each network, we compute queuing costs assuming a protocol with 5 pegged tokens, although queuing is not affected by the number of collaterals or pegs.

## Execution cost model

For each network, we simulate deployments with:

- 2 to 5 collaterals, and

- 2 to 5 pegged tokens per collateral configuration.

This yields 16 deployment variants per network. For each variant, we report five pricing columns. Worst case is maximum gas at maximum gas price. Best case is minimum gas at minimum gas price. We also compute estimated costs by multiplying average gas by the minimum, average, median, and maximum gas prices.

## Sources of error and methodological limitations

Fee token prices are fixed to the most recent value, which introduces error because it does not reflect price variation over the full month.

Hardhat gas estimates are systematically lower than on-chain measurements, and the gap varies by network. We apply a gasAdjustmentMultiplier of 1.20 for most networks and 1.10 for BSC.

In the current simulation code, one collateral is always the base coin rather than an ERC20 token.

## Observations

### Protocol level observations

Block gas limits are not a constraint. All transactions remain well below 1 percent of the block gas limit on every network evaluated.

Adding pegged tokens increases gas usage by approximately 7 to 22 percent, depending on the operation and the number of collaterals.

The incremental cost of adding each additional pegged token decreases by roughly 10 to 15 percent as the peg count grows. For example, mintTP with 3 pegs is 19 percent more expensive than with 2 pegs, while moving from 3 to 4 pegs increases cost by only 16 percent.

Sensitivity to peg count varies by operation. For example, mintTC and swapTPforTC increase by about 7 percent when moving from 2 to 3 pegs, while redeemTC and mintTP increase by about 18 percent and 15 percent, respectively.

More collaterals increase the marginal cost of adding pegged tokens. For example, redeemTC increases by 18 percent when moving from 2 to 3 pegs with 2 collaterals, but increases by 22 percent with 5 collaterals.

Adding collaterals can increase gas usage by roughly 10 to 100 percent. The marginal cost of additional collaterals decreases as more collaterals are added. More pegged tokens also increase gas usage, but the effect is comparatively small.

Example: mintTP with 3 collaterals is 93 percent more expensive than with only 2 collaterals, but moving from 3 to 4 collaterals increases cost by just 62 percent.

The per-action progress tables in appendix A summarize these dynamics for the most frequent operations.

## Estimated cost for StableX with 2 pegs and 3 collaterals, by network

Although Ethereum is the preferred launch network, we evaluate other networks for comparison. For each operation, we report minimum and maximum gas consumption. Combined with minimum and maximum gas prices, these produce the Best and Worst cost estimates. We also compute expected dollar costs by multiplying average gas consumption by the minimum, average, median, and maximum gas prices.

A complete dataset covering all peg and collateral variants is provided in Appendix B.

### Ethereum:

We consider ethereum at 3245 USD and adjust our local gas estimations for a 20% increase on mainnet.

On ethereum a swap is 356190, an nft sale 601953, a bridging 114556, and a borrowing 302169.

Our most expensive action mintTP, including queue and execution costs, is about 5 times the cost of a typical ethereum swap. Our cheapest, redeemTP is 2.5 times the cost of a swap.

These are the fees for enqueing actions. Nothing costs more than a typical swap just to add it to the queue. Nothing is over 0.30 USD.

| Action         | Gas    | Min fee @ 0.027gw | $ Min  | Avg fee @ 0.2494gw | $ Avg  | Median fee @ 0.1475gw | $ Median | Max fee @ 2.31gw | $ Max  |
| -------------- | ------ | ----------------- | ------ | ------------------ | ------ | --------------------- | -------- | ---------------- | ------ |
| mintTC         | 280278 | 7567506000000     | 0.0246 | 69901333200000     | 0.2268 | 41341005000000        | 0.1342   | 647442180000000  | 2.1009 |
| redeemTC       | 257028 | 6939756000000     | 0.0225 | 64102783200000     | 0.2080 | 37911630000000        | 0.1230   | 593734680000000  | 1.9267 |
| mintTP         | 287759 | 7769493000000     | 0.0252 | 71767094600000     | 0.2329 | 42444452500000        | 0.1377   | 664723290000000  | 2.1570 |
| redeemTP       | 279650 | 7550550000000     | 0.0245 | 69744710000000     | 0.2263 | 41248375000000        | 0.1339   | 645991500000000  | 2.0962 |
| swapTPforTP    | 342821 | 9256167000000     | 0.0300 | 85499557400000     | 0.2774 | 50566097500000        | 0.1641   | 791916510000000  | 2.5698 |
| swapTPforTC    | 315461 | 8517447000000     | 0.0276 | 78675973400000     | 0.2553 | 46530497500000        | 0.1510   | 728714910000000  | 2.3647 |
| swapTCforTP    | 320234 | 8646318000000     | 0.0281 | 79866359600000     | 0.2592 | 47234515000000        | 0.1533   | 739740540000000  | 2.4005 |
| redeemTCandTP  | 317005 | 8559135000000     | 0.0278 | 79061047000000     | 0.2566 | 46758237500000        | 0.1517   | 732281550000000  | 2.3763 |
| mintTCandTP    | 288104 | 7778808000000     | 0.0252 | 71853137600000     | 0.2332 | 42495340000000        | 0.1379   | 665520240000000  | 2.1596 |
| execSettlement | 170743 | 4610061000000     | 0.0150 | 42583304200000     | 0.1382 | 25184592500000        | 0.0817   | 394416330000000  | 1.2799 |

When the actions execute as the only item in the queue, these would be the expected prices:
| Action | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
|------------------|--------|---------|--------------------|---------------------|---------------------|-------------------|
| mintTC | 0.0507 | 5.4686 | 0.0553 | 0.5106 | 0.3020 | 4.7294 |
| redeemTC | 0.0743 | 6.8578 | 0.0778 | 0.7182 | 0.4248 | 6.6522 |
| mintTP | 0.1184 | 10.9005 | 0.1227 | 1.1334 | 0.6703 | 10.4974 |
| redeemTP | 0.0424 | 4.1920 | 0.0457 | 0.4219 | 0.2495 | 3.9075 |
| swapTPforTC | 0.0680 | 6.3358 | 0.0724 | 0.6685 | 0.3953 | 6.1916 |
| swapTCforTP | 0.0905 | 8.2699 | 0.0940 | 0.8687 | 0.5138 | 8.0462 |
| redeemTCandTP | 0.1118 | 10.0782 | 0.1156 | 1.0680 | 0.6316 | 9.8917 |
| mintTCandTP | 0.0481 | 4.6730 | 0.0512 | 0.4731 | 0.2798 | 4.3817 |
| swapTPforTP | 0.0621 | 10.7578 | 0.0879 | 0.8122 | 0.4804 | 7.5232 |

When the que has 10 actions on average, these are the prices, about 40% savings across the board.
| Action | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
|------------------|--------|---------|--------------------|---------------------|---------------------|-------------------|
| mintTC | 0.0132 | 8.3350 | 0.0287 | 0.2653 | 0.1569 | 2.4569 |
| redeemTC | 0.0522 | 7.3161 | 0.0697 | 0.6435 | 0.3806 | 5.9603 |
| mintTP | 0.0425 | 10.6499 | 0.0725 | 0.6697 | 0.3961 | 6.2028 |
| redeemTP | 0.0186 | 4.0354 | 0.0302 | 0.2785 | 0.1647 | 2.5796 |
| swapTPforTC | 0.0190 | 6.3150 | 0.0364 | 0.3365 | 0.1990 | 3.1167 |
| swapTCforTP | 0.0644 | 8.7712 | 0.0888 | 0.8204 | 0.4852 | 7.5988 |
| redeemTCandTP | 0.0397 | 10.0363 | 0.0652 | 0.6021 | 0.3561 | 5.5765 |
| mintTCandTP | 0.0218 | 4.5165 | 0.0351 | 0.3242 | 0.1917 | 3.0025 |
| swapTPforTP | 0.0179 | 10.7739 | 0.0503 | 0.4645 | 0.2747 | 4.3021 |

### Arbitrum

On arbitrum, the median fee is lower than the minimum on ethereum mainnet.

Adding things to the queue:

| Action         | estimatedGas | min fee @ 0.01gw | $ min  | avg fee @ 0.029gw | $ avg  | median fee @ 0.019gw | $ median | max fee @ 1.0gw | $ max  |
| -------------- | ------------ | ---------------- | ------ | ----------------- | ------ | -------------------- | -------- | --------------- | ------ |
| mintTC         | 280278       | 2802780000000    | 0.0091 | 8128062000000     | 0.0264 | 5325282000000        | 0.0173   | 280278000000000 | 0.9095 |
| redeemTC       | 257028       | 2570280000000    | 0.0083 | 7453812000000     | 0.0242 | 4883532000000        | 0.0158   | 257028000000000 | 0.8341 |
| mintTP         | 287759       | 2877590000000    | 0.0093 | 8345011000000     | 0.0271 | 5467421000000        | 0.0177   | 287759000000000 | 0.9338 |
| redeemTP       | 279650       | 2796500000000    | 0.0091 | 8109850000000     | 0.0263 | 5313350000000        | 0.0172   | 279650000000000 | 0.9075 |
| swapTPforTP    | 342821       | 3428210000000    | 0.0111 | 9941809000000     | 0.0323 | 6513599000000        | 0.0211   | 342821000000000 | 1.1125 |
| swapTPforTC    | 315461       | 3154610000000    | 0.0102 | 9148369000000     | 0.0297 | 5993759000000        | 0.0194   | 315461000000000 | 1.0237 |
| swapTCforTP    | 320234       | 3202340000000    | 0.0104 | 9286786000000     | 0.0301 | 6084446000000        | 0.0197   | 320234000000000 | 1.0392 |
| redeemTCandTP  | 317005       | 3170050000000    | 0.0103 | 9193145000000     | 0.0298 | 6023095000000        | 0.0195   | 317005000000000 | 1.0287 |
| mintTCandTP    | 288104       | 2881040000000    | 0.0093 | 8355016000000     | 0.0271 | 5473976000000        | 0.0178   | 288104000000000 | 0.9349 |
| execSettlement | 170743       | 1707430000000    | 0.0055 | 4951547000000     | 0.0161 | 3244117000000        | 0.0105   | 170743000000000 | 0.5541 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 3; Pegs: 2; Gas adjustment: 1.2

| Action        | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| ------------- | ------ | ------- | ----------------- | ------------------ | ------------------ | ---------------- |
| mintTC        | 0.0187 | 2.3673  | 0.0205            | 0.0593             | 0.0389             | 2.0463           |
| redeemTC      | 0.0276 | 2.9758  | 0.0288            | 0.0834             | 0.0546             | 2.8756           |
| mintTP        | 0.0439 | 4.6999  | 0.0455            | 0.1319             | 0.0864             | 4.5487           |
| redeemTP      | 0.0157 | 1.8045  | 0.0169            | 0.0490             | 0.0321             | 1.6885           |
| swapTPforTC   | 0.0252 | 2.7518  | 0.0268            | 0.0777             | 0.0509             | 2.6793           |
| swapTCforTP   | 0.0334 | 3.6297  | 0.0349            | 0.1013             | 0.0664             | 3.4939           |
| redeemTCandTP | 0.0411 | 4.3640  | 0.0427            | 0.1240             | 0.0812             | 4.2745           |
| mintTCandTP   | 0.0178 | 2.0212  | 0.0189            | 0.0547             | 0.0358             | 1.8868           |
| swapTPforTP   | 0.0232 | 4.6651  | 0.0339            | 0.0983             | 0.0644             | 3.3909           |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 3; Pegs: 2; Gas adjustment: 1.2

| Action        | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| ------------- | ------ | ------- | ----------------- | ------------------ | ------------------ | ---------------- |
| mintTC        | 0.0051 | 10.5980 | 0.0123            | 0.0357             | 0.0234             | 1.2325           |
| redeemTC      | 0.0194 | 2.9937  | 0.0260            | 0.0755             | 0.0494             | 2.6022           |
| mintTP        | 0.0176 | 4.6539  | 0.0274            | 0.0794             | 0.0520             | 2.7383           |
| redeemTP      | 0.0069 | 1.7481  | 0.0114            | 0.0331             | 0.0217             | 1.1412           |
| swapTPforTC   | 0.0071 | 2.7428  | 0.0138            | 0.0401             | 0.0263             | 1.3819           |
| swapTCforTP   | 0.0242 | 3.8118  | 0.0332            | 0.0964             | 0.0631             | 3.3231           |
| redeemTCandTP | 0.0148 | 4.3381  | 0.0246            | 0.0713             | 0.0467             | 2.4574           |
| mintTCandTP   | 0.0081 | 1.9564  | 0.0133            | 0.0385             | 0.0253             | 1.3290           |
| swapTPforTP   | 0.0083 | 4.6036  | 0.0183            | 0.0530             | 0.0347             | 1.8263           |

### Binance smart chain:

It's very cheap and gas prices are fixed to 0.05gw. The only variation may occur due to fee token price fluctuations, which we take at 885 USD for these estimations.
Also, the gas adjustment is just at 1.1 because their gas calculation matches more closely the usual hardhat gas calculations.

BSC users are used to pay a bit less than 0.01USD for swaps and adding or removing liquidity pools. A BEP20 (erc20) token transfer is fixed at 0.003.
While we would be more expensive, none of our actions, even in the worst case scenario, go over 6 cents.

Nothing costs more than 2 cents to add to the queue.

| Action         | estimatedGas | avg fee @ 0.05gw | $ avg  |
| -------------- | ------------ | ---------------- | ------ |
| mintTC         | 256922       | 12846100000000   | 0.0114 |
| redeemTC       | 235609       | 11780450000000   | 0.0104 |
| mintTP         | 263779       | 13188950000000   | 0.0117 |
| redeemTP       | 256346       | 12817300000000   | 0.0113 |
| swapTPforTP    | 314252       | 15712600000000   | 0.0139 |
| swapTPforTC    | 289172       | 14458600000000   | 0.0128 |
| swapTCforTP    | 293548       | 14677400000000   | 0.0130 |
| redeemTCandTP  | 290588       | 14529400000000   | 0.0129 |
| mintTCandTP    | 264096       | 13204800000000   | 0.0117 |
| execSettlement | 156515       | 7825750000000    | 0.0069 |

Execution costs for just a single item in the queue.

| Action        | minGas  | avgGas  | maxGas  | $ Best | $ Worst | $ avgGas @ 0.05gw |
| ------------- | ------- | ------- | ------- | ------ | ------- | ----------------- |
| mintTC        | 530691  | 576961  | 668741  | 0.0235 | 0.0296  | 0.0255            |
| redeemTC      | 771293  | 814543  | 838630  | 0.0341 | 0.0371  | 0.0360            |
| mintTP        | 1238709 | 1284959 | 1316499 | 0.0548 | 0.0583  | 0.0569            |
| redeemTP      | 444063  | 476147  | 509758  | 0.0196 | 0.0226  | 0.0211            |
| swapTPforTC   | 709103  | 754999  | 775128  | 0.0314 | 0.0343  | 0.0334            |
| swapTCforTP   | 946559  | 988298  | 1014256 | 0.0419 | 0.0449  | 0.0437            |
| redeemTCandTP | 1159177 | 1209423 | 1235094 | 0.0513 | 0.0547  | 0.0535            |
| mintTCandTP   | 502742  | 532158  | 584143  | 0.0222 | 0.0258  | 0.0235            |
| swapTPforTP   | 661186  | 963055  | 1316490 | 0.0293 | 0.0583  | 0.0426            |

Execution costs for 10 things in the queue.

| Action        | minGas | avgGas | maxGas  | $ Best | $ Worst | $ avgGas @ 0.05gw |
| ------------- | ------ | ------ | ------- | ------ | ------- | ----------------- |
| mintTC        | 142291 | 317973 | 2022666 | 0.0063 | 0.0895  | 0.0141            |
| redeemTC      | 536404 | 744450 | 836651  | 0.0237 | 0.0370  | 0.0329            |
| mintTP        | 445485 | 797360 | 1304804 | 0.0197 | 0.0577  | 0.0353            |
| redeemTP      | 195662 | 329129 | 493823  | 0.0087 | 0.0219  | 0.0146            |
| swapTPforTC   | 195969 | 403863 | 774453  | 0.0087 | 0.0343  | 0.0179            |
| swapTCforTP   | 678660 | 951113 | 1083969 | 0.0300 | 0.0480  | 0.0421            |
| redeemTCandTP | 417827 | 721242 | 1232778 | 0.0185 | 0.0546  | 0.0319            |
| mintTCandTP   | 229538 | 379943 | 552647  | 0.0102 | 0.0245  | 0.0168            |
| swapTPforTP   | 256255 | 534478 | 1317446 | 0.0113 | 0.0583  | 0.0237            |

### Polygon:

It's the absolute cheapest. Our research showed the highest gas price is 439gwei, but it's a gross outlier. The most frequent maximum is 30gwei.

At 439gwei prices are in the same ballpark as BNB.

In reality, most of the time, any of our actions would cost less than 0.01 USD.

# Appendix A:

These tables show how gas consumption increases when adding more collaterals and pegs for some actions.

### mintTP

| Collaterals / Pegs | 2       | →      | 3       | →      | 4       | →      | 5       |
| ------------------ | ------- | ------ | ------- | ------ | ------- | ------ | ------- |
| 2                  | 724169  | 15.41% | 835746  | 13.98% | 952607  | 11.90% | 1066012 |
| ↓                  | 93.38%  |        | 98.57%  |        | 102.08% |        | 105.06% |
| 3                  | 1400413 | 18.51% | 1659571 | 16.00% | 1925048 | 13.55% | 2185917 |
| ↓                  | 62.44%  |        | 65.28%  |        | 66.55%  |        | 67.87%  |
| 4                  | 2274800 | 20.58% | 2743010 | 16.89% | 3206256 | 14.44% | 3669395 |
| ↓                  | 47.11%  |        | 48.47%  |        | 49.78%  |        | 50.56%  |
| 5                  | 3346418 | 21.70% | 4072441 | 17.92% | 4802281 | 15.04% | 5524714 |

### redeemTP

| Collaterals / Pegs | 2      | →     | 3      | →     | 4      | →     | 5      |
| ------------------ | ------ | ----- | ------ | ----- | ------ | ----- | ------ |
| 2                  | 432828 | 7.71% | 466203 | 7.22% | 499852 | 6.54% | 532533 |
| ↓                  | 20.44% |       | 21.17% |       | 21.33% |       | 21.35% |
| 3                  | 521282 | 8.36% | 564882 | 7.37% | 606489 | 6.55% | 646210 |
| ↓                  | 12.39% |       | 12.70% |       | 14.56% |       | 15.23% |
| 4                  | 585843 | 8.67% | 636612 | 9.14% | 694790 | 7.17% | 744626 |
| ↓                  | 11.67% |       | 12.51% |       | 11.48% |       | 12.89% |
| 5                  | 654228 | 9.48% | 716247 | 8.14% | 774539 | 8.53% | 840611 |

### mintTC

| Collaterals / Pegs | 2       | →     | 3       | →     | 4       | →     | 5       |
| ------------------ | ------- | ----- | ------- | ----- | ------- | ----- | ------- |
| 2                  | 392270  | 9.03% | 427711  | 7.45% | 459585  | 7.66% | 494799  |
| ↓                  | 60.84%  |       | 60.80%  |       | 62.45%  |       | 62.79%  |
| 3                  | 630930  | 9.01% | 687754  | 8.56% | 746605  | 7.88% | 805468  |
| ↓                  | 39.32%  |       | 39.65%  |       | 39.70%  |       | 39.89%  |
| 4                  | 879010  | 9.26% | 960443  | 8.60% | 1043028 | 8.03% | 1126755 |
| ↓                  | 27.92%  |       | 28.19%  |       | 28.21%  |       | 28.04%  |
| 5                  | 1124432 | 9.50% | 1231217 | 8.61% | 1337226 | 7.89% | 1442667 |

### redeemTC

| Collaterals / Pegs | 2       | →      | 3       | →      | 4       | →      | 5       |
| ------------------ | ------- | ------ | ------- | ------ | ------- | ------ | ------- |
| 2                  | 659208  | 18.89% | 783749  | 16.16% | 910437  | 13.85% | 1036561 |
| ↓                  | 34.62%  |        | 36.11%  |        | 37.54%  |        | 38.24%  |
| 3                  | 887437  | 20.21% | 1066778 | 17.38% | 1252231 | 14.43% | 1432972 |
| ↓                  | 23.20%  |        | 24.97%  |        | 25.74%  |        | 26.35%  |
| 4                  | 1093317 | 21.93% | 1333125 | 18.11% | 1574586 | 14.99% | 1810566 |
| ↓                  | 19.33%  |        | 19.86%  |        | 20.15%  |        | 20.79%  |
| 5                  | 1304620 | 22.48% | 1597876 | 18.40% | 1891829 | 15.60% | 2186994 |

### swapTpForTp

| Collaterals / Pegs | 2       | →      | 3       | →      | 4       | →      | 5       |
| ------------------ | ------- | ------ | ------- | ------ | ------- | ------ | ------- |
| 2                  | 515744  | 9.84%  | 566478  | 12.14% | 635234  | 3.83%  | 659547  |
| ↓                  | 86.73%  |        | 86.94%  |        | 81.01%  |        | 97.05%  |
| 3                  | 963055  | 9.96%  | 1058985 | 8.58%  | 1149844 | 13.03% | 1299650 |
| ↓                  | 46.71%  |        | 55.79%  |        | 55.42%  |        | 58.59%  |
| 4                  | 1412869 | 16.77% | 1649745 | 8.33%  | 1787136 | 15.33% | 2061073 |
| ↓                  | 38.89%  |        | 39.37%  |        | 47.03%  |        | 36.15%  |
| 5                  | 1962388 | 17.17% | 2299319 | 14.28% | 2627624 | 6.79%  | 2806048 |

### swapTpforTc

| Collaterals / Pegs | 2       | →     | 3       | →     | 4       | →     | 5       |
| ------------------ | ------- | ----- | ------- | ----- | ------- | ----- | ------- |
| 2                  | 496240  | 7.02% | 531071  | 6.86% | 567493  | 6.03% | 601699  |
| ↓                  | 65.80%  |       | 66.15%  |       | 66.38%  |       | 65.72%  |
| 3                  | 822757  | 7.25% | 882370  | 7.01% | 944210  | 5.61% | 997154  |
| ↓                  | 40.95%  |       | 40.82%  |       | 40.44%  |       | 40.87%  |
| 4                  | 1159659 | 7.15% | 1242528 | 6.72% | 1326014 | 5.93% | 1404646 |
| ↓                  | 28.74%  |       | 28.90%  |       | 28.59%  |       | 28.91%  |
| 5                  | 1492977 | 7.28% | 1601603 | 6.46% | 1705106 | 6.19% | 1810683 |

# Appendix B:

For review, all raw results are attached below. The test runs for several minutes in order to produce these.
can be run as `GAS_ESTIMATION=true npx hardhat test --typecheck --grep 'General survey' > survey_results.txt`

ETH Queueing; Price: $3245; Gas adjustment: 1.2
| (index) | blockGasLimit | estimatedGas | gasLeftPct | min fee @ 0.027gw | $ min | avg fee @ 0.2494gw | $ avg | median fee @ 0.1475gw | $ median | max fee @ 2.31gw | $ max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 60000000 | 280278 | 99.53% | 7567506000000 | 0.0246 | 69901333200000 | 0.2268 | 41341005000000 | 0.1342 | 647442180000000 | 2.1009 |
| redeemTC | 60000000 | 257028 | 99.57% | 6939756000000 | 0.0225 | 64102783200000 | 0.2080 | 37911630000000 | 0.1230 | 593734680000000 | 1.9267 |
| mintTP | 60000000 | 287759 | 99.52% | 7769493000000 | 0.0252 | 71767094600000 | 0.2329 | 42444452500000 | 0.1377 | 664723290000000 | 2.1570 |
| redeemTP | 60000000 | 279650 | 99.53% | 7550550000000 | 0.0245 | 69744710000000 | 0.2263 | 41248375000000 | 0.1339 | 645991500000000 | 2.0962 |
| swapTPforTP | 60000000 | 342821 | 99.43% | 9256167000000 | 0.0300 | 85499557400000 | 0.2774 | 50566097500000 | 0.1641 | 791916510000000 | 2.5698 |
| swapTPforTC | 60000000 | 315461 | 99.47% | 8517447000000 | 0.0276 | 78675973400000 | 0.2553 | 46530497500000 | 0.1510 | 728714910000000 | 2.3647 |
| swapTCforTP | 60000000 | 320234 | 99.47% | 8646318000000 | 0.0281 | 79866359600000 | 0.2592 | 47234515000000 | 0.1533 | 739740540000000 | 2.4005 |
| redeemTCandTP | 60000000 | 317005 | 99.47% | 8559135000000 | 0.0278 | 79061047000000 | 0.2566 | 46758237500000 | 0.1517 | 732281550000000 | 2.3763 |
| mintTCandTP | 60000000 | 288104 | 99.52% | 7778808000000 | 0.0252 | 71853137600000 | 0.2332 | 42495340000000 | 0.1379 | 665520240000000 | 2.1596 |
| execSettlement | 60000000 | 170743 | 99.72% | 4610061000000 | 0.0150 | 42583304200000 | 0.1382 | 25184592500000 | 0.0817 | 394416330000000 | 1.2799 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 2; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 358106 | 392270 | 470813 | 0.0314 | 3.5292 | 0.0344 | 0.3175 | 0.1878 | 2.9404 |
| redeemTC | 100 | 626574 | 659208 | 681390 | 0.0549 | 5.1077 | 0.0578 | 0.5335 | 0.3155 | 4.9414 |
| mintTP | 100 | 684986 | 724169 | 767636 | 0.0600 | 5.7542 | 0.0634 | 0.5861 | 0.3466 | 5.4283 |
| redeemTP | 100 | 406601 | 432828 | 466951 | 0.0356 | 3.5002 | 0.0379 | 0.3503 | 0.2072 | 3.2445 |
| swapTPforTC | 100 | 458551 | 497522 | 516787 | 0.0402 | 3.8738 | 0.0436 | 0.4026 | 0.2381 | 3.7294 |
| swapTCforTP | 100 | 782860 | 812200 | 840443 | 0.0686 | 6.2999 | 0.0712 | 0.6573 | 0.3887 | 6.0882 |
| redeemTCandTP | 100 | 669793 | 708730 | 731689 | 0.0587 | 5.4847 | 0.0621 | 0.5736 | 0.3392 | 5.3126 |
| mintTCandTP | 100 | 470612 | 496693 | 530964 | 0.0412 | 3.9801 | 0.0435 | 0.4020 | 0.2377 | 3.7232 |
| swapTPforTP | 100 | 438409 | 571569 | 757194 | 0.0384 | 5.6759 | 0.0501 | 0.4626 | 0.2736 | 4.2845 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 2; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 106812 | 210459 | 412390 | 0.0094 | 3.0913 | 0.0184 | 0.1703 | 0.1007 | 1.5776 |
| redeemTC | 100 | 312242 | 452054 | 677072 | 0.0274 | 5.0753 | 0.0396 | 0.3658 | 0.2164 | 3.3886 |
| mintTP | 100 | 316737 | 473030 | 744958 | 0.0278 | 5.5842 | 0.0414 | 0.3828 | 0.2264 | 3.5458 |
| redeemTP | 100 | 129666 | 247570 | 446800 | 0.0114 | 3.3492 | 0.0217 | 0.2004 | 0.1185 | 1.8558 |
| swapTPforTC | 100 | 151321 | 283795 | 516787 | 0.0133 | 3.8738 | 0.0249 | 0.2297 | 0.1358 | 2.1273 |
| swapTCforTP | 100 | 401983 | 579043 | 830906 | 0.0352 | 6.2284 | 0.0507 | 0.4686 | 0.2772 | 4.3405 |
| redeemTCandTP | 100 | 280711 | 443930 | 731689 | 0.0246 | 5.4847 | 0.0389 | 0.3593 | 0.2125 | 3.3277 |
| mintTCandTP | 100 | 150697 | 289471 | 510602 | 0.0132 | 3.8274 | 0.0254 | 0.2343 | 0.1386 | 2.1699 |
| swapTPforTP | 100 | 173665 | 337189 | 750318 | 0.0152 | 5.6243 | 0.0295 | 0.2729 | 0.1614 | 2.5276 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 2; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 394152 | 427711 | 507228 | 0.0345 | 3.8022 | 0.0375 | 0.3461 | 0.2047 | 3.2061 |
| redeemTC | 100 | 753852 | 783749 | 810584 | 0.0660 | 6.0761 | 0.0687 | 0.6343 | 0.3751 | 5.8749 |
| mintTP | 100 | 797168 | 835746 | 864277 | 0.0698 | 6.4786 | 0.0732 | 0.6764 | 0.4000 | 6.2647 |
| redeemTP | 100 | 442646 | 466203 | 500598 | 0.0388 | 3.7525 | 0.0408 | 0.3773 | 0.2231 | 3.4946 |
| swapTPforTC | 100 | 495781 | 531487 | 570217 | 0.0434 | 4.2743 | 0.0466 | 0.4301 | 0.2544 | 3.9840 |
| swapTCforTP | 100 | 920257 | 956022 | 981624 | 0.0806 | 7.3582 | 0.0838 | 0.7737 | 0.4576 | 7.1663 |
| redeemTCandTP | 100 | 767340 | 802476 | 826837 | 0.0672 | 6.1979 | 0.0703 | 0.6494 | 0.3841 | 6.0153 |
| mintTCandTP | 100 | 506659 | 530540 | 564611 | 0.0444 | 4.2323 | 0.0465 | 0.4294 | 0.2539 | 3.9769 |
| swapTPforTP | 100 | 461555 | 608830 | 874325 | 0.0404 | 6.5539 | 0.0533 | 0.4927 | 0.2914 | 4.5638 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 2; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 117816 | 222977 | 446036 | 0.0103 | 3.3435 | 0.0195 | 0.1805 | 0.1067 | 1.6714 |
| redeemTC | 100 | 395517 | 544198 | 804108 | 0.0347 | 6.0276 | 0.0477 | 0.4404 | 0.2605 | 4.0793 |
| mintTP | 100 | 381423 | 556288 | 853928 | 0.0334 | 6.4010 | 0.0487 | 0.4502 | 0.2663 | 4.1699 |
| redeemTP | 100 | 142453 | 264463 | 480446 | 0.0125 | 3.6014 | 0.0232 | 0.2140 | 0.1266 | 1.9824 |
| swapTPforTC | 100 | 162937 | 298612 | 550434 | 0.0143 | 4.1260 | 0.0262 | 0.2417 | 0.1429 | 2.2384 |
| swapTCforTP | 100 | 501821 | 690972 | 976411 | 0.0440 | 7.3191 | 0.0605 | 0.5592 | 0.3307 | 5.1795 |
| redeemTCandTP | 100 | 331660 | 505607 | 825205 | 0.0291 | 6.1857 | 0.0443 | 0.4092 | 0.2420 | 3.7900 |
| mintTCandTP | 100 | 165209 | 308074 | 544249 | 0.0145 | 4.0797 | 0.0270 | 0.2493 | 0.1475 | 2.3093 |
| swapTPforTP | 100 | 176314 | 371304 | 871112 | 0.0154 | 6.5298 | 0.0325 | 0.3005 | 0.1777 | 2.7833 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 2; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 424662 | 459585 | 541243 | 0.0372 | 4.0571 | 0.0403 | 0.3719 | 0.2200 | 3.4450 |
| redeemTC | 100 | 883290 | 910437 | 935465 | 0.0774 | 7.0122 | 0.0798 | 0.7368 | 0.4358 | 6.8246 |
| mintTP | 100 | 909354 | 952607 | 994006 | 0.0797 | 7.4510 | 0.0835 | 0.7709 | 0.4560 | 7.1407 |
| redeemTP | 100 | 476293 | 499852 | 533875 | 0.0417 | 4.0019 | 0.0438 | 0.4045 | 0.2392 | 3.7469 |
| swapTPforTC | 100 | 529058 | 565766 | 584080 | 0.0464 | 4.3782 | 0.0496 | 0.4579 | 0.2708 | 4.2410 |
| swapTCforTP | 100 | 1064711 | 1094766 | 1138490 | 0.0933 | 8.5341 | 0.0959 | 0.8860 | 0.5240 | 8.2063 |
| redeemTCandTP | 100 | 862489 | 900962 | 923250 | 0.0756 | 6.9206 | 0.0789 | 0.7292 | 0.4312 | 6.7536 |
| mintTCandTP | 100 | 533585 | 563164 | 594751 | 0.0468 | 4.4582 | 0.0493 | 0.4558 | 0.2696 | 4.2214 |
| swapTPforTP | 100 | 478140 | 708994 | 1019356 | 0.0419 | 7.6410 | 0.0621 | 0.5738 | 0.3394 | 5.3146 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 2; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 123199 | 219025 | 467432 | 0.0108 | 3.5038 | 0.0192 | 0.1773 | 0.1048 | 1.6418 |
| redeemTC | 100 | 461811 | 610220 | 931147 | 0.0405 | 6.9798 | 0.0535 | 0.4939 | 0.2921 | 4.5742 |
| mintTP | 100 | 459485 | 610618 | 971485 | 0.0403 | 7.2822 | 0.0535 | 0.4942 | 0.2923 | 4.5772 |
| redeemTP | 100 | 155553 | 266294 | 510218 | 0.0136 | 3.8246 | 0.0233 | 0.2155 | 0.1275 | 1.9961 |
| swapTPforTC | 100 | 175546 | 297376 | 583711 | 0.0154 | 4.3755 | 0.0261 | 0.2407 | 0.1423 | 2.2291 |
| swapTCforTP | 100 | 606387 | 771172 | 1113653 | 0.0531 | 8.3479 | 0.0676 | 0.6241 | 0.3691 | 5.7807 |
| redeemTCandTP | 100 | 385278 | 538179 | 920354 | 0.0338 | 6.8989 | 0.0472 | 0.4355 | 0.2576 | 4.0342 |
| mintTCandTP | 100 | 184165 | 308690 | 577526 | 0.0161 | 4.3291 | 0.0270 | 0.2498 | 0.1478 | 2.3139 |
| swapTPforTP | 100 | 218454 | 403020 | 990563 | 0.0191 | 7.4252 | 0.0353 | 0.3262 | 0.1929 | 3.0210 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 2; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 460709 | 494799 | 573415 | 0.0404 | 4.2983 | 0.0434 | 0.4004 | 0.2368 | 3.7090 |
| redeemTC | 100 | 1005767 | 1036561 | 1064659 | 0.0881 | 7.9806 | 0.0908 | 0.8389 | 0.4961 | 7.7700 |
| mintTP | 100 | 1027148 | 1066012 | 1111400 | 0.0900 | 8.3310 | 0.0934 | 0.8627 | 0.5102 | 7.9908 |
| redeemTP | 100 | 506434 | 532533 | 567890 | 0.0444 | 4.2569 | 0.0467 | 0.4310 | 0.2549 | 3.9918 |
| swapTPforTC | 100 | 565105 | 598974 | 617726 | 0.0495 | 4.6304 | 0.0525 | 0.4848 | 0.2867 | 4.4899 |
| swapTCforTP | 100 | 1205245 | 1237301 | 1266041 | 0.1056 | 9.4902 | 0.1084 | 1.0014 | 0.5922 | 9.2747 |
| redeemTCandTP | 100 | 954371 | 996029 | 1020925 | 0.0836 | 7.6528 | 0.0873 | 0.8061 | 0.4767 | 7.4662 |
| mintTCandTP | 100 | 573215 | 596340 | 631535 | 0.0502 | 4.7340 | 0.0522 | 0.4826 | 0.2854 | 4.4701 |
| swapTPforTP | 100 | 507847 | 742000 | 1107694 | 0.0445 | 8.3032 | 0.0650 | 0.6005 | 0.3551 | 5.5620 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 2; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 133817 | 238234 | 512960 | 0.0117 | 3.8451 | 0.0209 | 0.1928 | 0.1140 | 1.7858 |
| redeemTC | 100 | 538123 | 713657 | 1053865 | 0.0471 | 7.8997 | 0.0625 | 0.5776 | 0.3416 | 5.3495 |
| mintTP | 100 | 527392 | 700034 | 1065101 | 0.0462 | 7.9839 | 0.0613 | 0.5665 | 0.3351 | 5.2474 |
| redeemTP | 100 | 169713 | 286858 | 547002 | 0.0149 | 4.1003 | 0.0251 | 0.2322 | 0.1373 | 2.1503 |
| swapTPforTC | 100 | 192633 | 318212 | 617726 | 0.0169 | 4.6304 | 0.0279 | 0.2575 | 0.1523 | 2.3853 |
| swapTCforTP | 100 | 703796 | 894002 | 1264055 | 0.0617 | 9.4753 | 0.0783 | 0.7235 | 0.4279 | 6.7014 |
| redeemTCandTP | 100 | 436082 | 608518 | 1019293 | 0.0382 | 7.6406 | 0.0533 | 0.4925 | 0.2913 | 4.5614 |
| mintTCandTP | 100 | 197689 | 328758 | 611910 | 0.0173 | 4.5868 | 0.0288 | 0.2661 | 0.1574 | 2.4644 |
| swapTPforTP | 100 | 243144 | 451190 | 1102691 | 0.0213 | 8.2657 | 0.0395 | 0.3651 | 0.2160 | 3.3821 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 3; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 578567 | 630930 | 729535 | 0.0507 | 5.4686 | 0.0553 | 0.5106 | 0.3020 | 4.7294 |
| redeemTC | 100 | 848128 | 887437 | 914869 | 0.0743 | 6.8578 | 0.0778 | 0.7182 | 0.4248 | 6.6522 |
| mintTP | 100 | 1350907 | 1400413 | 1454188 | 0.1184 | 10.9005 | 0.1227 | 1.1334 | 0.6703 | 10.4974 |
| redeemTP | 100 | 484433 | 521282 | 559236 | 0.0424 | 4.1920 | 0.0457 | 0.4219 | 0.2495 | 3.9075 |
| swapTPforTC | 100 | 775967 | 825987 | 845226 | 0.0680 | 6.3358 | 0.0724 | 0.6685 | 0.3953 | 6.1916 |
| swapTCforTP | 100 | 1032610 | 1073411 | 1103249 | 0.0905 | 8.2699 | 0.0940 | 0.8687 | 0.5138 | 8.0462 |
| redeemTCandTP | 100 | 1275960 | 1319606 | 1344480 | 0.1118 | 10.0782 | 0.1156 | 1.0680 | 0.6316 | 9.8917 |
| mintTCandTP | 100 | 548446 | 584539 | 623407 | 0.0481 | 4.6730 | 0.0512 | 0.4731 | 0.2798 | 4.3817 |
| swapTPforTP | 100 | 708584 | 1003634 | 1435154 | 0.0621 | 10.7578 | 0.0879 | 0.8122 | 0.4804 | 7.5232 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 3; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 150671 | 327766 | 1111935 | 0.0132 | 8.3350 | 0.0287 | 0.2653 | 0.1569 | 2.4569 |
| redeemTC | 100 | 595697 | 795135 | 976009 | 0.0522 | 7.3161 | 0.0697 | 0.6435 | 0.3806 | 5.9603 |
| mintTP | 100 | 485591 | 827485 | 1420754 | 0.0425 | 10.6499 | 0.0725 | 0.6697 | 0.3961 | 6.2028 |
| redeemTP | 100 | 212083 | 344134 | 538348 | 0.0186 | 4.0354 | 0.0302 | 0.2785 | 0.1647 | 2.5796 |
| swapTPforTC | 100 | 216383 | 415779 | 842458 | 0.0190 | 6.3150 | 0.0364 | 0.3365 | 0.1990 | 3.1167 |
| swapTCforTP | 100 | 734580 | 1013718 | 1170121 | 0.0644 | 8.7712 | 0.0888 | 0.8204 | 0.4852 | 7.5988 |
| redeemTCandTP | 100 | 453221 | 743940 | 1338899 | 0.0397 | 10.0363 | 0.0652 | 0.6021 | 0.3561 | 5.5765 |
| mintTCandTP | 100 | 248520 | 400555 | 602519 | 0.0218 | 4.5165 | 0.0351 | 0.3242 | 0.1917 | 3.0025 |
| swapTPforTP | 100 | 204027 | 573925 | 1437296 | 0.0179 | 10.7739 | 0.0503 | 0.4645 | 0.2747 | 4.3021 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 3; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 635695 | 687754 | 790171 | 0.0557 | 5.9231 | 0.0603 | 0.5566 | 0.3292 | 5.1554 |
| redeemTC | 100 | 1029954 | 1066778 | 1102930 | 0.0902 | 8.2675 | 0.0935 | 0.8633 | 0.5106 | 7.9965 |
| mintTP | 100 | 1610024 | 1659571 | 1693943 | 0.1411 | 12.6977 | 0.1454 | 1.3431 | 0.7943 | 12.4401 |
| redeemTP | 100 | 527136 | 564882 | 601572 | 0.0462 | 4.5094 | 0.0495 | 0.4572 | 0.2704 | 4.2343 |
| swapTPforTC | 100 | 827561 | 881223 | 915362 | 0.0725 | 6.8615 | 0.0772 | 0.7132 | 0.4218 | 6.6056 |
| swapTCforTP | 100 | 1235269 | 1278322 | 1309770 | 0.1082 | 9.8180 | 0.1120 | 1.0345 | 0.6119 | 9.5822 |
| redeemTCandTP | 100 | 1467815 | 1526614 | 1556059 | 0.1286 | 11.6641 | 0.1338 | 1.2355 | 0.7307 | 11.4434 |
| mintTCandTP | 100 | 591150 | 626699 | 662816 | 0.0518 | 4.9684 | 0.0549 | 0.5072 | 0.3000 | 4.6977 |
| swapTPforTP | 100 | 763687 | 1156242 | 1702762 | 0.0669 | 12.7638 | 0.1013 | 0.9358 | 0.5534 | 8.6671 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 3; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 162977 | 303193 | 1369276 | 0.0143 | 10.2640 | 0.0266 | 0.2454 | 0.1451 | 2.2727 |
| redeemTC | 100 | 742753 | 986474 | 1261881 | 0.0651 | 9.4590 | 0.0864 | 0.7984 | 0.4722 | 7.3946 |
| mintTP | 100 | 537606 | 921231 | 1670422 | 0.0471 | 12.5214 | 0.0807 | 0.7456 | 0.4409 | 6.9055 |
| redeemTP | 100 | 204989 | 355572 | 581789 | 0.0180 | 4.3611 | 0.0312 | 0.2878 | 0.1702 | 2.6653 |
| swapTPforTC | 100 | 231220 | 389105 | 889483 | 0.0203 | 6.6675 | 0.0341 | 0.3149 | 0.1862 | 2.9167 |
| swapTCforTP | 100 | 929976 | 1261131 | 1451182 | 0.0815 | 10.8780 | 0.1105 | 1.0206 | 0.6036 | 9.4534 |
| redeemTCandTP | 100 | 553147 | 792637 | 1531751 | 0.0485 | 11.4819 | 0.0694 | 0.6415 | 0.3794 | 5.9416 |
| mintTCandTP | 100 | 240820 | 408197 | 636689 | 0.0211 | 4.7726 | 0.0358 | 0.3304 | 0.1954 | 3.0598 |
| swapTPforTP | 100 | 289853 | 571942 | 1292382 | 0.0254 | 9.6876 | 0.0501 | 0.4629 | 0.2738 | 4.2872 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 3; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 696700 | 746605 | 846932 | 0.0610 | 6.3486 | 0.0654 | 0.6042 | 0.3574 | 5.5965 |
| redeemTC | 100 | 1209382 | 1252231 | 1282358 | 0.1060 | 9.6125 | 0.1097 | 1.0134 | 0.5994 | 9.3867 |
| mintTP | 100 | 1868044 | 1925048 | 1976220 | 0.1637 | 14.8136 | 0.1687 | 1.5579 | 0.9214 | 14.4301 |
| redeemTP | 100 | 572609 | 606489 | 644645 | 0.0502 | 4.8322 | 0.0531 | 0.4908 | 0.2903 | 4.5462 |
| swapTPforTC | 100 | 890963 | 939493 | 980742 | 0.0781 | 7.3516 | 0.0823 | 0.7603 | 0.4497 | 7.0424 |
| swapTCforTP | 100 | 1440269 | 1484427 | 1515880 | 0.1262 | 11.3630 | 0.1301 | 1.2014 | 0.7105 | 11.1272 |
| redeemTCandTP | 100 | 1681114 | 1731699 | 1756429 | 0.1473 | 13.1661 | 0.1517 | 1.4015 | 0.8289 | 12.9807 |
| mintTCandTP | 100 | 637517 | 671830 | 708656 | 0.0559 | 5.3120 | 0.0589 | 0.5437 | 0.3216 | 5.0360 |
| swapTPforTP | 100 | 782159 | 1272399 | 1973521 | 0.0685 | 14.7934 | 0.1115 | 1.0298 | 0.6090 | 9.5378 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 3; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 177008 | 426728 | 4428821 | 0.0155 | 33.1982 | 0.0374 | 0.3454 | 0.2042 | 3.1987 |
| redeemTC | 100 | 875562 | 1189667 | 1427501 | 0.0767 | 10.7005 | 0.1042 | 0.9628 | 0.5694 | 8.9177 |
| mintTP | 100 | 645713 | 1164215 | 1940162 | 0.0566 | 14.5434 | 0.1020 | 0.9422 | 0.5572 | 8.7269 |
| redeemTP | 100 | 219757 | 408317 | 624493 | 0.0193 | 4.6812 | 0.0358 | 0.3305 | 0.1954 | 3.0607 |
| swapTPforTC | 100 | 251313 | 478618 | 960590 | 0.0220 | 7.2005 | 0.0419 | 0.3873 | 0.2291 | 3.5877 |
| swapTCforTP | 100 | 1114354 | 1497121 | 1734124 | 0.0976 | 12.9989 | 0.1312 | 1.2116 | 0.7166 | 11.2223 |
| redeemTCandTP | 100 | 642442 | 995261 | 1754609 | 0.0563 | 13.1525 | 0.0872 | 0.8055 | 0.4764 | 7.4604 |
| mintTCandTP | 100 | 257427 | 469553 | 688505 | 0.0226 | 5.1610 | 0.0411 | 0.3800 | 0.2247 | 3.5197 |
| swapTPforTP | 100 | 281097 | 706554 | 1973593 | 0.0246 | 14.7940 | 0.0619 | 0.5718 | 0.3382 | 5.2963 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 3; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 753829 | 805468 | 901662 | 0.0660 | 6.7588 | 0.0706 | 0.6519 | 0.3855 | 6.0377 |
| redeemTC | 100 | 1388809 | 1432972 | 1468261 | 0.1217 | 11.0060 | 0.1255 | 1.1597 | 0.6859 | 10.7415 |
| mintTP | 100 | 2144203 | 2185917 | 2226528 | 0.1879 | 16.6899 | 0.1915 | 1.7691 | 1.0463 | 16.3855 |
| redeemTP | 100 | 609698 | 646210 | 688086 | 0.0534 | 5.1579 | 0.0566 | 0.5230 | 0.3093 | 4.8440 |
| swapTPforTC | 100 | 947725 | 996279 | 1018458 | 0.0830 | 7.6343 | 0.0873 | 0.8063 | 0.4769 | 7.4681 |
| swapTCforTP | 100 | 1643875 | 1691003 | 1723194 | 0.1440 | 12.9170 | 0.1482 | 1.3685 | 0.8094 | 12.6757 |
| redeemTCandTP | 100 | 1882325 | 1928060 | 1962608 | 0.1649 | 14.7116 | 0.1689 | 1.5604 | 0.9228 | 14.4526 |
| mintTCandTP | 100 | 679326 | 713080 | 771881 | 0.0595 | 5.7860 | 0.0625 | 0.5771 | 0.3413 | 5.3452 |
| swapTPforTP | 100 | 826291 | 1416368 | 2264974 | 0.0724 | 16.9781 | 0.1241 | 1.1463 | 0.6779 | 10.6170 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 3; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 182510 | 373300 | 2317457 | 0.0160 | 17.3715 | 0.0327 | 0.3021 | 0.1787 | 2.7982 |
| redeemTC | 100 | 1068250 | 1371801 | 1810813 | 0.0936 | 13.5738 | 0.1202 | 1.1102 | 0.6566 | 10.2830 |
| mintTP | 100 | 966301 | 1235886 | 2186509 | 0.0847 | 16.3900 | 0.1083 | 1.0002 | 0.5915 | 9.2641 |
| redeemTP | 100 | 271436 | 404579 | 666829 | 0.0238 | 4.9985 | 0.0354 | 0.3274 | 0.1936 | 3.0327 |
| swapTPforTC | 100 | 266576 | 437673 | 1012736 | 0.0234 | 7.5914 | 0.0383 | 0.3542 | 0.2095 | 3.2808 |
| swapTCforTP | 100 | 1296203 | 1724370 | 1995813 | 0.1136 | 14.9605 | 0.1511 | 1.3955 | 0.8253 | 12.9258 |
| redeemTCandTP | 100 | 723331 | 1017806 | 1954709 | 0.0634 | 14.6524 | 0.0892 | 0.8237 | 0.4872 | 7.6294 |
| mintTCandTP | 100 | 312732 | 465637 | 730472 | 0.0274 | 5.4756 | 0.0408 | 0.3768 | 0.2229 | 3.4904 |
| swapTPforTP | 100 | 290798 | 727198 | 1656820 | 0.0255 | 12.4194 | 0.0637 | 0.5885 | 0.3481 | 5.4510 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 4; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 812506 | 879010 | 996860 | 0.0712 | 7.4724 | 0.0770 | 0.7114 | 0.4207 | 6.5890 |
| redeemTC | 100 | 1052308 | 1093317 | 1123608 | 0.0922 | 8.4225 | 0.0958 | 0.8848 | 0.5233 | 8.1954 |
| mintTP | 100 | 2198165 | 2274800 | 2319649 | 0.1926 | 17.3880 | 0.1993 | 1.8410 | 1.0888 | 17.0518 |
| redeemTP | 100 | 547601 | 585843 | 623219 | 0.0480 | 4.6716 | 0.0513 | 0.4741 | 0.2804 | 4.3914 |
| swapTPforTC | 100 | 1086068 | 1158958 | 1178900 | 0.0952 | 8.8370 | 0.1015 | 0.9379 | 0.5547 | 8.6875 |
| swapTCforTP | 100 | 1269542 | 1317066 | 1346848 | 0.1112 | 10.0959 | 0.1154 | 1.0659 | 0.6304 | 9.8727 |
| redeemTCandTP | 100 | 2000323 | 2068892 | 2094430 | 0.1753 | 15.6997 | 0.1813 | 1.6744 | 0.9902 | 15.5083 |
| mintTCandTP | 100 | 615565 | 651171 | 687232 | 0.0539 | 5.1515 | 0.0571 | 0.5270 | 0.3117 | 4.8811 |
| swapTPforTP | 100 | 1017170 | 1524221 | 2308196 | 0.0891 | 17.3021 | 0.1335 | 1.2336 | 0.7295 | 11.4255 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 4; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 174036 | 813553 | 5777465 | 0.0152 | 43.3076 | 0.0713 | 0.6584 | 0.3894 | 6.0984 |
| redeemTC | 100 | 720385 | 1333106 | 4875664 | 0.0631 | 36.5477 | 0.1168 | 1.0789 | 0.6381 | 9.9929 |
| mintTP | 100 | 690244 | 1469780 | 7370891 | 0.0605 | 55.2518 | 0.1288 | 1.1895 | 0.7035 | 11.0174 |
| redeemTP | 100 | 176251 | 600740 | 4855518 | 0.0154 | 36.3967 | 0.0526 | 0.4862 | 0.2875 | 4.5031 |
| swapTPforTC | 100 | 242400 | 693790 | 5007532 | 0.0212 | 37.5362 | 0.0608 | 0.5615 | 0.3321 | 5.2006 |
| swapTCforTP | 100 | 942956 | 1532303 | 3665980 | 0.0826 | 27.4800 | 0.1343 | 1.2401 | 0.7334 | 11.4861 |
| redeemTCandTP | 100 | 537491 | 1133233 | 2089789 | 0.0471 | 15.6650 | 0.0993 | 0.9171 | 0.5424 | 8.4947 |
| mintTCandTP | 100 | 207472 | 499264 | 1555155 | 0.0182 | 11.6574 | 0.0437 | 0.4041 | 0.2390 | 3.7425 |
| swapTPforTP | 100 | 281525 | 785318 | 1920050 | 0.0247 | 14.3926 | 0.0688 | 0.6356 | 0.3759 | 5.8867 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 4; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 891454 | 960443 | 1080244 | 0.0781 | 8.0975 | 0.0841 | 0.7773 | 0.4597 | 7.1994 |
| redeemTC | 100 | 1290840 | 1333125 | 1361898 | 0.1131 | 10.2087 | 0.1168 | 1.0789 | 0.6381 | 9.9930 |
| mintTP | 100 | 2682601 | 2743010 | 2782238 | 0.2350 | 20.8555 | 0.2403 | 2.2199 | 1.3129 | 20.5615 |
| redeemTP | 100 | 599730 | 636612 | 678486 | 0.0525 | 5.0859 | 0.0558 | 0.5152 | 0.3047 | 4.7720 |
| swapTPforTC | 100 | 1176094 | 1242188 | 1260989 | 0.1030 | 9.4523 | 0.1088 | 1.0053 | 0.5946 | 9.3114 |
| swapTCforTP | 100 | 1533852 | 1585928 | 1621024 | 0.1344 | 12.1511 | 0.1390 | 1.2835 | 0.7591 | 11.8880 |
| redeemTCandTP | 100 | 2353866 | 2426129 | 2462438 | 0.2062 | 18.4583 | 0.2126 | 1.9635 | 1.1612 | 18.1861 |
| mintTCandTP | 100 | 667696 | 699844 | 743026 | 0.0585 | 5.5697 | 0.0613 | 0.5664 | 0.3350 | 5.2460 |
| swapTPforTP | 100 | 1068294 | 1734379 | 2766037 | 0.0936 | 20.7341 | 0.1520 | 1.4036 | 0.8301 | 13.0008 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 4; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 188046 | 765031 | 5148590 | 0.0165 | 38.5936 | 0.0670 | 0.6191 | 0.3662 | 5.7346 |
| redeemTC | 100 | 919451 | 1610278 | 7502404 | 0.0806 | 56.2376 | 0.1411 | 1.3032 | 0.7707 | 12.0706 |
| mintTP | 100 | 672096 | 1643750 | 6176678 | 0.0589 | 46.3001 | 0.1440 | 1.3303 | 0.7868 | 12.3215 |
| redeemTP | 100 | 193466 | 523395 | 4950532 | 0.0170 | 37.1089 | 0.0459 | 0.4236 | 0.2505 | 3.9233 |
| swapTPforTC | 100 | 261565 | 755548 | 2559521 | 0.0229 | 19.1860 | 0.0662 | 0.6115 | 0.3616 | 5.6636 |
| swapTCforTP | 100 | 1199370 | 1878950 | 2856870 | 0.1051 | 21.4150 | 0.1646 | 1.5206 | 0.8993 | 14.0845 |
| redeemTCandTP | 100 | 576805 | 1372171 | 2508303 | 0.0505 | 18.8021 | 0.1202 | 1.1105 | 0.6568 | 10.2857 |
| mintTCandTP | 100 | 221954 | 539091 | 1554434 | 0.0194 | 11.6520 | 0.0472 | 0.4363 | 0.2580 | 4.0410 |
| swapTPforTP | 100 | 428076 | 988820 | 2267152 | 0.0375 | 16.9945 | 0.0866 | 0.8003 | 0.4733 | 7.4121 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 4; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 975205 | 1043028 | 1159194 | 0.0854 | 8.6893 | 0.0914 | 0.8441 | 0.4992 | 7.8185 |
| redeemTC | 100 | 1531537 | 1574586 | 1604197 | 0.1342 | 12.0250 | 0.1380 | 1.2743 | 0.7537 | 11.8030 |
| mintTP | 100 | 3146712 | 3206256 | 3256980 | 0.2757 | 24.4142 | 0.2809 | 2.5948 | 1.5346 | 24.0339 |
| redeemTP | 100 | 652597 | 694790 | 730248 | 0.0572 | 5.4739 | 0.0609 | 0.5623 | 0.3326 | 5.2081 |
| swapTPforTC | 100 | 1258547 | 1323258 | 1362488 | 0.1103 | 10.2131 | 0.1159 | 1.0709 | 0.6334 | 9.9191 |
| swapTCforTP | 100 | 1807538 | 1856538 | 1887994 | 0.1584 | 14.1523 | 0.1627 | 1.5025 | 0.8886 | 13.9165 |
| redeemTCandTP | 100 | 2720972 | 2782254 | 2810150 | 0.2384 | 21.0647 | 0.2438 | 2.2517 | 1.3317 | 20.8556 |
| mintTCandTP | 100 | 719825 | 755702 | 794786 | 0.0631 | 5.9577 | 0.0662 | 0.6116 | 0.3617 | 5.6647 |
| swapTPforTP | 100 | 1111782 | 1963827 | 3265877 | 0.0974 | 24.4809 | 0.1721 | 1.5893 | 0.9400 | 14.7207 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 4; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 201959 | 1073126 | 8722398 | 0.0177 | 65.3827 | 0.0940 | 0.8685 | 0.5136 | 8.0441 |
| redeemTC | 100 | 1145990 | 2048841 | 7159288 | 0.1004 | 53.6657 | 0.1795 | 1.6581 | 0.9807 | 15.3580 |
| mintTP | 100 | 1157738 | 2178006 | 9989606 | 0.1014 | 74.8816 | 0.1908 | 1.7627 | 1.0425 | 16.3262 |
| redeemTP | 100 | 208775 | 723015 | 6167552 | 0.0183 | 46.2317 | 0.0633 | 0.5851 | 0.3461 | 5.4197 |
| swapTPforTC | 100 | 279061 | 774878 | 4361228 | 0.0244 | 32.6915 | 0.0679 | 0.6271 | 0.3709 | 5.8084 |
| swapTCforTP | 100 | 1452963 | 2252551 | 2885160 | 0.1273 | 21.6270 | 0.1974 | 1.8230 | 1.0782 | 16.8850 |
| redeemTCandTP | 100 | 776760 | 1593442 | 2807195 | 0.0681 | 21.0426 | 0.1396 | 1.2896 | 0.7627 | 11.9444 |
| mintTCandTP | 100 | 243592 | 572347 | 970006 | 0.0213 | 7.2711 | 0.0501 | 0.4632 | 0.2739 | 4.2903 |
| swapTPforTP | 100 | 356455 | 1056885 | 2608771 | 0.0312 | 19.5552 | 0.0926 | 0.8553 | 0.5059 | 7.9224 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 4; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1056924 | 1126755 | 1243680 | 0.0926 | 9.3226 | 0.0987 | 0.9119 | 0.5393 | 8.4461 |
| redeemTC | 100 | 1774390 | 1810566 | 1838489 | 0.1555 | 13.7812 | 0.1586 | 1.4653 | 0.8666 | 13.5719 |
| mintTP | 100 | 3622874 | 3669395 | 3709942 | 0.3174 | 27.8095 | 0.3215 | 2.9697 | 1.7563 | 27.5056 |
| redeemTP | 100 | 707942 | 744626 | 782747 | 0.0620 | 5.8674 | 0.0652 | 0.6026 | 0.3564 | 5.5817 |
| swapTPforTC | 100 | 1338425 | 1405194 | 1437737 | 0.1173 | 10.7772 | 0.1231 | 1.1372 | 0.6726 | 10.5333 |
| swapTCforTP | 100 | 2082854 | 2120508 | 2154802 | 0.1825 | 16.1523 | 0.1858 | 1.7161 | 1.0150 | 15.8952 |
| redeemTCandTP | 100 | 3069805 | 3138326 | 3174412 | 0.2690 | 23.7952 | 0.2750 | 2.5399 | 1.5021 | 23.5247 |
| mintTCandTP | 100 | 774724 | 806935 | 847285 | 0.0679 | 6.3512 | 0.0707 | 0.6531 | 0.3862 | 6.0487 |
| swapTPforTP | 100 | 1169638 | 2174896 | 3770892 | 0.1025 | 28.2664 | 0.1906 | 1.7601 | 1.0410 | 16.3029 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 4; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 208751 | 1150888 | 6505883 | 0.0183 | 48.7678 | 0.1008 | 0.9314 | 0.5509 | 8.6270 |
| redeemTC | 100 | 1337170 | 2304356 | 9132664 | 0.1172 | 68.4580 | 0.2019 | 1.8649 | 1.1030 | 17.2733 |
| mintTP | 100 | 999641 | 2345357 | 9674113 | 0.0876 | 72.5167 | 0.2055 | 1.8981 | 1.1226 | 17.5807 |
| redeemTP | 100 | 224949 | 775470 | 9959180 | 0.0197 | 74.6535 | 0.0679 | 0.6276 | 0.3712 | 5.8129 |
| swapTPforTC | 100 | 296619 | 961181 | 9400811 | 0.0260 | 70.4680 | 0.0842 | 0.7779 | 0.4601 | 7.2050 |
| swapTCforTP | 100 | 1699271 | 2671406 | 7994575 | 0.1489 | 59.9269 | 0.2341 | 2.1620 | 1.2786 | 20.0247 |
| redeemTCandTP | 100 | 759413 | 1859591 | 8299007 | 0.0665 | 62.2089 | 0.1629 | 1.5050 | 0.8901 | 13.9394 |
| mintTCandTP | 100 | 260384 | 680605 | 7686863 | 0.0228 | 57.6203 | 0.0596 | 0.5508 | 0.3258 | 5.1018 |
| swapTPforTP | 100 | 388697 | 1273529 | 7923097 | 0.0341 | 59.3911 | 0.1116 | 1.0307 | 0.6096 | 9.5463 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 5; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1040909 | 1124432 | 1266587 | 0.0912 | 9.4943 | 0.0985 | 0.9100 | 0.5382 | 8.4287 |
| redeemTC | 100 | 1265606 | 1304620 | 1336666 | 0.1109 | 10.0196 | 0.1143 | 1.0558 | 0.6244 | 9.7794 |
| mintTP | 100 | 3270560 | 3346418 | 3393145 | 0.2866 | 25.4348 | 0.2932 | 2.7083 | 1.6017 | 25.0846 |
| redeemTP | 100 | 618673 | 654228 | 690340 | 0.0542 | 5.1748 | 0.0573 | 0.5295 | 0.3131 | 4.9041 |
| swapTPforTC | 100 | 1407245 | 1492597 | 1524421 | 0.1233 | 11.4270 | 0.1308 | 1.2080 | 0.7144 | 11.1884 |
| swapTCforTP | 100 | 1516199 | 1559828 | 1594609 | 0.1328 | 11.9531 | 0.1367 | 1.2624 | 0.7466 | 11.6924 |
| redeemTCandTP | 100 | 2850126 | 2946383 | 2991055 | 0.2497 | 22.4208 | 0.2581 | 2.3845 | 1.4102 | 22.0859 |
| mintTCandTP | 100 | 682686 | 719484 | 757279 | 0.0598 | 5.6765 | 0.0630 | 0.5823 | 0.3444 | 5.3932 |
| swapTPforTP | 100 | 1313222 | 2176151 | 3384474 | 0.1151 | 25.3698 | 0.1907 | 1.7612 | 1.0416 | 16.3123 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 5; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 193814 | 1356575 | 6833081 | 0.0170 | 51.2204 | 0.1189 | 1.0979 | 0.6493 | 10.1688 |
| redeemTC | 100 | 861672 | 1977225 | 6346471 | 0.0755 | 47.5728 | 0.1732 | 1.6002 | 0.9464 | 14.8212 |
| mintTP | 100 | 907942 | 2261520 | 7991815 | 0.0795 | 59.9062 | 0.1981 | 1.8303 | 1.0824 | 16.9522 |
| redeemTP | 100 | 179360 | 1003089 | 6039948 | 0.0157 | 45.2751 | 0.0879 | 0.8118 | 0.4801 | 7.5191 |
| swapTPforTC | 100 | 210890 | 1096087 | 6474631 | 0.0185 | 48.5335 | 0.0960 | 0.8871 | 0.5246 | 8.2162 |
| swapTCforTP | 100 | 1118750 | 2248002 | 6304960 | 0.0980 | 47.2617 | 0.1970 | 1.8193 | 1.0760 | 16.8509 |
| redeemTCandTP | 100 | 839880 | 1872127 | 7007807 | 0.0736 | 52.5302 | 0.1640 | 1.5151 | 0.8961 | 14.0334 |
| mintTCandTP | 100 | 209812 | 887167 | 5753070 | 0.0184 | 43.1247 | 0.0777 | 0.7180 | 0.4246 | 6.6502 |
| swapTPforTP | 100 | 232433 | 1299987 | 7047383 | 0.0204 | 52.8268 | 0.1139 | 1.0521 | 0.6222 | 9.7446 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 5; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1146845 | 1231217 | 1372896 | 0.1005 | 10.2912 | 0.1079 | 0.9964 | 0.5893 | 9.2291 |
| redeemTC | 100 | 1542221 | 1597876 | 1627348 | 0.1351 | 12.1985 | 0.1400 | 1.2932 | 0.7648 | 11.9776 |
| mintTP | 100 | 3987316 | 4072441 | 4137166 | 0.3493 | 31.0120 | 0.3568 | 3.2958 | 1.9492 | 30.5268 |
| redeemTP | 100 | 680228 | 716247 | 754664 | 0.0596 | 5.6569 | 0.0628 | 0.5797 | 0.3428 | 5.3690 |
| swapTPforTC | 100 | 1518354 | 1597670 | 1620110 | 0.1330 | 12.1443 | 0.1400 | 1.2930 | 0.7647 | 11.9761 |
| swapTCforTP | 100 | 1846720 | 1891531 | 1923224 | 0.1618 | 14.4164 | 0.1657 | 1.5308 | 0.9054 | 14.1788 |
| redeemTCandTP | 100 | 3411355 | 3502953 | 3533405 | 0.2989 | 26.4862 | 0.3069 | 2.8350 | 1.6766 | 26.2580 |
| mintTCandTP | 100 | 747011 | 780969 | 818677 | 0.0654 | 6.1368 | 0.0684 | 0.6320 | 0.3738 | 5.8541 |
| swapTPforTP | 100 | 1361951 | 2413695 | 4198703 | 0.1193 | 31.4733 | 0.2115 | 1.9534 | 1.1553 | 18.0929 |

ETH Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 5; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 208000 | 1444911 | 7469666 | 0.0182 | 55.9922 | 0.1266 | 1.1694 | 0.6916 | 10.8310 |
| redeemTC | 100 | 1122736 | 2591561 | 8377537 | 0.0984 | 62.7976 | 0.2271 | 2.0974 | 1.2404 | 19.4262 |
| mintTP | 100 | 1136718 | 2801098 | 10679947 | 0.0996 | 80.0563 | 0.2454 | 2.2669 | 1.3407 | 20.9969 |
| redeemTP | 100 | 194768 | 1394907 | 8907199 | 0.0171 | 66.7679 | 0.1222 | 1.1289 | 0.6677 | 10.4562 |
| swapTPforTC | 100 | 230464 | 1328038 | 6601907 | 0.0202 | 49.4876 | 0.1164 | 1.0748 | 0.6356 | 9.9549 |
| swapTCforTP | 100 | 1434231 | 2867959 | 7922303 | 0.1257 | 59.3852 | 0.2513 | 2.3210 | 1.3727 | 21.4981 |
| redeemTCandTP | 100 | 894262 | 2217650 | 8872448 | 0.0784 | 66.5074 | 0.1943 | 1.7948 | 1.0615 | 16.6234 |
| mintTCandTP | 100 | 226167 | 1025104 | 8156094 | 0.0198 | 61.1377 | 0.0898 | 0.8296 | 0.4907 | 7.6841 |
| swapTPforTP | 100 | 317891 | 1444271 | 7554792 | 0.0279 | 56.6303 | 0.1265 | 1.1689 | 0.6913 | 10.8262 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 5; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1255186 | 1337226 | 1474225 | 0.1100 | 11.0507 | 0.1172 | 1.0822 | 0.6400 | 10.0238 |
| redeemTC | 100 | 1851538 | 1891829 | 1928832 | 0.1622 | 14.4584 | 0.1658 | 1.5311 | 0.9055 | 14.1811 |
| mintTP | 100 | 4748537 | 4802281 | 4851748 | 0.4160 | 36.3685 | 0.4208 | 3.8865 | 2.2986 | 35.9977 |
| redeemTP | 100 | 744553 | 774539 | 816589 | 0.0652 | 6.1211 | 0.0679 | 0.6268 | 0.3707 | 5.8059 |
| swapTPforTC | 100 | 1624290 | 1705839 | 1770865 | 0.1423 | 13.2743 | 0.1495 | 1.3805 | 0.8165 | 12.7869 |
| swapTCforTP | 100 | 2172448 | 2222140 | 2264695 | 0.1903 | 16.9760 | 0.1947 | 1.7984 | 1.0636 | 16.6571 |
| redeemTCandTP | 100 | 3958948 | 4054817 | 4092742 | 0.3469 | 30.6790 | 0.3553 | 3.2816 | 1.9408 | 30.3947 |
| mintTCandTP | 100 | 805798 | 841663 | 881128 | 0.0706 | 6.6049 | 0.0737 | 0.6812 | 0.4029 | 6.3091 |
| swapTPforTP | 100 | 1441156 | 2779946 | 4984459 | 0.1263 | 37.3633 | 0.2436 | 2.2498 | 1.3306 | 20.8383 |

ETH Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 5; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.027gw | $ avgGas @ 0.2494gw | $ avgGas @ 0.1475gw | $ avgGas @ 2.31gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1360388 | 1442667 | 1580162 | 0.1192 | 11.8448 | 0.1264 | 1.1676 | 0.6905 | 10.8142 |
| redeemTC | 100 | 2146784 | 2186994 | 2221678 | 0.1881 | 16.6536 | 0.1916 | 1.7699 | 1.0468 | 16.3936 |
| mintTP | 100 | 5458506 | 5524714 | 5586680 | 0.4782 | 41.8775 | 0.4840 | 4.4712 | 2.6443 | 41.4130 |
| redeemTP | 100 | 806478 | 840611 | 878146 | 0.0707 | 6.5825 | 0.0737 | 0.6803 | 0.4023 | 6.3012 |
| swapTPforTC | 100 | 1729126 | 1811549 | 1869960 | 0.1515 | 14.0171 | 0.1587 | 1.4661 | 0.8671 | 13.5793 |
| swapTCforTP | 100 | 2508756 | 2552051 | 2599478 | 0.2198 | 19.4856 | 0.2236 | 2.0654 | 1.2215 | 19.1300 |
| redeemTCandTP | 100 | 4537040 | 4605672 | 4650403 | 0.3975 | 34.8592 | 0.4035 | 3.7274 | 2.2044 | 34.5239 |
| mintTCandTP | 100 | 867354 | 901942 | 943052 | 0.0760 | 7.0691 | 0.0790 | 0.7299 | 0.4317 | 6.7609 |
| swapTPforTP | 100 | 1491683 | 3128161 | 5535161 | 0.1307 | 41.4913 | 0.2741 | 2.5316 | 1.4973 | 23.4485 |

ARB Queueing; Price: $3245; Gas adjustment: 1.2
| (index) | blockGasLimit | estimatedGas | gasLeftPct | min fee @ 0.01gw | $ min | avg fee @ 0.029gw | $ avg | median fee @ 0.019gw | $ median | max fee @ 1.0gw | $ max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 32000000 | 280278 | 99.12% | 2802780000000 | 0.0091 | 8128062000000 | 0.0264 | 5325282000000 | 0.0173 | 280278000000000 | 0.9095 |
| redeemTC | 32000000 | 257028 | 99.20% | 2570280000000 | 0.0083 | 7453812000000 | 0.0242 | 4883532000000 | 0.0158 | 257028000000000 | 0.8341 |
| mintTP | 32000000 | 287759 | 99.10% | 2877590000000 | 0.0093 | 8345011000000 | 0.0271 | 5467421000000 | 0.0177 | 287759000000000 | 0.9338 |
| redeemTP | 32000000 | 279650 | 99.13% | 2796500000000 | 0.0091 | 8109850000000 | 0.0263 | 5313350000000 | 0.0172 | 279650000000000 | 0.9075 |
| swapTPforTP | 32000000 | 342821 | 98.93% | 3428210000000 | 0.0111 | 9941809000000 | 0.0323 | 6513599000000 | 0.0211 | 342821000000000 | 1.1125 |
| swapTPforTC | 32000000 | 315461 | 99.01% | 3154610000000 | 0.0102 | 9148369000000 | 0.0297 | 5993759000000 | 0.0194 | 315461000000000 | 1.0237 |
| swapTCforTP | 32000000 | 320234 | 99.00% | 3202340000000 | 0.0104 | 9286786000000 | 0.0301 | 6084446000000 | 0.0197 | 320234000000000 | 1.0392 |
| redeemTCandTP | 32000000 | 317005 | 99.01% | 3170050000000 | 0.0103 | 9193145000000 | 0.0298 | 6023095000000 | 0.0195 | 317005000000000 | 1.0287 |
| mintTCandTP | 32000000 | 288104 | 99.10% | 2881040000000 | 0.0093 | 8355016000000 | 0.0271 | 5473976000000 | 0.0178 | 288104000000000 | 0.9349 |
| execSettlement | 32000000 | 170743 | 99.47% | 1707430000000 | 0.0055 | 4951547000000 | 0.0161 | 3244117000000 | 0.0105 | 170743000000000 | 0.5541 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 2; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 358106 | 392083 | 473581 | 0.0116 | 1.5368 | 0.0127 | 0.0369 | 0.0242 | 1.2723 |
| redeemTC | 100 | 633292 | 657801 | 681390 | 0.0206 | 2.2111 | 0.0213 | 0.0619 | 0.0406 | 2.1346 |
| mintTP | 100 | 685145 | 724906 | 762107 | 0.0222 | 2.4730 | 0.0235 | 0.0682 | 0.0447 | 2.3523 |
| redeemTP | 100 | 406601 | 429279 | 464183 | 0.0132 | 1.5063 | 0.0139 | 0.0404 | 0.0265 | 1.3930 |
| swapTPforTC | 100 | 462503 | 495918 | 516787 | 0.0150 | 1.6770 | 0.0161 | 0.0467 | 0.0306 | 1.6093 |
| swapTCforTP | 100 | 785018 | 811076 | 836119 | 0.0255 | 2.7132 | 0.0263 | 0.0763 | 0.0500 | 2.6319 |
| redeemTCandTP | 100 | 673457 | 709883 | 731689 | 0.0219 | 2.3743 | 0.0230 | 0.0668 | 0.0438 | 2.3036 |
| mintTCandTP | 100 | 470612 | 496271 | 528196 | 0.0153 | 1.7140 | 0.0161 | 0.0467 | 0.0306 | 1.6104 |
| swapTPforTP | 100 | 431848 | 568923 | 757194 | 0.0140 | 2.4571 | 0.0185 | 0.0535 | 0.0351 | 1.8462 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 2; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 106231 | 192928 | 412021 | 0.0034 | 1.3370 | 0.0063 | 0.0182 | 0.0119 | 0.6261 |
| redeemTC | 100 | 314552 | 432519 | 679231 | 0.0102 | 2.2041 | 0.0140 | 0.0407 | 0.0267 | 1.4035 |
| mintTP | 100 | 316982 | 450941 | 744958 | 0.0103 | 2.4174 | 0.0146 | 0.0424 | 0.0278 | 1.4633 |
| redeemTP | 100 | 131174 | 231467 | 446431 | 0.0043 | 1.4487 | 0.0075 | 0.0218 | 0.0143 | 0.7511 |
| swapTPforTC | 100 | 149524 | 264285 | 516787 | 0.0049 | 1.6770 | 0.0086 | 0.0249 | 0.0163 | 0.8576 |
| swapTCforTP | 100 | 406396 | 555548 | 830906 | 0.0132 | 2.6963 | 0.0180 | 0.0523 | 0.0343 | 1.8028 |
| redeemTCandTP | 100 | 279645 | 419899 | 728794 | 0.0091 | 2.3649 | 0.0136 | 0.0395 | 0.0259 | 1.3626 |
| mintTCandTP | 100 | 151420 | 271405 | 510444 | 0.0049 | 1.6564 | 0.0088 | 0.0255 | 0.0167 | 0.8807 |
| swapTPforTP | 100 | 156654 | 318500 | 748818 | 0.0051 | 2.4299 | 0.0103 | 0.0300 | 0.0196 | 1.0335 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 2; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 391384 | 428275 | 506860 | 0.0127 | 1.6448 | 0.0139 | 0.0403 | 0.0264 | 1.3898 |
| redeemTC | 100 | 753852 | 787048 | 808426 | 0.0245 | 2.6233 | 0.0255 | 0.0741 | 0.0485 | 2.5540 |
| mintTP | 100 | 798222 | 840588 | 885032 | 0.0259 | 2.8719 | 0.0273 | 0.0791 | 0.0518 | 2.7277 |
| redeemTP | 100 | 442646 | 463910 | 500966 | 0.0144 | 1.6256 | 0.0151 | 0.0437 | 0.0286 | 1.5054 |
| swapTPforTC | 100 | 498550 | 531651 | 550434 | 0.0162 | 1.7862 | 0.0173 | 0.0500 | 0.0328 | 1.7252 |
| swapTCforTP | 100 | 920099 | 952644 | 981624 | 0.0299 | 3.1854 | 0.0309 | 0.0896 | 0.0587 | 3.0913 |
| redeemTCandTP | 100 | 768235 | 805455 | 826837 | 0.0249 | 2.6831 | 0.0261 | 0.0758 | 0.0497 | 2.6137 |
| mintTCandTP | 100 | 503891 | 526509 | 565138 | 0.0164 | 1.8339 | 0.0171 | 0.0495 | 0.0325 | 1.7085 |
| swapTPforTP | 100 | 454835 | 613184 | 874325 | 0.0148 | 2.8372 | 0.0199 | 0.0577 | 0.0378 | 1.9898 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 2; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 115406 | 229369 | 445668 | 0.0037 | 1.4462 | 0.0074 | 0.0216 | 0.0141 | 0.7443 |
| redeemTC | 100 | 388001 | 553681 | 801949 | 0.0126 | 2.6023 | 0.0180 | 0.0521 | 0.0341 | 1.7967 |
| mintTP | 100 | 382406 | 566509 | 862195 | 0.0124 | 2.7978 | 0.0184 | 0.0533 | 0.0349 | 1.8383 |
| redeemTP | 100 | 143308 | 272636 | 480078 | 0.0047 | 1.5579 | 0.0088 | 0.0257 | 0.0168 | 0.8847 |
| swapTPforTC | 100 | 162682 | 308988 | 550434 | 0.0053 | 1.7862 | 0.0100 | 0.0291 | 0.0191 | 1.0027 |
| swapTCforTP | 100 | 506669 | 702335 | 981624 | 0.0164 | 3.1854 | 0.0228 | 0.0661 | 0.0433 | 2.2791 |
| redeemTCandTP | 100 | 332156 | 518307 | 824678 | 0.0108 | 2.6761 | 0.0168 | 0.0488 | 0.0320 | 1.6819 |
| mintTCandTP | 100 | 167596 | 318143 | 544249 | 0.0054 | 1.7661 | 0.0103 | 0.0299 | 0.0196 | 1.0324 |
| swapTPforTP | 100 | 170164 | 386611 | 868058 | 0.0055 | 2.8168 | 0.0125 | 0.0364 | 0.0238 | 1.2546 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 2; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 424662 | 458438 | 540138 | 0.0138 | 1.7527 | 0.0149 | 0.0431 | 0.0283 | 1.4876 |
| redeemTC | 100 | 883049 | 911398 | 933306 | 0.0287 | 3.0286 | 0.0296 | 0.0858 | 0.0562 | 2.9575 |
| mintTP | 100 | 910249 | 953223 | 988634 | 0.0295 | 3.2081 | 0.0309 | 0.0897 | 0.0588 | 3.0932 |
| redeemTP | 100 | 473156 | 497848 | 534612 | 0.0154 | 1.7348 | 0.0162 | 0.0468 | 0.0307 | 1.6155 |
| swapTPforTC | 100 | 531827 | 563404 | 584080 | 0.0173 | 1.8953 | 0.0183 | 0.0530 | 0.0347 | 1.8282 |
| swapTCforTP | 100 | 1060552 | 1096861 | 1127132 | 0.0344 | 3.6575 | 0.0356 | 0.1032 | 0.0676 | 3.5593 |
| redeemTCandTP | 100 | 860489 | 899091 | 923250 | 0.0279 | 2.9959 | 0.0292 | 0.0846 | 0.0554 | 2.9176 |
| mintTCandTP | 100 | 539936 | 562981 | 597520 | 0.0175 | 1.9390 | 0.0183 | 0.0530 | 0.0347 | 1.8269 |
| swapTPforTP | 100 | 484702 | 706257 | 1023914 | 0.0157 | 3.3226 | 0.0229 | 0.0665 | 0.0435 | 2.2918 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 2; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 122130 | 223344 | 479315 | 0.0040 | 1.5554 | 0.0072 | 0.0210 | 0.0138 | 0.7248 |
| redeemTC | 100 | 468585 | 620509 | 935465 | 0.0152 | 3.0356 | 0.0201 | 0.0584 | 0.0383 | 2.0136 |
| mintTP | 100 | 463209 | 621595 | 975644 | 0.0150 | 3.1660 | 0.0202 | 0.0585 | 0.0383 | 2.0171 |
| redeemTP | 100 | 157169 | 270405 | 514092 | 0.0051 | 1.6682 | 0.0088 | 0.0254 | 0.0167 | 0.8775 |
| swapTPforTC | 100 | 176258 | 301638 | 583711 | 0.0057 | 1.8941 | 0.0098 | 0.0284 | 0.0186 | 0.9788 |
| swapTCforTP | 100 | 598500 | 780363 | 1121024 | 0.0194 | 3.6377 | 0.0253 | 0.0734 | 0.0481 | 2.5323 |
| redeemTCandTP | 100 | 378590 | 549483 | 921250 | 0.0123 | 2.9895 | 0.0178 | 0.0517 | 0.0339 | 1.7831 |
| mintTCandTP | 100 | 184331 | 310962 | 577895 | 0.0060 | 1.8753 | 0.0101 | 0.0293 | 0.0192 | 1.0091 |
| swapTPforTP | 100 | 213311 | 409120 | 988087 | 0.0069 | 3.2063 | 0.0133 | 0.0385 | 0.0252 | 1.3276 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 2; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 461077 | 494912 | 574520 | 0.0150 | 1.8643 | 0.0161 | 0.0466 | 0.0305 | 1.6060 |
| redeemTC | 100 | 1008167 | 1038666 | 1064659 | 0.0327 | 3.4548 | 0.0337 | 0.0977 | 0.0640 | 3.3705 |
| mintTP | 100 | 1026990 | 1067256 | 1110137 | 0.0333 | 3.6024 | 0.0346 | 0.1004 | 0.0658 | 3.4632 |
| redeemTP | 100 | 509570 | 532138 | 567154 | 0.0165 | 1.8404 | 0.0173 | 0.0501 | 0.0328 | 1.7268 |
| swapTPforTC | 100 | 565474 | 601691 | 637141 | 0.0183 | 2.0675 | 0.0195 | 0.0566 | 0.0371 | 1.9525 |
| swapTCforTP | 100 | 1202350 | 1235054 | 1279520 | 0.0390 | 4.1520 | 0.0401 | 0.1162 | 0.0761 | 4.0078 |
| redeemTCandTP | 100 | 952949 | 993173 | 1016608 | 0.0309 | 3.2989 | 0.0322 | 0.0935 | 0.0612 | 3.2228 |
| mintTCandTP | 100 | 573583 | 594966 | 631903 | 0.0186 | 2.0505 | 0.0193 | 0.0560 | 0.0367 | 1.9307 |
| swapTPforTP | 100 | 507847 | 754141 | 1139413 | 0.0165 | 3.6974 | 0.0245 | 0.0710 | 0.0465 | 2.4472 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 2; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 129977 | 258412 | 512592 | 0.0042 | 1.6634 | 0.0084 | 0.0243 | 0.0159 | 0.8385 |
| redeemTC | 100 | 538457 | 736595 | 1060342 | 0.0175 | 3.4408 | 0.0239 | 0.0693 | 0.0454 | 2.3903 |
| mintTP | 100 | 528534 | 731406 | 1091039 | 0.0172 | 3.5404 | 0.0237 | 0.0688 | 0.0451 | 2.3734 |
| redeemTP | 100 | 170269 | 304863 | 547370 | 0.0055 | 1.7762 | 0.0099 | 0.0287 | 0.0188 | 0.9893 |
| swapTPforTC | 100 | 187598 | 339291 | 617358 | 0.0061 | 2.0033 | 0.0110 | 0.0319 | 0.0209 | 1.1010 |
| swapTCforTP | 100 | 704517 | 918818 | 1255946 | 0.0229 | 4.0755 | 0.0298 | 0.0865 | 0.0566 | 2.9816 |
| redeemTCandTP | 100 | 431266 | 637220 | 1015502 | 0.0140 | 3.2953 | 0.0207 | 0.0600 | 0.0393 | 2.0678 |
| mintTCandTP | 100 | 196878 | 347467 | 611910 | 0.0064 | 1.9856 | 0.0113 | 0.0327 | 0.0214 | 1.1275 |
| swapTPforTP | 100 | 257896 | 485125 | 1107377 | 0.0084 | 3.5934 | 0.0157 | 0.0457 | 0.0299 | 1.5742 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 3; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 575798 | 630595 | 729535 | 0.0187 | 2.3673 | 0.0205 | 0.0593 | 0.0389 | 2.0463 |
| redeemTC | 100 | 850528 | 886148 | 917028 | 0.0276 | 2.9758 | 0.0288 | 0.0834 | 0.0546 | 2.8756 |
| mintTP | 100 | 1351319 | 1401768 | 1448341 | 0.0439 | 4.6999 | 0.0455 | 0.1319 | 0.0864 | 4.5487 |
| redeemTP | 100 | 484433 | 520335 | 556099 | 0.0157 | 1.8045 | 0.0169 | 0.0490 | 0.0321 | 1.6885 |
| swapTPforTC | 100 | 776704 | 825655 | 848003 | 0.0252 | 2.7518 | 0.0268 | 0.0777 | 0.0509 | 2.6793 |
| swapTCforTP | 100 | 1030609 | 1076713 | 1118556 | 0.0334 | 3.6297 | 0.0349 | 0.1013 | 0.0664 | 3.4939 |
| redeemTCandTP | 100 | 1267360 | 1317253 | 1344848 | 0.0411 | 4.3640 | 0.0427 | 0.1240 | 0.0812 | 4.2745 |
| mintTCandTP | 100 | 548446 | 581450 | 622880 | 0.0178 | 2.0212 | 0.0189 | 0.0547 | 0.0358 | 1.8868 |
| swapTPforTP | 100 | 715692 | 1044974 | 1437613 | 0.0232 | 4.6651 | 0.0339 | 0.0983 | 0.0644 | 3.3909 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 3; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 157407 | 379822 | 3265951 | 0.0051 | 10.5980 | 0.0123 | 0.0357 | 0.0234 | 1.2325 |
| redeemTC | 100 | 597288 | 801922 | 922545 | 0.0194 | 2.9937 | 0.0260 | 0.0755 | 0.0494 | 2.6022 |
| mintTP | 100 | 543594 | 843866 | 1434164 | 0.0176 | 4.6539 | 0.0274 | 0.0794 | 0.0520 | 2.7383 |
| redeemTP | 100 | 211682 | 351693 | 538716 | 0.0069 | 1.7481 | 0.0114 | 0.0331 | 0.0217 | 1.1412 |
| swapTPforTC | 100 | 217696 | 425861 | 845226 | 0.0071 | 2.7428 | 0.0138 | 0.0401 | 0.0263 | 1.3819 |
| swapTCforTP | 100 | 746505 | 1024071 | 1174656 | 0.0242 | 3.8118 | 0.0332 | 0.0964 | 0.0631 | 3.3231 |
| redeemTCandTP | 100 | 455096 | 757300 | 1336867 | 0.0148 | 4.3381 | 0.0246 | 0.0713 | 0.0467 | 2.4574 |
| mintTCandTP | 100 | 249057 | 409565 | 602887 | 0.0081 | 1.9564 | 0.0133 | 0.0385 | 0.0253 | 1.3290 |
| swapTPforTP | 100 | 256129 | 562797 | 1418684 | 0.0083 | 4.6036 | 0.0183 | 0.0530 | 0.0347 | 1.8263 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 3; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 636432 | 690431 | 790171 | 0.0207 | 2.5641 | 0.0224 | 0.0650 | 0.0426 | 2.2404 |
| redeemTC | 100 | 1038830 | 1072608 | 1098612 | 0.0337 | 3.5650 | 0.0348 | 0.1009 | 0.0661 | 3.4806 |
| mintTP | 100 | 1605211 | 1661633 | 1706669 | 0.0521 | 5.5381 | 0.0539 | 0.1564 | 0.1024 | 5.3920 |
| redeemTP | 100 | 529904 | 562345 | 601572 | 0.0172 | 1.9521 | 0.0182 | 0.0529 | 0.0347 | 1.8248 |
| swapTPforTC | 100 | 843724 | 885041 | 903094 | 0.0274 | 2.9305 | 0.0287 | 0.0833 | 0.0546 | 2.8720 |
| swapTCforTP | 100 | 1242324 | 1282674 | 1310720 | 0.0403 | 4.2533 | 0.0416 | 0.1207 | 0.0791 | 4.1623 |
| redeemTCandTP | 100 | 1460150 | 1523813 | 1550478 | 0.0474 | 5.0313 | 0.0494 | 0.1434 | 0.0940 | 4.9448 |
| mintTCandTP | 100 | 591150 | 629853 | 665585 | 0.0192 | 2.1598 | 0.0204 | 0.0593 | 0.0388 | 2.0439 |
| swapTPforTP | 100 | 752400 | 1152547 | 1703150 | 0.0244 | 5.5267 | 0.0374 | 0.1085 | 0.0711 | 3.7400 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 3; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 163882 | 366293 | 3057004 | 0.0053 | 9.9200 | 0.0119 | 0.0345 | 0.0226 | 1.1886 |
| redeemTC | 100 | 750036 | 996263 | 1237112 | 0.0243 | 4.0144 | 0.0323 | 0.0938 | 0.0614 | 3.2329 |
| mintTP | 100 | 673165 | 1006760 | 1680936 | 0.0218 | 5.4546 | 0.0327 | 0.0947 | 0.0621 | 3.2669 |
| redeemTP | 100 | 234939 | 389093 | 581420 | 0.0076 | 1.8867 | 0.0126 | 0.0366 | 0.0240 | 1.2626 |
| swapTPforTC | 100 | 231541 | 455401 | 902725 | 0.0075 | 2.9293 | 0.0148 | 0.0429 | 0.0281 | 1.4778 |
| swapTCforTP | 100 | 930903 | 1264831 | 1462289 | 0.0302 | 4.7451 | 0.0410 | 0.1190 | 0.0780 | 4.1044 |
| redeemTCandTP | 100 | 549959 | 883815 | 1548180 | 0.0178 | 5.0238 | 0.0287 | 0.0832 | 0.0545 | 2.8680 |
| mintTCandTP | 100 | 273154 | 448146 | 645592 | 0.0089 | 2.0949 | 0.0145 | 0.0422 | 0.0276 | 1.4542 |
| swapTPforTP | 100 | 283498 | 630373 | 1626308 | 0.0092 | 5.2774 | 0.0205 | 0.0593 | 0.0389 | 2.0456 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 3; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 695594 | 745189 | 848038 | 0.0226 | 2.7519 | 0.0242 | 0.0701 | 0.0459 | 2.4181 |
| redeemTC | 100 | 1209382 | 1250705 | 1282358 | 0.0392 | 4.1613 | 0.0406 | 0.1177 | 0.0771 | 4.0585 |
| mintTP | 100 | 1872878 | 1921916 | 1973062 | 0.0608 | 6.4026 | 0.0624 | 0.1809 | 0.1185 | 6.2366 |
| redeemTP | 100 | 572609 | 607739 | 645013 | 0.0186 | 2.0931 | 0.0197 | 0.0572 | 0.0375 | 1.9721 |
| swapTPforTC | 100 | 887458 | 941215 | 972124 | 0.0288 | 3.1545 | 0.0305 | 0.0886 | 0.0580 | 3.0542 |
| swapTCforTP | 100 | 1431761 | 1484945 | 1518038 | 0.0465 | 4.9260 | 0.0482 | 0.1397 | 0.0916 | 4.8186 |
| redeemTCandTP | 100 | 1673270 | 1730171 | 1755902 | 0.0543 | 5.6979 | 0.0561 | 0.1628 | 0.1067 | 5.6144 |
| mintTCandTP | 100 | 633853 | 669575 | 709183 | 0.0206 | 2.3013 | 0.0217 | 0.0630 | 0.0413 | 2.1728 |
| swapTPforTP | 100 | 788465 | 1303945 | 1962079 | 0.0256 | 6.3669 | 0.0423 | 0.1227 | 0.0804 | 4.2313 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 3; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 170971 | 430606 | 4457197 | 0.0055 | 14.4636 | 0.0140 | 0.0405 | 0.0265 | 1.3973 |
| redeemTC | 100 | 892231 | 1186841 | 1463892 | 0.0290 | 4.7503 | 0.0385 | 0.1117 | 0.0732 | 3.8513 |
| mintTP | 100 | 691473 | 1134089 | 1950240 | 0.0224 | 6.3285 | 0.0368 | 0.1067 | 0.0699 | 3.6801 |
| redeemTP | 100 | 219894 | 404788 | 792180 | 0.0071 | 2.5706 | 0.0131 | 0.0381 | 0.0250 | 1.3135 |
| swapTPforTC | 100 | 247873 | 451662 | 959485 | 0.0080 | 3.1135 | 0.0147 | 0.0425 | 0.0278 | 1.4656 |
| swapTCforTP | 100 | 1112101 | 1501488 | 1735201 | 0.0361 | 5.6307 | 0.0487 | 0.1413 | 0.0926 | 4.8723 |
| redeemTCandTP | 100 | 634430 | 959239 | 1747794 | 0.0206 | 5.6716 | 0.0311 | 0.0903 | 0.0591 | 3.1127 |
| mintTCandTP | 100 | 250144 | 460409 | 688663 | 0.0081 | 2.2347 | 0.0149 | 0.0433 | 0.0284 | 1.4940 |
| swapTPforTP | 100 | 335384 | 646581 | 1962462 | 0.0109 | 6.3682 | 0.0210 | 0.0608 | 0.0399 | 2.0982 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 3; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 754198 | 804466 | 905536 | 0.0245 | 2.9385 | 0.0261 | 0.0757 | 0.0496 | 2.6105 |
| redeemTC | 100 | 1386650 | 1435685 | 1466102 | 0.0450 | 4.7575 | 0.0466 | 0.1351 | 0.0885 | 4.6588 |
| mintTP | 100 | 2121392 | 2182555 | 2227055 | 0.0688 | 7.2268 | 0.0708 | 0.2054 | 0.1346 | 7.0824 |
| redeemTP | 100 | 615682 | 649696 | 687349 | 0.0200 | 2.2304 | 0.0211 | 0.0611 | 0.0401 | 2.1083 |
| swapTPforTC | 100 | 947357 | 998656 | 1029990 | 0.0307 | 3.3423 | 0.0324 | 0.0940 | 0.0616 | 3.2406 |
| swapTCforTP | 100 | 1640821 | 1690708 | 1726090 | 0.0532 | 5.6012 | 0.0549 | 0.1591 | 0.1042 | 5.4863 |
| redeemTCandTP | 100 | 1876902 | 1934525 | 1958956 | 0.0609 | 6.3568 | 0.0628 | 0.1820 | 0.1193 | 6.2775 |
| mintTCandTP | 100 | 679484 | 710878 | 751888 | 0.0220 | 2.4399 | 0.0231 | 0.0669 | 0.0438 | 2.3068 |
| swapTPforTP | 100 | 843022 | 1435464 | 2236256 | 0.0274 | 7.2567 | 0.0466 | 0.1351 | 0.0885 | 4.6581 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 3; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 184221 | 409524 | 3887444 | 0.0060 | 12.6148 | 0.0133 | 0.0385 | 0.0252 | 1.3289 |
| redeemTC | 100 | 1068871 | 1374868 | 1604706 | 0.0347 | 5.2073 | 0.0446 | 0.1294 | 0.0848 | 4.4614 |
| mintTP | 100 | 912417 | 1339557 | 2214293 | 0.0296 | 7.1854 | 0.0435 | 0.1261 | 0.0826 | 4.3469 |
| redeemTP | 100 | 274258 | 429515 | 666829 | 0.0089 | 2.1639 | 0.0139 | 0.0404 | 0.0265 | 1.3938 |
| swapTPforTC | 100 | 263510 | 494892 | 1014216 | 0.0086 | 3.2911 | 0.0161 | 0.0466 | 0.0305 | 1.6059 |
| swapTCforTP | 100 | 1293919 | 1726090 | 1988244 | 0.0420 | 6.4519 | 0.0560 | 0.1624 | 0.1064 | 5.6012 |
| redeemTCandTP | 100 | 727983 | 1121522 | 1954270 | 0.0236 | 6.3416 | 0.0364 | 0.1055 | 0.0691 | 3.6393 |
| mintTCandTP | 100 | 316917 | 486059 | 731368 | 0.0103 | 2.3733 | 0.0158 | 0.0457 | 0.0300 | 1.5773 |
| swapTPforTP | 100 | 290324 | 828081 | 2223762 | 0.0094 | 7.2161 | 0.0269 | 0.0779 | 0.0511 | 2.6871 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 4; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 812506 | 878146 | 999260 | 0.0264 | 3.2426 | 0.0285 | 0.0826 | 0.0541 | 2.8496 |
| redeemTC | 100 | 1050149 | 1098697 | 1127926 | 0.0341 | 3.6601 | 0.0357 | 0.1034 | 0.0677 | 3.5653 |
| mintTP | 100 | 2231830 | 2279797 | 2319976 | 0.0724 | 7.5283 | 0.0740 | 0.2145 | 0.1406 | 7.3979 |
| redeemTP | 100 | 551552 | 583386 | 625987 | 0.0179 | 2.0313 | 0.0189 | 0.0549 | 0.0360 | 1.8931 |
| swapTPforTC | 100 | 1094742 | 1159560 | 1197896 | 0.0355 | 3.8872 | 0.0376 | 0.1091 | 0.0715 | 3.7628 |
| swapTCforTP | 100 | 1270596 | 1313848 | 1346848 | 0.0412 | 4.3705 | 0.0426 | 0.1236 | 0.0810 | 4.2634 |
| redeemTCandTP | 100 | 2011200 | 2065193 | 2092678 | 0.0653 | 6.7907 | 0.0670 | 0.1943 | 0.1273 | 6.7016 |
| mintTCandTP | 100 | 615565 | 652903 | 687232 | 0.0200 | 2.2301 | 0.0212 | 0.0614 | 0.0403 | 2.1187 |
| swapTPforTP | 100 | 998762 | 1505750 | 2317927 | 0.0324 | 7.5217 | 0.0489 | 0.1417 | 0.0928 | 4.8862 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 4; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 182081 | 630863 | 4659317 | 0.0059 | 15.1195 | 0.0205 | 0.0594 | 0.0389 | 2.0472 |
| redeemTC | 100 | 716031 | 1269920 | 5427086 | 0.0232 | 17.6109 | 0.0412 | 0.1195 | 0.0783 | 4.1209 |
| mintTP | 100 | 749421 | 1301519 | 6330167 | 0.0243 | 20.5414 | 0.0422 | 0.1225 | 0.0802 | 4.2234 |
| redeemTP | 100 | 176712 | 474993 | 5254706 | 0.0057 | 17.0515 | 0.0154 | 0.0447 | 0.0293 | 1.5414 |
| swapTPforTC | 100 | 240064 | 615761 | 4974415 | 0.0078 | 16.1420 | 0.0200 | 0.0579 | 0.0380 | 1.9981 |
| swapTCforTP | 100 | 947979 | 1541847 | 4658887 | 0.0308 | 15.1181 | 0.0500 | 0.1451 | 0.0951 | 5.0033 |
| redeemTCandTP | 100 | 534120 | 1090825 | 3317135 | 0.0173 | 10.7641 | 0.0354 | 0.1027 | 0.0673 | 3.5397 |
| mintTCandTP | 100 | 207202 | 468064 | 2318177 | 0.0067 | 7.5225 | 0.0152 | 0.0440 | 0.0289 | 1.5189 |
| swapTPforTP | 100 | 243734 | 739268 | 1899474 | 0.0079 | 6.1638 | 0.0240 | 0.0696 | 0.0456 | 2.3989 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 4; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 891085 | 962442 | 1080980 | 0.0289 | 3.5078 | 0.0312 | 0.0906 | 0.0593 | 3.1231 |
| redeemTC | 100 | 1290840 | 1333826 | 1364057 | 0.0419 | 4.4264 | 0.0433 | 0.1255 | 0.0822 | 4.3283 |
| mintTP | 100 | 2688361 | 2742396 | 2781757 | 0.0872 | 9.0268 | 0.0890 | 0.2581 | 0.1691 | 8.8991 |
| redeemTP | 100 | 606450 | 639958 | 678118 | 0.0197 | 2.2005 | 0.0208 | 0.0602 | 0.0395 | 2.0767 |
| swapTPforTC | 100 | 1175725 | 1241385 | 1280772 | 0.0382 | 4.1561 | 0.0403 | 0.1168 | 0.0765 | 4.0283 |
| swapTCforTP | 100 | 1539960 | 1586834 | 1615969 | 0.0500 | 5.2438 | 0.0515 | 0.1493 | 0.0978 | 5.1493 |
| redeemTCandTP | 100 | 2353446 | 2425097 | 2455046 | 0.0764 | 7.9666 | 0.0787 | 0.2282 | 0.1495 | 7.8694 |
| mintTCandTP | 100 | 670464 | 698969 | 742130 | 0.0218 | 2.4082 | 0.0227 | 0.0658 | 0.0431 | 2.2682 |
| swapTPforTP | 100 | 1061586 | 1834528 | 2790932 | 0.0344 | 9.0566 | 0.0595 | 0.1726 | 0.1131 | 5.9530 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 4; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 187567 | 810727 | 6273653 | 0.0061 | 20.3580 | 0.0263 | 0.0763 | 0.0500 | 2.6308 |
| redeemTC | 100 | 925215 | 1638790 | 6213518 | 0.0300 | 20.1629 | 0.0532 | 0.1542 | 0.1010 | 5.3179 |
| mintTP | 100 | 891022 | 1630295 | 7491216 | 0.0289 | 24.3090 | 0.0529 | 0.1534 | 0.1005 | 5.2903 |
| redeemTP | 100 | 190624 | 648266 | 6988195 | 0.0062 | 22.6767 | 0.0210 | 0.0610 | 0.0400 | 2.1036 |
| swapTPforTC | 100 | 262366 | 745384 | 5751936 | 0.0085 | 18.6650 | 0.0242 | 0.0701 | 0.0460 | 2.4188 |
| swapTCforTP | 100 | 1189390 | 1901044 | 5446700 | 0.0386 | 17.6745 | 0.0617 | 0.1789 | 0.1172 | 6.1689 |
| redeemTCandTP | 100 | 655195 | 1362500 | 5917459 | 0.0213 | 19.2022 | 0.0442 | 0.1282 | 0.0840 | 4.4213 |
| mintTCandTP | 100 | 221289 | 561965 | 4622640 | 0.0072 | 15.0005 | 0.0182 | 0.0529 | 0.0346 | 1.8236 |
| swapTPforTP | 100 | 373407 | 924505 | 7315555 | 0.0121 | 23.7390 | 0.0300 | 0.0870 | 0.0570 | 3.0000 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 4; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 977047 | 1043885 | 1161962 | 0.0317 | 3.7706 | 0.0339 | 0.0982 | 0.0644 | 3.3874 |
| redeemTC | 100 | 1531537 | 1570616 | 1606673 | 0.0497 | 5.2137 | 0.0510 | 0.1478 | 0.0968 | 5.0966 |
| mintTP | 100 | 3156182 | 3208502 | 3262674 | 0.1024 | 10.5874 | 0.1041 | 0.3019 | 0.1978 | 10.4116 |
| redeemTP | 100 | 658580 | 691678 | 730616 | 0.0214 | 2.3708 | 0.0224 | 0.0651 | 0.0426 | 2.2445 |
| swapTPforTC | 100 | 1257073 | 1322865 | 1342873 | 0.0408 | 4.3576 | 0.0429 | 0.1245 | 0.0816 | 4.2927 |
| swapTCforTP | 100 | 1805221 | 1852900 | 1887098 | 0.0586 | 6.1236 | 0.0601 | 0.1744 | 0.1142 | 6.0127 |
| redeemTCandTP | 100 | 2722043 | 2784261 | 2816717 | 0.0883 | 9.1402 | 0.0903 | 0.2620 | 0.1717 | 9.0349 |
| mintTCandTP | 100 | 719825 | 755121 | 794996 | 0.0234 | 2.5798 | 0.0245 | 0.0711 | 0.0466 | 2.4504 |
| swapTPforTP | 100 | 1118344 | 1982087 | 3231308 | 0.0363 | 10.4856 | 0.0643 | 0.1865 | 0.1222 | 6.4319 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 4; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 199951 | 828087 | 5812957 | 0.0065 | 18.8630 | 0.0269 | 0.0779 | 0.0511 | 2.6871 |
| redeemTC | 100 | 1123452 | 1932014 | 6003892 | 0.0365 | 19.4826 | 0.0627 | 0.1818 | 0.1191 | 6.2694 |
| mintTP | 100 | 1035391 | 1873382 | 7149000 | 0.0336 | 23.1985 | 0.0608 | 0.1763 | 0.1155 | 6.0791 |
| redeemTP | 100 | 206785 | 721633 | 7033652 | 0.0067 | 22.8242 | 0.0234 | 0.0679 | 0.0445 | 2.3417 |
| swapTPforTC | 100 | 278590 | 815965 | 3928628 | 0.0090 | 12.7484 | 0.0265 | 0.0768 | 0.0503 | 2.6478 |
| swapTCforTP | 100 | 1455123 | 2281651 | 4427896 | 0.0472 | 14.3685 | 0.0740 | 0.2147 | 0.1407 | 7.4040 |
| redeemTCandTP | 100 | 773027 | 1524942 | 4208951 | 0.0251 | 13.6580 | 0.0495 | 0.1435 | 0.0940 | 4.9484 |
| mintTCandTP | 100 | 236933 | 598556 | 2851460 | 0.0077 | 9.2530 | 0.0194 | 0.0563 | 0.0369 | 1.9423 |
| swapTPforTP | 100 | 400307 | 1071504 | 3493123 | 0.0130 | 11.3352 | 0.0348 | 0.1008 | 0.0661 | 3.4770 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 4; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1057292 | 1126255 | 1243312 | 0.0343 | 4.0345 | 0.0365 | 0.1060 | 0.0694 | 3.6547 |
| redeemTC | 100 | 1763354 | 1808600 | 1842806 | 0.0572 | 5.9799 | 0.0587 | 0.1702 | 0.1115 | 5.8689 |
| mintTP | 100 | 3603486 | 3669405 | 3717805 | 0.1169 | 12.0643 | 0.1191 | 0.3453 | 0.2262 | 11.9072 |
| redeemTP | 100 | 710711 | 744292 | 783115 | 0.0231 | 2.5412 | 0.0242 | 0.0700 | 0.0459 | 2.4152 |
| swapTPforTC | 100 | 1338793 | 1406327 | 1424057 | 0.0434 | 4.6211 | 0.0456 | 0.1323 | 0.0867 | 4.5635 |
| swapTCforTP | 100 | 2085013 | 2123948 | 2161856 | 0.0677 | 7.0152 | 0.0689 | 0.1999 | 0.1310 | 6.8922 |
| redeemTCandTP | 100 | 3075176 | 3140856 | 3175972 | 0.0998 | 10.3060 | 0.1019 | 0.2956 | 0.1936 | 10.1921 |
| mintTCandTP | 100 | 774724 | 808017 | 847127 | 0.0251 | 2.7489 | 0.0262 | 0.0760 | 0.0498 | 2.6220 |
| swapTPforTP | 100 | 1174122 | 2162959 | 3729290 | 0.0381 | 12.1015 | 0.0702 | 0.2035 | 0.1334 | 7.0188 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 4; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 213048 | 937380 | 10135678 | 0.0069 | 32.8903 | 0.0304 | 0.0882 | 0.0578 | 3.0418 |
| redeemTC | 100 | 1325620 | 2311318 | 10507838 | 0.0430 | 34.0979 | 0.0750 | 0.2175 | 0.1425 | 7.5002 |
| mintTP | 100 | 1254045 | 2146664 | 8572684 | 0.0407 | 27.8184 | 0.0697 | 0.2020 | 0.1324 | 6.9659 |
| redeemTP | 100 | 229758 | 716109 | 7431444 | 0.0075 | 24.1150 | 0.0232 | 0.0674 | 0.0442 | 2.3238 |
| swapTPforTC | 100 | 296586 | 863690 | 4070161 | 0.0096 | 13.2077 | 0.0280 | 0.0813 | 0.0533 | 2.8027 |
| swapTCforTP | 100 | 1710036 | 2663029 | 5221170 | 0.0555 | 16.9427 | 0.0864 | 0.2506 | 0.1642 | 8.6415 |
| redeemTCandTP | 100 | 877540 | 1790663 | 4899311 | 0.0285 | 15.8983 | 0.0581 | 0.1685 | 0.1104 | 5.8107 |
| mintTCandTP | 100 | 258224 | 637883 | 3387642 | 0.0084 | 10.9929 | 0.0207 | 0.0600 | 0.0393 | 2.0699 |
| swapTPforTP | 100 | 466807 | 1148366 | 3686573 | 0.0151 | 11.9629 | 0.0373 | 0.1081 | 0.0708 | 3.7264 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 5; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1044414 | 1124762 | 1266955 | 0.0339 | 4.1113 | 0.0365 | 0.1058 | 0.0693 | 3.6499 |
| redeemTC | 100 | 1256489 | 1302573 | 1334507 | 0.0408 | 4.3305 | 0.0423 | 0.1226 | 0.0803 | 4.2268 |
| mintTP | 100 | 3264911 | 3350491 | 3398928 | 0.1059 | 11.0295 | 0.1087 | 0.3153 | 0.2066 | 10.8723 |
| redeemTP | 100 | 618673 | 652028 | 690340 | 0.0201 | 2.2402 | 0.0212 | 0.0614 | 0.0402 | 2.1158 |
| swapTPforTC | 100 | 1410013 | 1493773 | 1516564 | 0.0458 | 4.9213 | 0.0485 | 0.1406 | 0.0921 | 4.8473 |
| swapTCforTP | 100 | 1517545 | 1562366 | 1591397 | 0.0492 | 5.1641 | 0.0507 | 0.1470 | 0.0963 | 5.0699 |
| redeemTCandTP | 100 | 2870984 | 2947185 | 2975410 | 0.0932 | 9.6552 | 0.0956 | 0.2773 | 0.1817 | 9.5636 |
| mintTCandTP | 100 | 682686 | 718995 | 757648 | 0.0222 | 2.4586 | 0.0233 | 0.0677 | 0.0443 | 2.3331 |
| swapTPforTP | 100 | 1294204 | 2079255 | 2897044 | 0.0420 | 9.4009 | 0.0675 | 0.1957 | 0.1282 | 6.7472 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 5; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 219644 | 1355247 | 7498492 | 0.0071 | 24.3326 | 0.0440 | 0.1275 | 0.0836 | 4.3978 |
| redeemTC | 100 | 858014 | 1983729 | 6477665 | 0.0278 | 21.0200 | 0.0644 | 0.1867 | 0.1223 | 6.4372 |
| mintTP | 100 | 891485 | 2030013 | 9121102 | 0.0289 | 29.5980 | 0.0659 | 0.1910 | 0.1252 | 6.5874 |
| redeemTP | 100 | 178770 | 1120834 | 7007056 | 0.0058 | 22.7379 | 0.0364 | 0.1055 | 0.0691 | 3.6371 |
| swapTPforTC | 100 | 216598 | 1237232 | 5676601 | 0.0070 | 18.4206 | 0.0401 | 0.1164 | 0.0763 | 4.0148 |
| swapTCforTP | 100 | 1129192 | 2344873 | 6372728 | 0.0366 | 20.6795 | 0.0761 | 0.2207 | 0.1446 | 7.6091 |
| redeemTCandTP | 100 | 920348 | 1918532 | 8125686 | 0.0299 | 26.3679 | 0.0623 | 0.1805 | 0.1183 | 6.2256 |
| mintTCandTP | 100 | 209383 | 961220 | 6751766 | 0.0068 | 21.9095 | 0.0312 | 0.0905 | 0.0593 | 3.1192 |
| swapTPforTP | 100 | 251644 | 1237245 | 6473921 | 0.0082 | 21.0079 | 0.0401 | 0.1164 | 0.0763 | 4.0149 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 5; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1147213 | 1231281 | 1372528 | 0.0372 | 4.4539 | 0.0400 | 0.1159 | 0.0759 | 3.9955 |
| redeemTC | 100 | 1554372 | 1598596 | 1629506 | 0.0504 | 5.2877 | 0.0519 | 0.1504 | 0.0986 | 5.1874 |
| mintTP | 100 | 3995552 | 4069000 | 4138535 | 0.1297 | 13.4295 | 0.1320 | 0.3829 | 0.2509 | 13.2039 |
| redeemTP | 100 | 673508 | 716117 | 754664 | 0.0219 | 2.4489 | 0.0232 | 0.0674 | 0.0442 | 2.3238 |
| swapTPforTC | 100 | 1535369 | 1599476 | 1618517 | 0.0498 | 5.2521 | 0.0519 | 0.1505 | 0.0986 | 5.1903 |
| swapTCforTP | 100 | 1856250 | 1893052 | 1928596 | 0.0602 | 6.2583 | 0.0614 | 0.1781 | 0.1167 | 6.1430 |
| redeemTCandTP | 100 | 3426677 | 3500841 | 3540034 | 0.1112 | 11.4874 | 0.1136 | 0.3294 | 0.2158 | 11.3602 |
| mintTCandTP | 100 | 744242 | 781402 | 819046 | 0.0242 | 2.6578 | 0.0254 | 0.0735 | 0.0482 | 2.5356 |
| swapTPforTP | 100 | 1367154 | 2543149 | 4105794 | 0.0444 | 13.3233 | 0.0825 | 0.2393 | 0.1568 | 8.2525 |

ARB Executing; Price: $3245; Average OPs per batch: 10; Collaterals: 5; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 206750 | 1621807 | 8546442 | 0.0067 | 27.7332 | 0.0526 | 0.1526 | 0.1000 | 5.2628 |
| redeemTC | 100 | 1113791 | 2500937 | 8861092 | 0.0361 | 28.7542 | 0.0812 | 0.2354 | 0.1542 | 8.1155 |
| mintTP | 100 | 1138371 | 2391233 | 8751979 | 0.0369 | 28.4002 | 0.0776 | 0.2250 | 0.1474 | 7.7596 |
| redeemTP | 100 | 195381 | 1318647 | 8881136 | 0.0063 | 28.8193 | 0.0428 | 0.1241 | 0.0813 | 4.2790 |
| swapTPforTC | 100 | 229004 | 1574245 | 9295964 | 0.0074 | 30.1654 | 0.0511 | 0.1481 | 0.0971 | 5.1084 |
| swapTCforTP | 100 | 1440280 | 2857707 | 8276447 | 0.0467 | 26.8571 | 0.0927 | 0.2689 | 0.1762 | 9.2733 |
| redeemTCandTP | 100 | 1123929 | 2369786 | 9306277 | 0.0365 | 30.1989 | 0.0769 | 0.2230 | 0.1461 | 7.6900 |
| mintTCandTP | 100 | 226971 | 1257600 | 7632277 | 0.0074 | 24.7667 | 0.0408 | 0.1183 | 0.0775 | 4.0809 |
| swapTPforTP | 100 | 247701 | 1721968 | 8194517 | 0.0080 | 26.5912 | 0.0559 | 0.1620 | 0.1062 | 5.5878 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 5; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1254080 | 1339630 | 1476994 | 0.0407 | 4.7928 | 0.0435 | 0.1261 | 0.0826 | 4.3471 |
| redeemTC | 100 | 1856096 | 1893964 | 1922356 | 0.0602 | 6.2380 | 0.0615 | 0.1782 | 0.1168 | 6.1459 |
| mintTP | 100 | 4730621 | 4797511 | 4855302 | 0.1535 | 15.7555 | 0.1557 | 0.4515 | 0.2958 | 15.5679 |
| redeemTP | 100 | 744553 | 774999 | 816221 | 0.0242 | 2.6486 | 0.0251 | 0.0729 | 0.0478 | 2.5149 |
| swapTPforTC | 100 | 1624290 | 1704291 | 1737767 | 0.0527 | 5.6391 | 0.0553 | 0.1604 | 0.1051 | 5.5304 |
| swapTCforTP | 100 | 2177660 | 2219768 | 2255692 | 0.0707 | 7.3197 | 0.0720 | 0.2089 | 0.1369 | 7.2031 |
| redeemTCandTP | 100 | 3986010 | 4055481 | 4101704 | 0.1293 | 13.3100 | 0.1316 | 0.3816 | 0.2500 | 13.1600 |
| mintTCandTP | 100 | 805798 | 838695 | 880232 | 0.0261 | 2.8564 | 0.0272 | 0.0789 | 0.0517 | 2.7216 |
| swapTPforTP | 100 | 1446757 | 2650251 | 4063351 | 0.0469 | 13.1856 | 0.0860 | 0.2494 | 0.1634 | 8.6001 |

ARB Executing; Price: $3245; Average OPs per batch: 1; Collaterals: 5; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.01gw | $ avgGas @ 0.029gw | $ avgGas @ 0.019gw | $ avgGas @ 1.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1360020 | 1445659 | 1582931 | 0.0441 | 5.1366 | 0.0469 | 0.1360 | 0.0891 | 4.6912 |
| redeemTC | 100 | 2137908 | 2186313 | 2219519 | 0.0694 | 7.2023 | 0.0709 | 0.2057 | 0.1348 | 7.0946 |
| mintTP | 100 | 5452975 | 5520436 | 5579204 | 0.1769 | 18.1045 | 0.1791 | 0.5195 | 0.3404 | 17.9138 |
| redeemTP | 100 | 806110 | 839844 | 878514 | 0.0262 | 2.8508 | 0.0273 | 0.0790 | 0.0518 | 2.7253 |
| swapTPforTC | 100 | 1728757 | 1811258 | 1864225 | 0.0561 | 6.0494 | 0.0588 | 0.1704 | 0.1117 | 5.8775 |
| swapTCforTP | 100 | 2508439 | 2556886 | 2593370 | 0.0814 | 8.4155 | 0.0830 | 0.2406 | 0.1576 | 8.2971 |
| redeemTCandTP | 100 | 4534062 | 4612152 | 4651072 | 0.1471 | 15.0927 | 0.1497 | 0.4340 | 0.2844 | 14.9664 |
| mintTCandTP | 100 | 867354 | 904441 | 942526 | 0.0281 | 3.0585 | 0.0293 | 0.0851 | 0.0558 | 2.9349 |
| swapTPforTP | 100 | 1510642 | 3361126 | 5595643 | 0.0490 | 18.1579 | 0.1091 | 0.3163 | 0.2072 | 10.9069 |

POL Queueing; Price: $0.122; Gas adjustment: 1.2
| (index) | blockGasLimit | estimatedGas | gasLeftPct | min fee @ 27.0gw | $ min | avg fee @ 15.0gw | $ avg | median fee @ 18.0gw | $ median | max fee @ 439.0gw | $ max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 45000000 | 280278 | 99.38% | 7567506000000000 | 0.0009 | 4204170000000000 | 0.0005 | 5045004000000000 | 0.0006 | 123042042000000000 | 0.0150 |
| redeemTC | 45000000 | 257028 | 99.43% | 6939756000000000 | 0.0008 | 3855420000000000 | 0.0005 | 4626504000000000 | 0.0006 | 112835292000000000 | 0.0138 |
| mintTP | 45000000 | 287759 | 99.36% | 7769493000000000 | 0.0009 | 4316385000000000 | 0.0005 | 5179662000000000 | 0.0006 | 126326201000000000 | 0.0154 |
| redeemTP | 45000000 | 279650 | 99.38% | 7550550000000000 | 0.0009 | 4194750000000000 | 0.0005 | 5033700000000000 | 0.0006 | 122766350000000000 | 0.0150 |
| swapTPforTP | 45000000 | 342821 | 99.24% | 9256167000000000 | 0.0011 | 5142315000000000 | 0.0006 | 6170778000000000 | 0.0008 | 150498419000000000 | 0.0184 |
| swapTPforTC | 45000000 | 315461 | 99.30% | 8517447000000000 | 0.0010 | 4731915000000000 | 0.0006 | 5678298000000000 | 0.0007 | 138487379000000000 | 0.0169 |
| swapTCforTP | 45000000 | 320234 | 99.29% | 8646318000000000 | 0.0011 | 4803510000000000 | 0.0006 | 5764212000000000 | 0.0007 | 140582726000000000 | 0.0172 |
| redeemTCandTP | 45000000 | 317005 | 99.30% | 8559135000000000 | 0.0010 | 4755075000000000 | 0.0006 | 5706090000000000 | 0.0007 | 139165195000000000 | 0.0170 |
| mintTCandTP | 45000000 | 288104 | 99.36% | 7778808000000000 | 0.0009 | 4321560000000000 | 0.0005 | 5185872000000000 | 0.0006 | 126477656000000000 | 0.0154 |
| execSettlement | 45000000 | 170743 | 99.62% | 4610061000000000 | 0.0006 | 2561145000000000 | 0.0003 | 3073374000000000 | 0.0004 | 74956177000000000 | 0.0091 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 2; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 358106 | 392165 | 473581 | 0.0012 | 0.0254 | 0.0013 | 0.0007 | 0.0009 | 0.0210 |
| redeemTC | 100 | 626574 | 659112 | 681390 | 0.0021 | 0.0365 | 0.0022 | 0.0012 | 0.0014 | 0.0353 |
| mintTP | 100 | 680428 | 722795 | 757548 | 0.0022 | 0.0406 | 0.0024 | 0.0013 | 0.0016 | 0.0387 |
| redeemTP | 100 | 406601 | 433631 | 467320 | 0.0013 | 0.0250 | 0.0014 | 0.0008 | 0.0010 | 0.0232 |
| swapTPforTC | 100 | 462503 | 496240 | 516787 | 0.0015 | 0.0277 | 0.0016 | 0.0009 | 0.0011 | 0.0266 |
| swapTCforTP | 100 | 783018 | 813103 | 836119 | 0.0026 | 0.0448 | 0.0027 | 0.0015 | 0.0018 | 0.0435 |
| redeemTCandTP | 100 | 673984 | 710499 | 731689 | 0.0022 | 0.0392 | 0.0023 | 0.0013 | 0.0016 | 0.0381 |
| mintTCandTP | 100 | 470612 | 495680 | 528196 | 0.0016 | 0.0283 | 0.0016 | 0.0009 | 0.0011 | 0.0265 |
| swapTPforTP | 100 | 438409 | 566692 | 757194 | 0.0014 | 0.0406 | 0.0019 | 0.0010 | 0.0012 | 0.0304 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 2; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 107312 | 228671 | 412390 | 0.0004 | 0.0221 | 0.0008 | 0.0004 | 0.0005 | 0.0122 |
| redeemTC | 100 | 311960 | 473944 | 677072 | 0.0010 | 0.0363 | 0.0016 | 0.0009 | 0.0010 | 0.0254 |
| mintTP | 100 | 312747 | 498895 | 744958 | 0.0010 | 0.0399 | 0.0016 | 0.0009 | 0.0011 | 0.0267 |
| redeemTP | 100 | 129849 | 266460 | 446800 | 0.0004 | 0.0239 | 0.0009 | 0.0005 | 0.0006 | 0.0143 |
| swapTPforTC | 100 | 150682 | 305136 | 516787 | 0.0005 | 0.0277 | 0.0010 | 0.0006 | 0.0007 | 0.0163 |
| swapTCforTP | 100 | 403800 | 603372 | 836119 | 0.0013 | 0.0448 | 0.0020 | 0.0011 | 0.0013 | 0.0323 |
| redeemTCandTP | 100 | 276450 | 472712 | 729899 | 0.0009 | 0.0391 | 0.0016 | 0.0009 | 0.0010 | 0.0253 |
| mintTCandTP | 100 | 151041 | 313029 | 510971 | 0.0005 | 0.0274 | 0.0010 | 0.0006 | 0.0007 | 0.0168 |
| swapTPforTP | 100 | 157194 | 377594 | 753982 | 0.0005 | 0.0404 | 0.0012 | 0.0007 | 0.0008 | 0.0202 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 2; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 394152 | 428209 | 504091 | 0.0013 | 0.0270 | 0.0014 | 0.0008 | 0.0009 | 0.0229 |
| redeemTC | 100 | 753852 | 785924 | 810584 | 0.0025 | 0.0434 | 0.0026 | 0.0014 | 0.0017 | 0.0421 |
| mintTP | 100 | 798222 | 834364 | 882715 | 0.0026 | 0.0473 | 0.0027 | 0.0015 | 0.0018 | 0.0447 |
| redeemTP | 100 | 439878 | 464304 | 500230 | 0.0014 | 0.0268 | 0.0015 | 0.0008 | 0.0010 | 0.0249 |
| swapTPforTC | 100 | 498550 | 531071 | 570586 | 0.0016 | 0.0306 | 0.0017 | 0.0010 | 0.0012 | 0.0284 |
| swapTCforTP | 100 | 914645 | 952089 | 981624 | 0.0030 | 0.0526 | 0.0031 | 0.0017 | 0.0021 | 0.0510 |
| redeemTCandTP | 100 | 768235 | 805021 | 827942 | 0.0025 | 0.0443 | 0.0027 | 0.0015 | 0.0018 | 0.0431 |
| mintTCandTP | 100 | 503891 | 531084 | 561474 | 0.0017 | 0.0301 | 0.0017 | 0.0010 | 0.0012 | 0.0284 |
| swapTPforTP | 100 | 461555 | 639737 | 876484 | 0.0015 | 0.0469 | 0.0021 | 0.0012 | 0.0014 | 0.0343 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 2; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 113890 | 212502 | 445668 | 0.0004 | 0.0239 | 0.0007 | 0.0004 | 0.0005 | 0.0114 |
| redeemTC | 100 | 385305 | 529393 | 804108 | 0.0013 | 0.0431 | 0.0017 | 0.0010 | 0.0012 | 0.0284 |
| mintTP | 100 | 389534 | 539771 | 860195 | 0.0013 | 0.0461 | 0.0018 | 0.0010 | 0.0012 | 0.0289 |
| redeemTP | 100 | 146872 | 255871 | 480078 | 0.0005 | 0.0257 | 0.0008 | 0.0005 | 0.0006 | 0.0137 |
| swapTPforTC | 100 | 162382 | 288955 | 550066 | 0.0005 | 0.0295 | 0.0010 | 0.0005 | 0.0006 | 0.0155 |
| swapTCforTP | 100 | 506363 | 672336 | 975358 | 0.0017 | 0.0522 | 0.0022 | 0.0012 | 0.0015 | 0.0360 |
| redeemTCandTP | 100 | 328504 | 490319 | 824837 | 0.0011 | 0.0442 | 0.0016 | 0.0009 | 0.0011 | 0.0263 |
| mintTCandTP | 100 | 164787 | 298578 | 544618 | 0.0005 | 0.0292 | 0.0010 | 0.0005 | 0.0007 | 0.0160 |
| swapTPforTP | 100 | 171745 | 366418 | 864236 | 0.0006 | 0.0463 | 0.0012 | 0.0007 | 0.0008 | 0.0196 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 2; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 427430 | 461670 | 540875 | 0.0014 | 0.0290 | 0.0015 | 0.0008 | 0.0010 | 0.0247 |
| redeemTC | 100 | 872014 | 910168 | 937624 | 0.0029 | 0.0502 | 0.0030 | 0.0017 | 0.0020 | 0.0487 |
| mintTP | 100 | 913830 | 949967 | 997955 | 0.0030 | 0.0534 | 0.0031 | 0.0017 | 0.0021 | 0.0509 |
| redeemTP | 100 | 475925 | 499421 | 533875 | 0.0016 | 0.0286 | 0.0016 | 0.0009 | 0.0011 | 0.0267 |
| swapTPforTC | 100 | 529058 | 567493 | 603863 | 0.0017 | 0.0323 | 0.0019 | 0.0010 | 0.0012 | 0.0304 |
| swapTCforTP | 100 | 1064952 | 1095641 | 1139386 | 0.0035 | 0.0610 | 0.0036 | 0.0020 | 0.0024 | 0.0587 |
| redeemTCandTP | 100 | 861752 | 898274 | 921618 | 0.0028 | 0.0494 | 0.0030 | 0.0016 | 0.0020 | 0.0481 |
| mintTCandTP | 100 | 533743 | 562733 | 598046 | 0.0018 | 0.0320 | 0.0019 | 0.0010 | 0.0012 | 0.0301 |
| swapTPforTP | 100 | 484702 | 631860 | 1026073 | 0.0016 | 0.0550 | 0.0021 | 0.0012 | 0.0014 | 0.0338 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 2; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 121421 | 230350 | 479315 | 0.0004 | 0.0257 | 0.0008 | 0.0004 | 0.0005 | 0.0123 |
| redeemTC | 100 | 464796 | 630838 | 934831 | 0.0015 | 0.0501 | 0.0021 | 0.0012 | 0.0014 | 0.0338 |
| mintTP | 100 | 454714 | 631416 | 971327 | 0.0015 | 0.0520 | 0.0021 | 0.0012 | 0.0014 | 0.0338 |
| redeemTP | 100 | 157290 | 278186 | 513724 | 0.0005 | 0.0275 | 0.0009 | 0.0005 | 0.0006 | 0.0149 |
| swapTPforTC | 100 | 173887 | 312106 | 583711 | 0.0006 | 0.0313 | 0.0010 | 0.0006 | 0.0007 | 0.0167 |
| swapTCforTP | 100 | 602113 | 796538 | 1112599 | 0.0020 | 0.0596 | 0.0026 | 0.0015 | 0.0017 | 0.0427 |
| redeemTCandTP | 100 | 385314 | 559100 | 921091 | 0.0013 | 0.0493 | 0.0018 | 0.0010 | 0.0012 | 0.0299 |
| mintTCandTP | 100 | 180952 | 323429 | 577736 | 0.0006 | 0.0309 | 0.0011 | 0.0006 | 0.0007 | 0.0173 |
| swapTPforTP | 100 | 194521 | 404731 | 978316 | 0.0006 | 0.0524 | 0.0013 | 0.0007 | 0.0009 | 0.0217 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 2; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 460709 | 494835 | 573415 | 0.0015 | 0.0307 | 0.0016 | 0.0009 | 0.0011 | 0.0265 |
| redeemTC | 100 | 1012318 | 1039692 | 1062500 | 0.0033 | 0.0569 | 0.0034 | 0.0019 | 0.0023 | 0.0557 |
| mintTP | 100 | 1026012 | 1067526 | 1100365 | 0.0034 | 0.0589 | 0.0035 | 0.0020 | 0.0023 | 0.0572 |
| redeemTP | 100 | 506434 | 534206 | 567890 | 0.0017 | 0.0304 | 0.0018 | 0.0010 | 0.0012 | 0.0286 |
| swapTPforTC | 100 | 565105 | 601699 | 617726 | 0.0019 | 0.0331 | 0.0020 | 0.0011 | 0.0013 | 0.0322 |
| swapTCforTP | 100 | 1210458 | 1239335 | 1263318 | 0.0040 | 0.0677 | 0.0041 | 0.0023 | 0.0027 | 0.0664 |
| redeemTCandTP | 100 | 959669 | 995164 | 1017871 | 0.0032 | 0.0545 | 0.0033 | 0.0018 | 0.0022 | 0.0533 |
| mintTCandTP | 100 | 567390 | 596976 | 651686 | 0.0019 | 0.0349 | 0.0020 | 0.0011 | 0.0013 | 0.0320 |
| swapTPforTP | 100 | 507847 | 783047 | 1141045 | 0.0017 | 0.0611 | 0.0026 | 0.0014 | 0.0017 | 0.0419 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 2; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 131608 | 253365 | 512592 | 0.0004 | 0.0275 | 0.0008 | 0.0005 | 0.0006 | 0.0136 |
| redeemTC | 100 | 541444 | 722596 | 1064659 | 0.0018 | 0.0570 | 0.0024 | 0.0013 | 0.0016 | 0.0387 |
| mintTP | 100 | 529052 | 716068 | 1086404 | 0.0017 | 0.0582 | 0.0024 | 0.0013 | 0.0016 | 0.0384 |
| redeemTP | 100 | 173531 | 300826 | 547002 | 0.0006 | 0.0293 | 0.0010 | 0.0006 | 0.0007 | 0.0161 |
| swapTPforTC | 100 | 189262 | 334135 | 617358 | 0.0006 | 0.0331 | 0.0011 | 0.0006 | 0.0007 | 0.0179 |
| swapTCforTP | 100 | 699977 | 903284 | 1269584 | 0.0023 | 0.0680 | 0.0030 | 0.0017 | 0.0020 | 0.0484 |
| redeemTCandTP | 100 | 433783 | 625613 | 1018030 | 0.0014 | 0.0545 | 0.0021 | 0.0011 | 0.0014 | 0.0335 |
| mintTCandTP | 100 | 199377 | 343705 | 611015 | 0.0007 | 0.0327 | 0.0011 | 0.0006 | 0.0008 | 0.0184 |
| swapTPforTP | 100 | 242046 | 446356 | 1101269 | 0.0008 | 0.0590 | 0.0015 | 0.0008 | 0.0010 | 0.0239 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 3; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 581335 | 632491 | 726767 | 0.0019 | 0.0389 | 0.0021 | 0.0012 | 0.0014 | 0.0339 |
| redeemTC | 100 | 841410 | 888776 | 914869 | 0.0028 | 0.0490 | 0.0029 | 0.0016 | 0.0020 | 0.0476 |
| mintTP | 100 | 1358903 | 1399788 | 1449323 | 0.0045 | 0.0776 | 0.0046 | 0.0026 | 0.0031 | 0.0750 |
| redeemTP | 100 | 484433 | 521210 | 558868 | 0.0016 | 0.0299 | 0.0017 | 0.0010 | 0.0011 | 0.0279 |
| swapTPforTC | 100 | 776335 | 822757 | 858262 | 0.0026 | 0.0460 | 0.0027 | 0.0015 | 0.0018 | 0.0441 |
| swapTCforTP | 100 | 1030609 | 1072246 | 1106461 | 0.0034 | 0.0593 | 0.0035 | 0.0020 | 0.0024 | 0.0574 |
| redeemTCandTP | 100 | 1278487 | 1320287 | 1344322 | 0.0042 | 0.0720 | 0.0043 | 0.0024 | 0.0029 | 0.0707 |
| mintTCandTP | 100 | 548446 | 585507 | 620112 | 0.0018 | 0.0332 | 0.0019 | 0.0011 | 0.0013 | 0.0314 |
| swapTPforTP | 100 | 715375 | 1020028 | 1436560 | 0.0024 | 0.0769 | 0.0034 | 0.0019 | 0.0022 | 0.0546 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 3; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 152083 | 310197 | 2119207 | 0.0005 | 0.1135 | 0.0010 | 0.0006 | 0.0007 | 0.0166 |
| redeemTC | 100 | 597864 | 800917 | 976644 | 0.0020 | 0.0523 | 0.0026 | 0.0015 | 0.0018 | 0.0429 |
| mintTP | 100 | 489591 | 814435 | 1428486 | 0.0016 | 0.0765 | 0.0027 | 0.0015 | 0.0018 | 0.0436 |
| redeemTP | 100 | 209738 | 335996 | 538716 | 0.0007 | 0.0289 | 0.0011 | 0.0006 | 0.0007 | 0.0180 |
| swapTPforTC | 100 | 217263 | 397480 | 845226 | 0.0007 | 0.0453 | 0.0013 | 0.0007 | 0.0009 | 0.0213 |
| swapTCforTP | 100 | 738502 | 1024800 | 1173958 | 0.0024 | 0.0629 | 0.0034 | 0.0019 | 0.0023 | 0.0549 |
| redeemTCandTP | 100 | 453411 | 730161 | 1341953 | 0.0015 | 0.0719 | 0.0024 | 0.0013 | 0.0016 | 0.0391 |
| mintTCandTP | 100 | 251851 | 388328 | 602887 | 0.0008 | 0.0323 | 0.0013 | 0.0007 | 0.0009 | 0.0208 |
| swapTPforTP | 100 | 255290 | 542543 | 1428838 | 0.0008 | 0.0765 | 0.0018 | 0.0010 | 0.0012 | 0.0291 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 3; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 638464 | 689795 | 789803 | 0.0021 | 0.0423 | 0.0023 | 0.0013 | 0.0015 | 0.0369 |
| redeemTC | 100 | 1029954 | 1070065 | 1098612 | 0.0034 | 0.0588 | 0.0035 | 0.0020 | 0.0023 | 0.0573 |
| mintTP | 100 | 1612362 | 1661070 | 1698276 | 0.0053 | 0.0910 | 0.0055 | 0.0030 | 0.0036 | 0.0890 |
| redeemTP | 100 | 529904 | 563303 | 598804 | 0.0017 | 0.0321 | 0.0019 | 0.0010 | 0.0012 | 0.0302 |
| swapTPforTC | 100 | 834203 | 882370 | 919740 | 0.0027 | 0.0493 | 0.0029 | 0.0016 | 0.0019 | 0.0473 |
| swapTCforTP | 100 | 1234952 | 1278770 | 1313774 | 0.0041 | 0.0704 | 0.0042 | 0.0023 | 0.0028 | 0.0685 |
| redeemTCandTP | 100 | 1467605 | 1523177 | 1549318 | 0.0048 | 0.0830 | 0.0050 | 0.0028 | 0.0033 | 0.0816 |
| mintTCandTP | 100 | 591150 | 626986 | 666112 | 0.0019 | 0.0357 | 0.0021 | 0.0011 | 0.0014 | 0.0336 |
| swapTPforTP | 100 | 752558 | 1155718 | 1698516 | 0.0025 | 0.0910 | 0.0038 | 0.0021 | 0.0025 | 0.0619 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 3; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 163091 | 367986 | 4244058 | 0.0005 | 0.2273 | 0.0012 | 0.0007 | 0.0008 | 0.0197 |
| redeemTC | 100 | 762731 | 985929 | 1115517 | 0.0025 | 0.0597 | 0.0032 | 0.0018 | 0.0022 | 0.0528 |
| mintTP | 100 | 597065 | 978907 | 1681958 | 0.0020 | 0.0901 | 0.0032 | 0.0018 | 0.0021 | 0.0524 |
| redeemTP | 100 | 234558 | 370836 | 581789 | 0.0008 | 0.0312 | 0.0012 | 0.0007 | 0.0008 | 0.0199 |
| swapTPforTC | 100 | 232119 | 428636 | 897271 | 0.0008 | 0.0481 | 0.0014 | 0.0008 | 0.0009 | 0.0230 |
| swapTCforTP | 100 | 927750 | 1255960 | 1465277 | 0.0031 | 0.0785 | 0.0041 | 0.0023 | 0.0028 | 0.0673 |
| redeemTCandTP | 100 | 549399 | 849901 | 1534342 | 0.0018 | 0.0822 | 0.0028 | 0.0016 | 0.0019 | 0.0455 |
| mintTCandTP | 100 | 269685 | 424997 | 645960 | 0.0009 | 0.0346 | 0.0014 | 0.0008 | 0.0009 | 0.0228 |
| swapTPforTP | 100 | 259123 | 629051 | 1672248 | 0.0009 | 0.0896 | 0.0021 | 0.0012 | 0.0014 | 0.0337 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 3; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 696331 | 745693 | 847669 | 0.0023 | 0.0454 | 0.0025 | 0.0014 | 0.0016 | 0.0399 |
| redeemTC | 100 | 1202664 | 1252676 | 1280200 | 0.0040 | 0.0686 | 0.0041 | 0.0023 | 0.0028 | 0.0671 |
| mintTP | 100 | 1882512 | 1922951 | 1963284 | 0.0062 | 0.1051 | 0.0063 | 0.0035 | 0.0042 | 0.1030 |
| redeemTP | 100 | 572609 | 605060 | 645013 | 0.0019 | 0.0345 | 0.0020 | 0.0011 | 0.0013 | 0.0324 |
| swapTPforTC | 100 | 891331 | 944210 | 977605 | 0.0029 | 0.0524 | 0.0031 | 0.0017 | 0.0021 | 0.0506 |
| swapTCforTP | 100 | 1440269 | 1486279 | 1516775 | 0.0047 | 0.0812 | 0.0049 | 0.0027 | 0.0033 | 0.0796 |
| redeemTCandTP | 100 | 1668553 | 1729864 | 1759325 | 0.0055 | 0.0942 | 0.0057 | 0.0032 | 0.0038 | 0.0926 |
| mintTCandTP | 100 | 630428 | 667436 | 708446 | 0.0021 | 0.0379 | 0.0022 | 0.0012 | 0.0015 | 0.0357 |
| swapTPforTP | 100 | 800870 | 1262162 | 1969276 | 0.0026 | 0.1055 | 0.0042 | 0.0023 | 0.0028 | 0.0676 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 3; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 171619 | 373194 | 3556997 | 0.0006 | 0.1905 | 0.0012 | 0.0007 | 0.0008 | 0.0200 |
| redeemTC | 100 | 886023 | 1197470 | 2603582 | 0.0029 | 0.1394 | 0.0039 | 0.0022 | 0.0026 | 0.0641 |
| mintTP | 100 | 636903 | 1127819 | 1946612 | 0.0021 | 0.1043 | 0.0037 | 0.0021 | 0.0025 | 0.0604 |
| redeemTP | 100 | 223342 | 388748 | 624125 | 0.0007 | 0.0334 | 0.0013 | 0.0007 | 0.0009 | 0.0208 |
| swapTPforTC | 100 | 245822 | 443266 | 960590 | 0.0008 | 0.0514 | 0.0015 | 0.0008 | 0.0010 | 0.0237 |
| swapTCforTP | 100 | 1107394 | 1491907 | 1735307 | 0.0036 | 0.0929 | 0.0049 | 0.0027 | 0.0033 | 0.0799 |
| redeemTCandTP | 100 | 641410 | 954729 | 1740662 | 0.0021 | 0.0932 | 0.0031 | 0.0017 | 0.0021 | 0.0511 |
| mintTCandTP | 100 | 255592 | 447543 | 688136 | 0.0008 | 0.0369 | 0.0015 | 0.0008 | 0.0010 | 0.0240 |
| swapTPforTP | 100 | 280555 | 708498 | 1968139 | 0.0009 | 0.1054 | 0.0023 | 0.0013 | 0.0016 | 0.0379 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 3; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 747187 | 805967 | 905167 | 0.0025 | 0.0485 | 0.0027 | 0.0015 | 0.0018 | 0.0432 |
| redeemTC | 100 | 1386650 | 1434882 | 1466102 | 0.0046 | 0.0785 | 0.0047 | 0.0026 | 0.0032 | 0.0768 |
| mintTP | 100 | 2150690 | 2186018 | 2229355 | 0.0071 | 0.1194 | 0.0072 | 0.0040 | 0.0048 | 0.1171 |
| redeemTP | 100 | 615313 | 650267 | 687718 | 0.0020 | 0.0368 | 0.0021 | 0.0012 | 0.0014 | 0.0348 |
| swapTPforTC | 100 | 948462 | 997154 | 1033524 | 0.0031 | 0.0554 | 0.0033 | 0.0018 | 0.0022 | 0.0534 |
| swapTCforTP | 100 | 1652142 | 1693168 | 1729918 | 0.0054 | 0.0927 | 0.0056 | 0.0031 | 0.0037 | 0.0907 |
| redeemTCandTP | 100 | 1873387 | 1934009 | 1965115 | 0.0062 | 0.1052 | 0.0064 | 0.0035 | 0.0042 | 0.1036 |
| mintTCandTP | 100 | 676558 | 713351 | 752256 | 0.0022 | 0.0403 | 0.0023 | 0.0013 | 0.0016 | 0.0382 |
| swapTPforTP | 100 | 813264 | 1405204 | 2231550 | 0.0027 | 0.1195 | 0.0046 | 0.0026 | 0.0031 | 0.0753 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 3; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 182039 | 407864 | 4498228 | 0.0006 | 0.2409 | 0.0013 | 0.0007 | 0.0009 | 0.0218 |
| redeemTC | 100 | 1068432 | 1378142 | 1814696 | 0.0035 | 0.0972 | 0.0045 | 0.0025 | 0.0030 | 0.0738 |
| mintTP | 100 | 818550 | 1310659 | 2206993 | 0.0027 | 0.1182 | 0.0043 | 0.0024 | 0.0029 | 0.0702 |
| redeemTP | 100 | 271152 | 411945 | 667566 | 0.0009 | 0.0358 | 0.0014 | 0.0008 | 0.0009 | 0.0221 |
| swapTPforTC | 100 | 264086 | 472913 | 1018090 | 0.0009 | 0.0545 | 0.0016 | 0.0009 | 0.0010 | 0.0253 |
| swapTCforTP | 100 | 1298297 | 1723267 | 1993764 | 0.0043 | 0.1068 | 0.0057 | 0.0032 | 0.0038 | 0.0923 |
| redeemTCandTP | 100 | 730548 | 1091586 | 1960240 | 0.0024 | 0.1050 | 0.0036 | 0.0020 | 0.0024 | 0.0585 |
| mintTCandTP | 100 | 312366 | 471013 | 731736 | 0.0010 | 0.0392 | 0.0016 | 0.0009 | 0.0010 | 0.0252 |
| swapTPforTP | 100 | 291584 | 757545 | 2220811 | 0.0010 | 0.1189 | 0.0025 | 0.0014 | 0.0017 | 0.0406 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 4; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 807337 | 878648 | 999260 | 0.0027 | 0.0535 | 0.0029 | 0.0016 | 0.0019 | 0.0471 |
| redeemTC | 100 | 1050149 | 1095043 | 1125767 | 0.0035 | 0.0603 | 0.0036 | 0.0020 | 0.0024 | 0.0586 |
| mintTP | 100 | 2219375 | 2279349 | 2324365 | 0.0073 | 0.1245 | 0.0075 | 0.0042 | 0.0050 | 0.1221 |
| redeemTP | 100 | 547601 | 586027 | 625987 | 0.0018 | 0.0335 | 0.0019 | 0.0011 | 0.0013 | 0.0314 |
| swapTPforTC | 100 | 1094374 | 1159659 | 1206838 | 0.0036 | 0.0646 | 0.0038 | 0.0021 | 0.0025 | 0.0621 |
| swapTCforTP | 100 | 1276050 | 1317502 | 1345952 | 0.0042 | 0.0721 | 0.0043 | 0.0024 | 0.0029 | 0.0706 |
| redeemTCandTP | 100 | 2005720 | 2067443 | 2094721 | 0.0066 | 0.1122 | 0.0068 | 0.0038 | 0.0045 | 0.1107 |
| mintTCandTP | 100 | 615565 | 650173 | 690000 | 0.0020 | 0.0370 | 0.0021 | 0.0012 | 0.0014 | 0.0348 |
| swapTPforTP | 100 | 1028947 | 1523235 | 2312593 | 0.0034 | 0.1239 | 0.0050 | 0.0028 | 0.0033 | 0.0816 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 4; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 176735 | 796107 | 5798989 | 0.0006 | 0.3106 | 0.0026 | 0.0015 | 0.0017 | 0.0426 |
| redeemTC | 100 | 726120 | 1411258 | 5958660 | 0.0024 | 0.3191 | 0.0046 | 0.0026 | 0.0031 | 0.0756 |
| mintTP | 100 | 695259 | 1421190 | 6064866 | 0.0023 | 0.3248 | 0.0047 | 0.0026 | 0.0031 | 0.0761 |
| redeemTP | 100 | 176900 | 572952 | 4956272 | 0.0006 | 0.2654 | 0.0019 | 0.0010 | 0.0013 | 0.0307 |
| swapTPforTC | 100 | 240759 | 629040 | 3075856 | 0.0008 | 0.1647 | 0.0021 | 0.0012 | 0.0014 | 0.0337 |
| swapTCforTP | 100 | 941577 | 1477638 | 2668874 | 0.0031 | 0.1429 | 0.0049 | 0.0027 | 0.0032 | 0.0791 |
| redeemTCandTP | 100 | 537419 | 1097929 | 2096348 | 0.0018 | 0.1123 | 0.0036 | 0.0020 | 0.0024 | 0.0588 |
| mintTCandTP | 100 | 207992 | 469481 | 1269096 | 0.0007 | 0.0680 | 0.0015 | 0.0009 | 0.0010 | 0.0251 |
| swapTPforTP | 100 | 354303 | 802113 | 2305114 | 0.0012 | 0.1235 | 0.0026 | 0.0015 | 0.0018 | 0.0430 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 4; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 891085 | 962544 | 1078212 | 0.0029 | 0.0577 | 0.0032 | 0.0018 | 0.0021 | 0.0516 |
| redeemTC | 100 | 1295399 | 1333669 | 1366216 | 0.0043 | 0.0732 | 0.0044 | 0.0024 | 0.0029 | 0.0714 |
| mintTP | 100 | 2668694 | 2742139 | 2789146 | 0.0088 | 0.1494 | 0.0090 | 0.0050 | 0.0060 | 0.1469 |
| redeemTP | 100 | 606450 | 640498 | 678118 | 0.0020 | 0.0363 | 0.0021 | 0.0012 | 0.0014 | 0.0343 |
| swapTPforTC | 100 | 1176094 | 1242528 | 1279018 | 0.0039 | 0.0685 | 0.0041 | 0.0023 | 0.0027 | 0.0665 |
| swapTCforTP | 100 | 1542043 | 1587294 | 1617970 | 0.0051 | 0.0867 | 0.0052 | 0.0029 | 0.0035 | 0.0850 |
| redeemTCandTP | 100 | 2354341 | 2424322 | 2455046 | 0.0078 | 0.1315 | 0.0080 | 0.0044 | 0.0053 | 0.1298 |
| mintTCandTP | 100 | 667696 | 699675 | 742657 | 0.0022 | 0.0398 | 0.0023 | 0.0013 | 0.0015 | 0.0375 |
| swapTPforTP | 100 | 1068074 | 1734838 | 2280040 | 0.0035 | 0.1221 | 0.0057 | 0.0032 | 0.0038 | 0.0929 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 4; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 185685 | 860758 | 7258468 | 0.0006 | 0.3887 | 0.0028 | 0.0016 | 0.0019 | 0.0461 |
| redeemTC | 100 | 931070 | 1684014 | 6254766 | 0.0031 | 0.3350 | 0.0055 | 0.0031 | 0.0037 | 0.0902 |
| mintTP | 100 | 900320 | 1784233 | 8367425 | 0.0030 | 0.4481 | 0.0059 | 0.0033 | 0.0039 | 0.0956 |
| redeemTP | 100 | 196262 | 602836 | 5466875 | 0.0006 | 0.2928 | 0.0020 | 0.0011 | 0.0013 | 0.0323 |
| swapTPforTC | 100 | 261761 | 669305 | 4302859 | 0.0009 | 0.2305 | 0.0022 | 0.0012 | 0.0015 | 0.0358 |
| swapTCforTP | 100 | 1201623 | 1917562 | 5978538 | 0.0040 | 0.3202 | 0.0063 | 0.0035 | 0.0042 | 0.1027 |
| redeemTCandTP | 100 | 651757 | 1417428 | 6772790 | 0.0021 | 0.3627 | 0.0047 | 0.0026 | 0.0031 | 0.0759 |
| mintTCandTP | 100 | 226443 | 568930 | 4555121 | 0.0007 | 0.2440 | 0.0019 | 0.0010 | 0.0012 | 0.0305 |
| swapTPforTP | 100 | 317645 | 862969 | 2264628 | 0.0010 | 0.1213 | 0.0028 | 0.0016 | 0.0019 | 0.0462 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 4; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 975205 | 1044721 | 1163436 | 0.0032 | 0.0623 | 0.0034 | 0.0019 | 0.0023 | 0.0560 |
| redeemTC | 100 | 1527220 | 1574466 | 1602355 | 0.0050 | 0.0858 | 0.0052 | 0.0029 | 0.0035 | 0.0843 |
| mintTP | 100 | 3148150 | 3209231 | 3257353 | 0.0104 | 0.1745 | 0.0106 | 0.0059 | 0.0070 | 0.1719 |
| redeemTP | 100 | 655812 | 691856 | 730616 | 0.0022 | 0.0391 | 0.0023 | 0.0013 | 0.0015 | 0.0371 |
| swapTPforTC | 100 | 1257073 | 1326014 | 1353590 | 0.0041 | 0.0725 | 0.0044 | 0.0024 | 0.0029 | 0.0710 |
| swapTCforTP | 100 | 1813729 | 1852949 | 1894559 | 0.0060 | 0.1015 | 0.0061 | 0.0034 | 0.0041 | 0.0992 |
| redeemTCandTP | 100 | 2729466 | 2782627 | 2812031 | 0.0090 | 0.1506 | 0.0092 | 0.0051 | 0.0061 | 0.1490 |
| mintTCandTP | 100 | 719825 | 756058 | 795155 | 0.0024 | 0.0426 | 0.0025 | 0.0014 | 0.0017 | 0.0405 |
| swapTPforTP | 100 | 1118344 | 1945766 | 3239407 | 0.0037 | 0.1735 | 0.0064 | 0.0036 | 0.0043 | 0.1042 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 4; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 197370 | 944256 | 6743783 | 0.0007 | 0.3612 | 0.0031 | 0.0017 | 0.0021 | 0.0506 |
| redeemTC | 100 | 1132946 | 2010840 | 8979443 | 0.0037 | 0.4809 | 0.0066 | 0.0037 | 0.0044 | 0.1077 |
| mintTP | 100 | 946115 | 2049449 | 10041420 | 0.0031 | 0.5378 | 0.0068 | 0.0038 | 0.0045 | 0.1098 |
| redeemTP | 100 | 208741 | 669986 | 7059538 | 0.0007 | 0.3781 | 0.0022 | 0.0012 | 0.0015 | 0.0359 |
| swapTPforTC | 100 | 275628 | 900939 | 8835578 | 0.0009 | 0.4732 | 0.0030 | 0.0016 | 0.0020 | 0.0483 |
| swapTCforTP | 100 | 1443208 | 2288226 | 6546922 | 0.0048 | 0.3506 | 0.0075 | 0.0042 | 0.0050 | 0.1226 |
| redeemTCandTP | 100 | 780572 | 1626224 | 5333125 | 0.0026 | 0.2856 | 0.0054 | 0.0030 | 0.0036 | 0.0871 |
| mintTCandTP | 100 | 236964 | 656800 | 7179382 | 0.0008 | 0.3845 | 0.0022 | 0.0012 | 0.0014 | 0.0352 |
| swapTPforTP | 100 | 359415 | 1150433 | 5190626 | 0.0012 | 0.2780 | 0.0038 | 0.0021 | 0.0025 | 0.0616 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 4; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1053419 | 1125043 | 1243680 | 0.0035 | 0.0666 | 0.0037 | 0.0021 | 0.0025 | 0.0603 |
| redeemTC | 100 | 1765513 | 1811114 | 1847124 | 0.0058 | 0.0989 | 0.0060 | 0.0033 | 0.0040 | 0.0970 |
| mintTP | 100 | 3588608 | 3671090 | 3728654 | 0.0118 | 0.1997 | 0.0121 | 0.0067 | 0.0081 | 0.1966 |
| redeemTP | 100 | 704728 | 742783 | 782747 | 0.0023 | 0.0419 | 0.0024 | 0.0014 | 0.0016 | 0.0398 |
| swapTPforTC | 100 | 1339530 | 1404646 | 1423320 | 0.0044 | 0.0762 | 0.0046 | 0.0026 | 0.0031 | 0.0752 |
| swapTCforTP | 100 | 2074746 | 2123228 | 2163227 | 0.0068 | 0.1159 | 0.0070 | 0.0039 | 0.0047 | 0.1137 |
| redeemTCandTP | 100 | 3066541 | 3141265 | 3173812 | 0.0101 | 0.1700 | 0.0103 | 0.0057 | 0.0069 | 0.1682 |
| mintTCandTP | 100 | 771955 | 805748 | 846917 | 0.0025 | 0.0454 | 0.0027 | 0.0015 | 0.0018 | 0.0432 |
| swapTPforTP | 100 | 1182823 | 2386805 | 3745951 | 0.0039 | 0.2006 | 0.0079 | 0.0044 | 0.0052 | 0.1278 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 4; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 214047 | 1135564 | 6573575 | 0.0007 | 0.3521 | 0.0037 | 0.0021 | 0.0025 | 0.0608 |
| redeemTC | 100 | 1329877 | 2421264 | 10451399 | 0.0044 | 0.5598 | 0.0080 | 0.0044 | 0.0053 | 0.1297 |
| mintTP | 100 | 1253019 | 2348003 | 11143458 | 0.0041 | 0.5968 | 0.0077 | 0.0043 | 0.0052 | 0.1258 |
| redeemTP | 100 | 224042 | 940302 | 8165365 | 0.0007 | 0.4373 | 0.0031 | 0.0017 | 0.0021 | 0.0504 |
| swapTPforTC | 100 | 297635 | 1055310 | 7899634 | 0.0010 | 0.4231 | 0.0035 | 0.0019 | 0.0023 | 0.0565 |
| swapTCforTP | 100 | 1713179 | 2606429 | 6685819 | 0.0056 | 0.3581 | 0.0086 | 0.0048 | 0.0057 | 0.1396 |
| redeemTCandTP | 100 | 873284 | 1861066 | 9758254 | 0.0029 | 0.5226 | 0.0061 | 0.0034 | 0.0041 | 0.0997 |
| mintTCandTP | 100 | 259106 | 683336 | 5347469 | 0.0009 | 0.2864 | 0.0023 | 0.0013 | 0.0015 | 0.0366 |
| swapTPforTP | 100 | 398775 | 1228532 | 2956873 | 0.0013 | 0.1584 | 0.0040 | 0.0022 | 0.0027 | 0.0658 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 5; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1040909 | 1121908 | 1263818 | 0.0034 | 0.0677 | 0.0037 | 0.0021 | 0.0025 | 0.0601 |
| redeemTC | 100 | 1265606 | 1302898 | 1332348 | 0.0042 | 0.0714 | 0.0043 | 0.0024 | 0.0029 | 0.0698 |
| mintTP | 100 | 3283610 | 3345433 | 3406441 | 0.0108 | 0.1824 | 0.0110 | 0.0061 | 0.0073 | 0.1792 |
| redeemTP | 100 | 618673 | 656117 | 693476 | 0.0020 | 0.0371 | 0.0022 | 0.0012 | 0.0014 | 0.0351 |
| swapTPforTC | 100 | 1407982 | 1492977 | 1539460 | 0.0046 | 0.0825 | 0.0049 | 0.0027 | 0.0033 | 0.0800 |
| swapTCforTP | 100 | 1512091 | 1558219 | 1589080 | 0.0050 | 0.0851 | 0.0051 | 0.0029 | 0.0034 | 0.0835 |
| redeemTCandTP | 100 | 2879334 | 2944023 | 2980674 | 0.0095 | 0.1596 | 0.0097 | 0.0054 | 0.0065 | 0.1577 |
| mintTCandTP | 100 | 682686 | 721035 | 757279 | 0.0022 | 0.0406 | 0.0024 | 0.0013 | 0.0016 | 0.0386 |
| swapTPforTP | 100 | 1315726 | 2102050 | 2897444 | 0.0043 | 0.1552 | 0.0069 | 0.0038 | 0.0046 | 0.1126 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 5; Pegs: 2; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 192669 | 1281976 | 6713318 | 0.0006 | 0.3596 | 0.0042 | 0.0023 | 0.0028 | 0.0687 |
| redeemTC | 100 | 861050 | 2020455 | 6363823 | 0.0028 | 0.3408 | 0.0067 | 0.0037 | 0.0044 | 0.1082 |
| mintTP | 100 | 907302 | 2191763 | 7566678 | 0.0030 | 0.4053 | 0.0072 | 0.0040 | 0.0048 | 0.1174 |
| redeemTP | 100 | 180611 | 1002034 | 6807822 | 0.0006 | 0.3646 | 0.0033 | 0.0018 | 0.0022 | 0.0537 |
| swapTPforTC | 100 | 217441 | 1055637 | 4493992 | 0.0007 | 0.2407 | 0.0035 | 0.0019 | 0.0023 | 0.0565 |
| swapTCforTP | 100 | 1120563 | 2208434 | 7076737 | 0.0037 | 0.3790 | 0.0073 | 0.0040 | 0.0048 | 0.1183 |
| redeemTCandTP | 100 | 914087 | 1875643 | 8580793 | 0.0030 | 0.4596 | 0.0062 | 0.0034 | 0.0041 | 0.1005 |
| mintTCandTP | 100 | 212323 | 885324 | 5805298 | 0.0007 | 0.3109 | 0.0029 | 0.0016 | 0.0019 | 0.0474 |
| swapTPforTP | 100 | 330771 | 1343494 | 7175768 | 0.0011 | 0.3843 | 0.0044 | 0.0025 | 0.0030 | 0.0720 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 5; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1145740 | 1230389 | 1371791 | 0.0038 | 0.0735 | 0.0041 | 0.0023 | 0.0027 | 0.0659 |
| redeemTC | 100 | 1554131 | 1598887 | 1629190 | 0.0051 | 0.0873 | 0.0053 | 0.0029 | 0.0035 | 0.0856 |
| mintTP | 100 | 3969215 | 4074065 | 4127885 | 0.0131 | 0.2211 | 0.0134 | 0.0075 | 0.0089 | 0.2182 |
| redeemTP | 100 | 680228 | 717817 | 754664 | 0.0022 | 0.0404 | 0.0024 | 0.0013 | 0.0016 | 0.0384 |
| swapTPforTC | 100 | 1533337 | 1601603 | 1634652 | 0.0051 | 0.0875 | 0.0053 | 0.0029 | 0.0035 | 0.0858 |
| swapTCforTP | 100 | 1838707 | 1889471 | 1932545 | 0.0061 | 0.1035 | 0.0062 | 0.0035 | 0.0041 | 0.1012 |
| redeemTCandTP | 100 | 3422676 | 3501367 | 3539507 | 0.0113 | 0.1896 | 0.0115 | 0.0064 | 0.0077 | 0.1875 |
| mintTCandTP | 100 | 744242 | 782071 | 819572 | 0.0025 | 0.0439 | 0.0026 | 0.0014 | 0.0017 | 0.0419 |
| swapTPforTP | 100 | 1366996 | 2532419 | 4105398 | 0.0045 | 0.2199 | 0.0083 | 0.0046 | 0.0056 | 0.1356 |

POL Executing; Price: $0.122; Average OPs per batch: 10; Collaterals: 5; Pegs: 3; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 203709 | 1695571 | 8556053 | 0.0007 | 0.4582 | 0.0056 | 0.0031 | 0.0037 | 0.0908 |
| redeemTC | 100 | 1114930 | 2604148 | 8046517 | 0.0037 | 0.4310 | 0.0086 | 0.0048 | 0.0057 | 0.1395 |
| mintTP | 100 | 1134238 | 2927087 | 9431336 | 0.0037 | 0.5051 | 0.0096 | 0.0054 | 0.0064 | 0.1568 |
| redeemTP | 100 | 197458 | 1351871 | 9793814 | 0.0007 | 0.5245 | 0.0045 | 0.0025 | 0.0030 | 0.0724 |
| swapTPforTC | 100 | 230061 | 1426124 | 8438759 | 0.0008 | 0.4520 | 0.0047 | 0.0026 | 0.0031 | 0.0764 |
| swapTCforTP | 100 | 1440482 | 2771387 | 8466554 | 0.0047 | 0.4535 | 0.0091 | 0.0051 | 0.0061 | 0.1484 |
| redeemTCandTP | 100 | 1191928 | 2440496 | 9498186 | 0.0039 | 0.5087 | 0.0080 | 0.0045 | 0.0054 | 0.1307 |
| mintTCandTP | 100 | 225520 | 1004651 | 6915098 | 0.0007 | 0.3704 | 0.0033 | 0.0018 | 0.0022 | 0.0538 |
| swapTPforTP | 100 | 316938 | 1670436 | 8325136 | 0.0010 | 0.4459 | 0.0055 | 0.0031 | 0.0037 | 0.0895 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 5; Pegs: 4; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1254817 | 1339152 | 1478099 | 0.0041 | 0.0792 | 0.0044 | 0.0025 | 0.0029 | 0.0717 |
| redeemTC | 100 | 1847220 | 1892734 | 1922356 | 0.0061 | 0.1030 | 0.0062 | 0.0035 | 0.0042 | 0.1014 |
| mintTP | 100 | 4737683 | 4796825 | 4858847 | 0.0156 | 0.2602 | 0.0158 | 0.0088 | 0.0105 | 0.2569 |
| redeemTP | 100 | 741785 | 776596 | 816958 | 0.0024 | 0.0438 | 0.0026 | 0.0014 | 0.0017 | 0.0416 |
| swapTPforTC | 100 | 1624290 | 1705106 | 1732877 | 0.0054 | 0.0928 | 0.0056 | 0.0031 | 0.0037 | 0.0913 |
| swapTCforTP | 100 | 2179819 | 2224630 | 2262275 | 0.0072 | 0.1212 | 0.0073 | 0.0041 | 0.0049 | 0.1191 |
| redeemTCandTP | 100 | 3975374 | 4054071 | 4099216 | 0.0131 | 0.2195 | 0.0134 | 0.0074 | 0.0089 | 0.2171 |
| mintTCandTP | 100 | 805798 | 841526 | 880601 | 0.0027 | 0.0472 | 0.0028 | 0.0015 | 0.0018 | 0.0451 |
| swapTPforTP | 100 | 1409417 | 2930708 | 4185400 | 0.0046 | 0.2242 | 0.0097 | 0.0054 | 0.0064 | 0.1570 |

POL Executing; Price: $0.122; Average OPs per batch: 1; Collaterals: 5; Pegs: 5; Gas adjustment: 1.2
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 27.0gw | $ avgGas @ 15.0gw | $ avgGas @ 18.0gw | $ avgGas @ 439.0gw |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1356883 | 1444984 | 1583299 | 0.0045 | 0.0848 | 0.0048 | 0.0026 | 0.0032 | 0.0774 |
| redeemTC | 100 | 2148943 | 2183711 | 2219519 | 0.0071 | 0.1189 | 0.0072 | 0.0040 | 0.0048 | 0.1170 |
| mintTP | 100 | 5459593 | 5522697 | 5593666 | 0.0180 | 0.2996 | 0.0182 | 0.0101 | 0.0121 | 0.2958 |
| redeemTP | 100 | 803341 | 837969 | 878146 | 0.0026 | 0.0470 | 0.0028 | 0.0015 | 0.0018 | 0.0449 |
| swapTPforTC | 100 | 1731336 | 1810683 | 1832434 | 0.0057 | 0.0981 | 0.0060 | 0.0033 | 0.0040 | 0.0970 |
| swapTCforTP | 100 | 2512051 | 2556099 | 2596583 | 0.0083 | 0.1391 | 0.0084 | 0.0047 | 0.0056 | 0.1369 |
| redeemTCandTP | 100 | 4504135 | 4605698 | 4646734 | 0.0148 | 0.2489 | 0.0152 | 0.0084 | 0.0101 | 0.2467 |
| mintTCandTP | 100 | 870122 | 902048 | 943052 | 0.0029 | 0.0505 | 0.0030 | 0.0017 | 0.0020 | 0.0483 |
| swapTPforTP | 100 | 1503205 | 3132621 | 5550032 | 0.0050 | 0.2972 | 0.0103 | 0.0057 | 0.0069 | 0.1678 |

BNB Queueing; Price: $885; Gas adjustment: 1.1
| (index) | blockGasLimit | estimatedGas | gasLeftPct | min fee @ 0.05gw | $ min | avg fee @ 0.05gw | $ avg | median fee @ 0.05gw | $ median | max fee @ 0.05gw | $ max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100000000 | 256922 | 99.74% | 12846100000000 | 0.0114 | 12846100000000 | 0.0114 | 12846100000000 | 0.0114 | 12846100000000 | 0.0114 |
| redeemTC | 100000000 | 235609 | 99.76% | 11780450000000 | 0.0104 | 11780450000000 | 0.0104 | 11780450000000 | 0.0104 | 11780450000000 | 0.0104 |
| mintTP | 100000000 | 263779 | 99.74% | 13188950000000 | 0.0117 | 13188950000000 | 0.0117 | 13188950000000 | 0.0117 | 13188950000000 | 0.0117 |
| redeemTP | 100000000 | 256346 | 99.74% | 12817300000000 | 0.0113 | 12817300000000 | 0.0113 | 12817300000000 | 0.0113 | 12817300000000 | 0.0113 |
| swapTPforTP | 100000000 | 314252 | 99.69% | 15712600000000 | 0.0139 | 15712600000000 | 0.0139 | 15712600000000 | 0.0139 | 15712600000000 | 0.0139 |
| swapTPforTC | 100000000 | 289172 | 99.71% | 14458600000000 | 0.0128 | 14458600000000 | 0.0128 | 14458600000000 | 0.0128 | 14458600000000 | 0.0128 |
| swapTCforTP | 100000000 | 293548 | 99.71% | 14677400000000 | 0.0130 | 14677400000000 | 0.0130 | 14677400000000 | 0.0130 | 14677400000000 | 0.0130 |
| redeemTCandTP | 100000000 | 290588 | 99.71% | 14529400000000 | 0.0129 | 14529400000000 | 0.0129 | 14529400000000 | 0.0129 | 14529400000000 | 0.0129 |
| mintTCandTP | 100000000 | 264096 | 99.74% | 13204800000000 | 0.0117 | 13204800000000 | 0.0117 | 13204800000000 | 0.0117 | 13204800000000 | 0.0117 |
| execSettlement | 100000000 | 156515 | 99.84% | 7825750000000 | 0.0069 | 7825750000000 | 0.0069 | 7825750000000 | 0.0069 | 7825750000000 | 0.0069 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 2; Pegs: 2; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 328264 | 359942 | 431578 | 0.0145 | 0.0191 | 0.0159 |
| redeemTC | 100 | 580517 | 605641 | 624608 | 0.0257 | 0.0276 | 0.0268 |
| mintTP | 100 | 627904 | 662555 | 698743 | 0.0278 | 0.0309 | 0.0293 |
| redeemTP | 100 | 372717 | 393095 | 428039 | 0.0165 | 0.0189 | 0.0174 |
| swapTPforTC | 100 | 426499 | 456886 | 473722 | 0.0189 | 0.0210 | 0.0202 |
| swapTCforTP | 100 | 717767 | 744739 | 766443 | 0.0318 | 0.0339 | 0.0330 |
| redeemTCandTP | 100 | 617673 | 652217 | 670715 | 0.0273 | 0.0297 | 0.0289 |
| mintTCandTP | 100 | 431395 | 453041 | 502989 | 0.0191 | 0.0223 | 0.0200 |
| swapTPforTP | 100 | 401875 | 515744 | 709960 | 0.0178 | 0.0314 | 0.0228 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 2; Pegs: 2; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 98603 | 182598 | 378024 | 0.0044 | 0.0167 | 0.0081 |
| redeemTC | 100 | 288660 | 400816 | 624608 | 0.0128 | 0.0276 | 0.0177 |
| mintTP | 100 | 286775 | 417985 | 682057 | 0.0127 | 0.0302 | 0.0185 |
| redeemTP | 100 | 120108 | 216301 | 409229 | 0.0053 | 0.0181 | 0.0096 |
| swapTPforTC | 100 | 136519 | 246521 | 473384 | 0.0060 | 0.0209 | 0.0109 |
| swapTCforTP | 100 | 378668 | 513510 | 761519 | 0.0168 | 0.0337 | 0.0227 |
| redeemTCandTP | 100 | 257417 | 391856 | 669557 | 0.0114 | 0.0296 | 0.0173 |
| mintTCandTP | 100 | 138578 | 254088 | 468390 | 0.0061 | 0.0207 | 0.0112 |
| swapTPforTP | 100 | 140334 | 289146 | 694095 | 0.0062 | 0.0307 | 0.0128 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 2; Pegs: 3; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 358768 | 391022 | 464959 | 0.0159 | 0.0206 | 0.0173 |
| redeemTC | 100 | 693010 | 718673 | 739078 | 0.0307 | 0.0327 | 0.0318 |
| mintTP | 100 | 730738 | 765941 | 803557 | 0.0323 | 0.0356 | 0.0339 |
| redeemTP | 100 | 403222 | 424745 | 456006 | 0.0178 | 0.0202 | 0.0188 |
| swapTPforTC | 100 | 454466 | 484617 | 504565 | 0.0201 | 0.0223 | 0.0214 |
| swapTCforTP | 100 | 843424 | 875531 | 899822 | 0.0373 | 0.0398 | 0.0387 |
| redeemTCandTP | 100 | 703395 | 735202 | 757934 | 0.0311 | 0.0335 | 0.0325 |
| mintTCandTP | 100 | 464438 | 485458 | 518043 | 0.0206 | 0.0229 | 0.0215 |
| swapTPforTP | 100 | 423092 | 566478 | 835995 | 0.0187 | 0.0370 | 0.0251 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 2; Pegs: 3; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 106738 | 196933 | 408529 | 0.0047 | 0.0181 | 0.0087 |
| redeemTC | 100 | 355125 | 486617 | 741057 | 0.0157 | 0.0328 | 0.0215 |
| mintTP | 100 | 354020 | 498263 | 788367 | 0.0157 | 0.0349 | 0.0220 |
| redeemTP | 100 | 131248 | 236199 | 440409 | 0.0058 | 0.0195 | 0.0105 |
| swapTPforTC | 100 | 149383 | 266403 | 504227 | 0.0066 | 0.0223 | 0.0118 |
| swapTCforTP | 100 | 459828 | 619982 | 896877 | 0.0203 | 0.0397 | 0.0274 |
| redeemTCandTP | 100 | 299394 | 452130 | 757934 | 0.0132 | 0.0335 | 0.0200 |
| mintTCandTP | 100 | 152159 | 276129 | 499233 | 0.0067 | 0.0221 | 0.0122 |
| swapTPforTP | 100 | 180789 | 357352 | 798520 | 0.0080 | 0.0353 | 0.0158 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 2; Pegs: 4; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 389274 | 421702 | 495127 | 0.0172 | 0.0219 | 0.0187 |
| redeemTC | 100 | 809683 | 834920 | 859488 | 0.0358 | 0.0380 | 0.0369 |
| mintTP | 100 | 837340 | 875210 | 913971 | 0.0371 | 0.0404 | 0.0387 |
| redeemTP | 100 | 436264 | 458429 | 489386 | 0.0193 | 0.0217 | 0.0203 |
| swapTPforTC | 100 | 487846 | 516279 | 535406 | 0.0216 | 0.0237 | 0.0228 |
| swapTCforTP | 100 | 969228 | 1006928 | 1029552 | 0.0429 | 0.0456 | 0.0446 |
| redeemTCandTP | 100 | 789940 | 825202 | 847471 | 0.0350 | 0.0375 | 0.0365 |
| mintTCandTP | 100 | 492404 | 516246 | 548209 | 0.0218 | 0.0243 | 0.0228 |
| swapTPforTP | 100 | 444310 | 635234 | 931610 | 0.0197 | 0.0412 | 0.0281 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 2; Pegs: 4; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 111303 | 198224 | 439372 | 0.0049 | 0.0194 | 0.0088 |
| redeemTC | 100 | 426048 | 562930 | 855531 | 0.0189 | 0.0379 | 0.0249 |
| mintTP | 100 | 413985 | 563107 | 898106 | 0.0183 | 0.0397 | 0.0249 |
| redeemTP | 100 | 144342 | 241290 | 470913 | 0.0064 | 0.0208 | 0.0107 |
| swapTPforTC | 100 | 160904 | 269561 | 535069 | 0.0071 | 0.0237 | 0.0119 |
| swapTCforTP | 100 | 547084 | 710298 | 1022682 | 0.0242 | 0.0453 | 0.0314 |
| redeemTCandTP | 100 | 347277 | 494412 | 844479 | 0.0154 | 0.0374 | 0.0219 |
| mintTCandTP | 100 | 165874 | 276944 | 529737 | 0.0073 | 0.0234 | 0.0123 |
| swapTPforTP | 100 | 197994 | 377946 | 905071 | 0.0088 | 0.0400 | 0.0167 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 2; Pegs: 5; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 422316 | 451928 | 525968 | 0.0187 | 0.0233 | 0.0200 |
| redeemTC | 100 | 924153 | 952040 | 973959 | 0.0409 | 0.0431 | 0.0421 |
| mintTP | 100 | 945511 | 978374 | 1016805 | 0.0418 | 0.0450 | 0.0433 |
| redeemTP | 100 | 466769 | 488386 | 520904 | 0.0207 | 0.0231 | 0.0216 |
| swapTPforTC | 100 | 518013 | 548662 | 584046 | 0.0229 | 0.0258 | 0.0243 |
| swapTCforTP | 100 | 1100772 | 1133070 | 1170094 | 0.0487 | 0.0518 | 0.0501 |
| redeemTCandTP | 100 | 878200 | 913582 | 933532 | 0.0389 | 0.0413 | 0.0404 |
| mintTCandTP | 100 | 520445 | 545575 | 579390 | 0.0230 | 0.0256 | 0.0241 |
| swapTPforTP | 100 | 465527 | 659547 | 1054404 | 0.0206 | 0.0467 | 0.0292 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 2; Pegs: 5; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 118718 | 223109 | 470551 | 0.0053 | 0.0208 | 0.0099 |
| redeemTC | 100 | 502230 | 659104 | 968022 | 0.0222 | 0.0428 | 0.0292 |
| mintTP | 100 | 482002 | 650897 | 996161 | 0.0213 | 0.0441 | 0.0288 |
| redeemTP | 100 | 156539 | 267342 | 502094 | 0.0069 | 0.0222 | 0.0118 |
| swapTPforTC | 100 | 175561 | 295923 | 565912 | 0.0078 | 0.0250 | 0.0131 |
| swapTCforTP | 100 | 629596 | 825163 | 1158862 | 0.0279 | 0.0513 | 0.0365 |
| redeemTCandTP | 100 | 394407 | 563309 | 930202 | 0.0175 | 0.0412 | 0.0249 |
| mintTCandTP | 100 | 179813 | 306427 | 560580 | 0.0080 | 0.0248 | 0.0136 |
| swapTPforTP | 100 | 192024 | 398065 | 982920 | 0.0085 | 0.0435 | 0.0176 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 3; Pegs: 2; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 530691 | 576961 | 668741 | 0.0235 | 0.0296 | 0.0255 |
| redeemTC | 100 | 771293 | 814543 | 838630 | 0.0341 | 0.0371 | 0.0360 |
| mintTP | 100 | 1238709 | 1284959 | 1316499 | 0.0548 | 0.0583 | 0.0569 |
| redeemTP | 100 | 444063 | 476147 | 509758 | 0.0196 | 0.0226 | 0.0211 |
| swapTPforTC | 100 | 709103 | 754999 | 775128 | 0.0314 | 0.0343 | 0.0334 |
| swapTCforTP | 100 | 946559 | 988298 | 1014256 | 0.0419 | 0.0449 | 0.0437 |
| redeemTCandTP | 100 | 1159177 | 1209423 | 1235094 | 0.0513 | 0.0547 | 0.0535 |
| mintTCandTP | 100 | 502742 | 532158 | 584143 | 0.0222 | 0.0258 | 0.0235 |
| swapTPforTP | 100 | 661186 | 963055 | 1316490 | 0.0293 | 0.0583 | 0.0426 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 3; Pegs: 2; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 142291 | 317973 | 2022666 | 0.0063 | 0.0895 | 0.0141 |
| redeemTC | 100 | 536404 | 744450 | 836651 | 0.0237 | 0.0370 | 0.0329 |
| mintTP | 100 | 445485 | 797360 | 1304804 | 0.0197 | 0.0577 | 0.0353 |
| redeemTP | 100 | 195662 | 329129 | 493823 | 0.0087 | 0.0219 | 0.0146 |
| swapTPforTC | 100 | 195969 | 403863 | 774453 | 0.0087 | 0.0343 | 0.0179 |
| swapTCforTP | 100 | 678660 | 951113 | 1083969 | 0.0300 | 0.0480 | 0.0421 |
| redeemTCandTP | 100 | 417827 | 721242 | 1232778 | 0.0185 | 0.0546 | 0.0319 |
| mintTCandTP | 100 | 229538 | 379943 | 552647 | 0.0102 | 0.0245 | 0.0168 |
| swapTPforTP | 100 | 256255 | 534478 | 1317446 | 0.0113 | 0.0583 | 0.0237 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 3; Pegs: 3; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 585596 | 630512 | 723986 | 0.0259 | 0.0320 | 0.0279 |
| redeemTC | 100 | 942146 | 981040 | 1009040 | 0.0417 | 0.0447 | 0.0434 |
| mintTP | 100 | 1476570 | 1521688 | 1560394 | 0.0653 | 0.0690 | 0.0673 |
| redeemTP | 100 | 483208 | 517866 | 551779 | 0.0214 | 0.0244 | 0.0229 |
| swapTPforTC | 100 | 761135 | 809429 | 835520 | 0.0337 | 0.0370 | 0.0358 |
| swapTCforTP | 100 | 1134984 | 1173512 | 1199515 | 0.0502 | 0.0531 | 0.0519 |
| redeemTCandTP | 100 | 1347697 | 1395443 | 1421272 | 0.0596 | 0.0629 | 0.0617 |
| mintTCandTP | 100 | 541888 | 575177 | 610602 | 0.0240 | 0.0270 | 0.0255 |
| swapTPforTP | 100 | 704927 | 1058985 | 1566309 | 0.0312 | 0.0693 | 0.0469 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 3; Pegs: 3; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 149969 | 325001 | 1417274 | 0.0066 | 0.0627 | 0.0144 |
| redeemTC | 100 | 691675 | 917103 | 1191241 | 0.0306 | 0.0527 | 0.0406 |
| mintTP | 100 | 639668 | 913051 | 1538172 | 0.0283 | 0.0681 | 0.0404 |
| redeemTP | 100 | 214860 | 346627 | 532631 | 0.0095 | 0.0236 | 0.0153 |
| swapTPforTC | 100 | 214907 | 405097 | 827160 | 0.0095 | 0.0366 | 0.0179 |
| swapTCforTP | 100 | 844198 | 1159866 | 1333318 | 0.0374 | 0.0590 | 0.0513 |
| redeemTCandTP | 100 | 499736 | 794541 | 1414387 | 0.0221 | 0.0626 | 0.0352 |
| mintTCandTP | 100 | 245192 | 401550 | 591309 | 0.0108 | 0.0262 | 0.0178 |
| swapTPforTP | 100 | 270738 | 574952 | 1543659 | 0.0120 | 0.0683 | 0.0254 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 3; Pegs: 4; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 637966 | 684506 | 777030 | 0.0282 | 0.0344 | 0.0303 |
| redeemTC | 100 | 1108600 | 1149868 | 1175495 | 0.0491 | 0.0520 | 0.0509 |
| mintTP | 100 | 1712664 | 1758488 | 1794624 | 0.0758 | 0.0794 | 0.0778 |
| redeemTP | 100 | 524891 | 556453 | 590924 | 0.0232 | 0.0261 | 0.0246 |
| swapTPforTC | 100 | 810965 | 862983 | 898338 | 0.0359 | 0.0398 | 0.0382 |
| swapTCforTP | 100 | 1324204 | 1362734 | 1389975 | 0.0586 | 0.0615 | 0.0603 |
| redeemTCandTP | 100 | 1539623 | 1585945 | 1607261 | 0.0681 | 0.0711 | 0.0702 |
| mintTCandTP | 100 | 583570 | 613015 | 668895 | 0.0258 | 0.0296 | 0.0271 |
| swapTPforTP | 100 | 739121 | 1149844 | 1809196 | 0.0327 | 0.0801 | 0.0509 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 3; Pegs: 4; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 157865 | 301897 | 773817 | 0.0070 | 0.0342 | 0.0134 |
| redeemTC | 100 | 805107 | 1078418 | 1307107 | 0.0356 | 0.0578 | 0.0477 |
| mintTP | 100 | 649661 | 1014517 | 1795429 | 0.0287 | 0.0794 | 0.0449 |
| redeemTP | 100 | 230379 | 358025 | 572452 | 0.0102 | 0.0253 | 0.0158 |
| swapTPforTC | 100 | 228799 | 397526 | 880541 | 0.0101 | 0.0390 | 0.0176 |
| swapTCforTP | 100 | 1014519 | 1365773 | 1575852 | 0.0449 | 0.0697 | 0.0604 |
| redeemTCandTP | 100 | 585329 | 859224 | 1600283 | 0.0259 | 0.0708 | 0.0380 |
| mintTCandTP | 100 | 265702 | 408485 | 649264 | 0.0118 | 0.0287 | 0.0181 |
| swapTPforTP | 100 | 258319 | 617295 | 1781131 | 0.0114 | 0.0788 | 0.0273 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 3; Pegs: 5; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 687797 | 735800 | 828724 | 0.0304 | 0.0367 | 0.0326 |
| redeemTC | 100 | 1271096 | 1316105 | 1341948 | 0.0562 | 0.0594 | 0.0582 |
| mintTP | 100 | 1947284 | 1998274 | 2036707 | 0.0862 | 0.0901 | 0.0884 |
| redeemTP | 100 | 561499 | 596010 | 630070 | 0.0248 | 0.0279 | 0.0264 |
| swapTPforTC | 100 | 869424 | 916019 | 933587 | 0.0385 | 0.0413 | 0.0405 |
| swapTCforTP | 100 | 1504086 | 1549285 | 1581428 | 0.0666 | 0.0700 | 0.0686 |
| redeemTCandTP | 100 | 1720494 | 1771166 | 1799541 | 0.0761 | 0.0796 | 0.0784 |
| mintTCandTP | 100 | 622716 | 653377 | 689085 | 0.0276 | 0.0305 | 0.0289 |
| swapTPforTP | 100 | 762859 | 1299650 | 2053670 | 0.0338 | 0.0909 | 0.0575 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 3; Pegs: 5; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 167953 | 383058 | 5109848 | 0.0074 | 0.2261 | 0.0170 |
| redeemTC | 100 | 939613 | 1245504 | 1563016 | 0.0416 | 0.0692 | 0.0551 |
| mintTP | 100 | 733820 | 1160720 | 2021198 | 0.0325 | 0.0894 | 0.0514 |
| redeemTP | 100 | 221611 | 385594 | 611598 | 0.0098 | 0.0271 | 0.0171 |
| swapTPforTC | 100 | 243154 | 431625 | 929017 | 0.0108 | 0.0411 | 0.0191 |
| swapTCforTP | 100 | 1173935 | 1562683 | 1830186 | 0.0519 | 0.0810 | 0.0691 |
| redeemTCandTP | 100 | 669644 | 970631 | 1789261 | 0.0296 | 0.0792 | 0.0430 |
| mintTCandTP | 100 | 251505 | 431033 | 662405 | 0.0111 | 0.0293 | 0.0191 |
| swapTPforTP | 100 | 346159 | 726161 | 2032313 | 0.0153 | 0.0899 | 0.0321 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 4; Pegs: 2; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 744797 | 805022 | 913451 | 0.0330 | 0.0404 | 0.0356 |
| redeemTC | 100 | 970994 | 1006026 | 1031953 | 0.0430 | 0.0457 | 0.0445 |
| mintTP | 100 | 2043680 | 2090511 | 2126781 | 0.0904 | 0.0941 | 0.0925 |
| redeemTP | 100 | 505590 | 534121 | 574159 | 0.0224 | 0.0254 | 0.0236 |
| swapTPforTC | 100 | 1000638 | 1062395 | 1093876 | 0.0443 | 0.0484 | 0.0470 |
| swapTCforTP | 100 | 1173891 | 1206085 | 1239389 | 0.0519 | 0.0548 | 0.0534 |
| redeemTCandTP | 100 | 1839787 | 1897858 | 1924700 | 0.0814 | 0.0852 | 0.0840 |
| mintTCandTP | 100 | 564268 | 593714 | 629962 | 0.0250 | 0.0279 | 0.0263 |
| swapTPforTP | 100 | 938479 | 1412869 | 2131669 | 0.0415 | 0.0943 | 0.0625 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 4; Pegs: 2; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 161871 | 645797 | 4976199 | 0.0072 | 0.2202 | 0.0286 |
| redeemTC | 100 | 662487 | 1201346 | 3984301 | 0.0293 | 0.1763 | 0.0532 |
| mintTP | 100 | 580741 | 1204606 | 5850666 | 0.0257 | 0.2589 | 0.0533 |
| redeemTP | 100 | 160388 | 533877 | 4248478 | 0.0071 | 0.1880 | 0.0236 |
| swapTPforTC | 100 | 221283 | 644861 | 5019175 | 0.0098 | 0.2221 | 0.0285 |
| swapTCforTP | 100 | 863250 | 1370639 | 3731091 | 0.0382 | 0.1651 | 0.0607 |
| redeemTCandTP | 100 | 432595 | 1027743 | 4987594 | 0.0191 | 0.2207 | 0.0455 |
| mintTCandTP | 100 | 186271 | 480930 | 4927722 | 0.0082 | 0.2181 | 0.0213 |
| swapTPforTP | 100 | 295916 | 738694 | 4114471 | 0.0131 | 0.1821 | 0.0327 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 4; Pegs: 3; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 819704 | 881721 | 990899 | 0.0363 | 0.0438 | 0.0390 |
| redeemTC | 100 | 1187228 | 1224661 | 1254343 | 0.0525 | 0.0555 | 0.0542 |
| mintTP | 100 | 2451570 | 2513717 | 2559435 | 0.1085 | 0.1133 | 0.1112 |
| redeemTP | 100 | 555913 | 587894 | 619070 | 0.0246 | 0.0274 | 0.0260 |
| swapTPforTC | 100 | 1078761 | 1140415 | 1156244 | 0.0477 | 0.0512 | 0.0505 |
| swapTCforTP | 100 | 1412643 | 1455910 | 1489302 | 0.0625 | 0.0659 | 0.0644 |
| redeemTCandTP | 100 | 2151843 | 2223255 | 2257879 | 0.0952 | 0.0999 | 0.0984 |
| mintTCandTP | 100 | 612054 | 646474 | 681107 | 0.0271 | 0.0301 | 0.0286 |
| swapTPforTP | 100 | 974001 | 1649745 | 2551707 | 0.0431 | 0.1129 | 0.0730 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 4; Pegs: 3; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 173572 | 785157 | 6597391 | 0.0077 | 0.2919 | 0.0347 |
| redeemTC | 100 | 857912 | 1628075 | 6963091 | 0.0380 | 0.3081 | 0.0720 |
| mintTP | 100 | 788955 | 1681195 | 7728164 | 0.0349 | 0.3420 | 0.0744 |
| redeemTP | 100 | 175796 | 639616 | 5000461 | 0.0078 | 0.2213 | 0.0283 |
| swapTPforTC | 100 | 242358 | 767166 | 7143454 | 0.0107 | 0.3161 | 0.0339 |
| swapTCforTP | 100 | 1080529 | 1766267 | 4164019 | 0.0478 | 0.1843 | 0.0782 |
| redeemTCandTP | 100 | 597170 | 1267592 | 6075726 | 0.0264 | 0.2689 | 0.0561 |
| mintTCandTP | 100 | 201143 | 535186 | 3614428 | 0.0089 | 0.1599 | 0.0237 |
| swapTPforTP | 100 | 399032 | 873211 | 2215413 | 0.0177 | 0.0980 | 0.0386 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 4; Pegs: 4; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 894614 | 957170 | 1064795 | 0.0396 | 0.0471 | 0.0424 |
| redeemTC | 100 | 1407798 | 1442728 | 1470514 | 0.0623 | 0.0651 | 0.0638 |
| mintTP | 100 | 2884701 | 2941356 | 2986855 | 0.1276 | 0.1322 | 0.1302 |
| redeemTP | 100 | 601161 | 633744 | 670407 | 0.0266 | 0.0297 | 0.0280 |
| swapTPforTC | 100 | 1152993 | 1213625 | 1237345 | 0.0510 | 0.0548 | 0.0537 |
| swapTCforTP | 100 | 1663475 | 1697091 | 1730806 | 0.0736 | 0.0766 | 0.0751 |
| redeemTCandTP | 100 | 2470967 | 2553142 | 2581653 | 0.1093 | 0.1142 | 0.1130 |
| mintTCandTP | 100 | 659839 | 692060 | 728554 | 0.0292 | 0.0322 | 0.0306 |
| swapTPforTP | 100 | 1024951 | 1787136 | 3052328 | 0.0454 | 0.1351 | 0.0791 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 4; Pegs: 4; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 183860 | 841281 | 4132805 | 0.0081 | 0.1829 | 0.0372 |
| redeemTC | 100 | 1045697 | 1809488 | 6599769 | 0.0463 | 0.2920 | 0.0801 |
| mintTP | 100 | 979565 | 1821564 | 8809166 | 0.0433 | 0.3898 | 0.0806 |
| redeemTP | 100 | 193387 | 651669 | 4940324 | 0.0086 | 0.2186 | 0.0288 |
| swapTPforTC | 100 | 255209 | 777495 | 7061759 | 0.0113 | 0.3125 | 0.0344 |
| swapTCforTP | 100 | 1338045 | 2155326 | 6785802 | 0.0592 | 0.3003 | 0.0954 |
| redeemTCandTP | 100 | 704293 | 1472835 | 5260886 | 0.0312 | 0.2328 | 0.0652 |
| mintTCandTP | 100 | 222278 | 585323 | 2903480 | 0.0098 | 0.1285 | 0.0259 |
| swapTPforTP | 100 | 330698 | 970836 | 2946235 | 0.0146 | 0.1304 | 0.0430 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 4; Pegs: 5; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 965634 | 1030529 | 1140715 | 0.0427 | 0.0505 | 0.0456 |
| redeemTC | 100 | 1618387 | 1659023 | 1688949 | 0.0716 | 0.0747 | 0.0734 |
| mintTP | 100 | 3299613 | 3365575 | 3413671 | 0.1460 | 0.1511 | 0.1489 |
| redeemTP | 100 | 651823 | 682559 | 717856 | 0.0288 | 0.0318 | 0.0302 |
| swapTPforTC | 100 | 1227565 | 1289587 | 1321912 | 0.0543 | 0.0585 | 0.0571 |
| swapTCforTP | 100 | 1900616 | 1947979 | 1978034 | 0.0841 | 0.0875 | 0.0862 |
| redeemTCandTP | 100 | 2818767 | 2879308 | 2916650 | 0.1247 | 0.1291 | 0.1274 |
| mintTCandTP | 100 | 704149 | 737618 | 776340 | 0.0312 | 0.0344 | 0.0326 |
| swapTPforTP | 100 | 1072168 | 2061073 | 3425239 | 0.0474 | 0.1516 | 0.0912 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 4; Pegs: 5; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 202050 | 932961 | 6275028 | 0.0089 | 0.2777 | 0.0413 |
| redeemTC | 100 | 1236649 | 2002761 | 9618927 | 0.0547 | 0.4256 | 0.0886 |
| mintTP | 100 | 1139999 | 2027667 | 7371932 | 0.0504 | 0.3262 | 0.0897 |
| redeemTP | 100 | 212804 | 580540 | 6806798 | 0.0094 | 0.3012 | 0.0257 |
| swapTPforTC | 100 | 273514 | 788133 | 4294843 | 0.0121 | 0.1900 | 0.0349 |
| swapTCforTP | 100 | 1569780 | 2402055 | 3305642 | 0.0695 | 0.1463 | 0.1063 |
| redeemTCandTP | 100 | 806983 | 1653739 | 2904785 | 0.0357 | 0.1285 | 0.0732 |
| mintTCandTP | 100 | 242081 | 571526 | 1060598 | 0.0107 | 0.0469 | 0.0253 |
| swapTPforTP | 100 | 432435 | 1112832 | 2704162 | 0.0191 | 0.1197 | 0.0492 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 5; Pegs: 2; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 951629 | 1030402 | 1155625 | 0.0421 | 0.0511 | 0.0456 |
| redeemTC | 100 | 1153981 | 1197131 | 1221319 | 0.0511 | 0.0540 | 0.0530 |
| mintTP | 100 | 3000924 | 3070041 | 3118829 | 0.1328 | 0.1380 | 0.1358 |
| redeemTP | 100 | 567117 | 596651 | 632811 | 0.0251 | 0.0280 | 0.0264 |
| swapTPforTC | 100 | 1295388 | 1368235 | 1392388 | 0.0573 | 0.0616 | 0.0605 |
| swapTCforTP | 100 | 1387049 | 1429470 | 1461580 | 0.0614 | 0.0647 | 0.0633 |
| redeemTCandTP | 100 | 2608128 | 2699461 | 2743640 | 0.1154 | 0.1214 | 0.1195 |
| mintTCandTP | 100 | 625796 | 657252 | 694027 | 0.0277 | 0.0307 | 0.0291 |
| swapTPforTP | 100 | 1182045 | 1962388 | 3088996 | 0.0523 | 0.1367 | 0.0868 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 5; Pegs: 2; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 174262 | 1066844 | 6791573 | 0.0077 | 0.3005 | 0.0472 |
| redeemTC | 100 | 784564 | 1802766 | 6010004 | 0.0347 | 0.2659 | 0.0798 |
| mintTP | 100 | 840832 | 1866413 | 6528553 | 0.0372 | 0.2889 | 0.0826 |
| redeemTP | 100 | 167941 | 959487 | 6507017 | 0.0074 | 0.2879 | 0.0425 |
| swapTPforTC | 100 | 200739 | 1032559 | 5150394 | 0.0089 | 0.2279 | 0.0457 |
| swapTCforTP | 100 | 1036425 | 2089131 | 5771605 | 0.0459 | 0.2554 | 0.0924 |
| redeemTCandTP | 100 | 828829 | 1771292 | 7305679 | 0.0367 | 0.3233 | 0.0784 |
| mintTCandTP | 100 | 189734 | 839016 | 5452189 | 0.0084 | 0.2413 | 0.0371 |
| swapTPforTP | 100 | 257212 | 1209888 | 6407602 | 0.0114 | 0.2835 | 0.0535 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 5; Pegs: 3; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1053474 | 1127324 | 1257475 | 0.0466 | 0.0556 | 0.0499 |
| redeemTC | 100 | 1422641 | 1463750 | 1491735 | 0.0630 | 0.0660 | 0.0648 |
| mintTP | 100 | 3671875 | 3731823 | 3783854 | 0.1625 | 0.1674 | 0.1651 |
| redeemTP | 100 | 626080 | 658224 | 691776 | 0.0277 | 0.0306 | 0.0291 |
| swapTPforTC | 100 | 1386411 | 1466433 | 1488793 | 0.0613 | 0.0659 | 0.0649 |
| swapTCforTP | 100 | 1682827 | 1734082 | 1763631 | 0.0745 | 0.0780 | 0.0767 |
| redeemTCandTP | 100 | 3127366 | 3210364 | 3245678 | 0.1384 | 0.1436 | 0.1421 |
| mintTCandTP | 100 | 682222 | 714198 | 750937 | 0.0302 | 0.0332 | 0.0316 |
| swapTPforTP | 100 | 1262857 | 2299319 | 3772450 | 0.0559 | 0.1669 | 0.1017 |

BNB Executing; Price: $885; Average OPs per batch: 10; Collaterals: 5; Pegs: 3; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 207568 | 1580626 | 7782611 | 0.0092 | 0.3444 | 0.0699 |
| redeemTC | 100 | 1011597 | 2508543 | 8301238 | 0.0448 | 0.3673 | 0.1110 |
| mintTP | 100 | 1052775 | 2645713 | 8989545 | 0.0466 | 0.3978 | 0.1171 |
| redeemTP | 100 | 178294 | 1321231 | 8900046 | 0.0079 | 0.3938 | 0.0585 |
| swapTPforTC | 100 | 211891 | 1363696 | 7088483 | 0.0094 | 0.3137 | 0.0603 |
| swapTCforTP | 100 | 1299517 | 2611693 | 7163085 | 0.0575 | 0.3170 | 0.1156 |
| redeemTCandTP | 100 | 1089664 | 2105984 | 7565289 | 0.0482 | 0.3348 | 0.0932 |
| mintTCandTP | 100 | 209284 | 758202 | 4227137 | 0.0093 | 0.1871 | 0.0336 |
| swapTPforTP | 100 | 251152 | 1341509 | 6285701 | 0.0111 | 0.2781 | 0.0594 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 5; Pegs: 4; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1149911 | 1225385 | 1351035 | 0.0509 | 0.0598 | 0.0542 |
| redeemTC | 100 | 1691085 | 1734450 | 1766117 | 0.0748 | 0.0782 | 0.0767 |
| mintTP | 100 | 4324277 | 4395590 | 4447968 | 0.1913 | 0.1968 | 0.1945 |
| redeemTP | 100 | 682507 | 713441 | 745665 | 0.0302 | 0.0330 | 0.0316 |
| swapTPforTC | 100 | 1488595 | 1562199 | 1584631 | 0.0659 | 0.0701 | 0.0691 |
| swapTCforTP | 100 | 1989356 | 2039170 | 2073897 | 0.0880 | 0.0918 | 0.0902 |
| redeemTCandTP | 100 | 3653843 | 3717497 | 3748686 | 0.1617 | 0.1659 | 0.1645 |
| mintTCandTP | 100 | 738648 | 769719 | 807363 | 0.0327 | 0.0357 | 0.0341 |
| swapTPforTP | 100 | 1324123 | 2627624 | 4417900 | 0.0586 | 0.1955 | 0.1163 |

BNB Executing; Price: $885; Average OPs per batch: 1; Collaterals: 5; Pegs: 5; Gas adjustment: 1.1
| (index) | count | minGas | avgGas | maxGas | $ Best | $ Worst | $ avgGas @ 0.05gw |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mintTC | 100 | 1247360 | 1321406 | 1451695 | 0.0552 | 0.0642 | 0.0585 |
| redeemTC | 100 | 1959749 | 1999785 | 2034559 | 0.0867 | 0.0900 | 0.0885 |
| mintTP | 100 | 4979987 | 5060677 | 5126937 | 0.2204 | 0.2269 | 0.2239 |
| redeemTP | 100 | 738934 | 769465 | 805305 | 0.0327 | 0.0356 | 0.0340 |
| swapTPforTC | 100 | 1584019 | 1662538 | 1688117 | 0.0701 | 0.0747 | 0.0736 |
| swapTCforTP | 100 | 2292645 | 2341812 | 2375517 | 0.1014 | 0.1051 | 0.1036 |
| redeemTCandTP | 100 | 4148674 | 4224987 | 4262532 | 0.1836 | 0.1886 | 0.1870 |
| mintTCandTP | 100 | 795075 | 825060 | 863789 | 0.0352 | 0.0382 | 0.0365 |
| swapTPforTP | 100 | 1375909 | 2806048 | 5174533 | 0.0609 | 0.2290 | 0.1242 |
