# Arbitrum Chain: Harvest Strategy Development

This [Hardhat](https://hardhat.org/) environment is configured to use Mainnet fork by default and provides templates and utilities for strategy development and testing.

## Installation

1. Run `npm install` to install all the dependencies.
2. Sign up on [Alchemy](https://dashboard.alchemyapi.io/signup/). We recommend using Alchemy over Infura to allow for a reproducible
Mainnet fork testing environment as well as efficiency due to caching.
3. Create a file `dev-keys.json`:
  ```
    {
      "alchemyKey": "<your-alchemy-key>"
    }
  ```

## Run

All tests are located under the `test` folder.

1. Run `npx hardhat test [test file location]`: `npx hardhat test ./test/balancer/wsteth-usdc.js` (if for some reason the NodeJS heap runs out of memory, make sure to explicitly increase its size via `export NODE_OPTIONS=--max_old_space_size=4096`). This will produce the following output:
  ```
  Arbitrum Mainnet Balancer wstETH-USDC
Impersonating...
0x6a74649aCFD7822ae8Fb78463a9f2192752E5Aa2
0x0345Bc8EDdbba03E11e366cFb4E2b232b8f1b739
Fetching Underlying at:  0x178E029173417b1F9C8bC16DCeC6f697bC323746
New Vault Deployed:  0xa4B5Ad0ca0E05ea73E59046CBCb6b3641318c9d3
Strategy Deployed:  0xf47FCd7914b24676C78222Af1431f4826B368F30
    Happy path
loop  0
old shareprice:  1000000000000000000
new shareprice:  1000000000000000000
growth:  1
instant APR: 0 %
instant APY: 0 %
loop  1
old shareprice:  1000000000000000000
new shareprice:  1000068403677420556
growth:  1.0000684036774206
instant APR: 26.04926042303911 %
instant APY: 29.74485660521895 %
loop  2
old shareprice:  1000068403677420556
new shareprice:  1000131319321304444
growth:  1.0000629113405168
instant APR: 23.95768699115301 %
instant APY: 27.061149684423057 %
loop  3
old shareprice:  1000131319321304444
new shareprice:  1000193897701257046
growth:  1.0000625701632813
instant APR: 23.827761013559037 %
instant APY: 26.896279294823277 %
loop  4
old shareprice:  1000193897701257046
new shareprice:  1000256321542735812
growth:  1.000062411739986
instant APR: 23.767430782293474 %
instant APY: 26.819795416465155 %
loop  5
old shareprice:  1000256321542735812
new shareprice:  1000318634555811359
growth:  1.0000622970450008
instant APR: 23.723753020397634 %
instant APY: 26.76445146036619 %
loop  6
old shareprice:  1000318634555811359
new shareprice:  1000380840931449184
growth:  1.0000621865608508
instant APR: 23.681678814655715 %
instant APY: 26.711162141078937 %
loop  7
old shareprice:  1000380840931449184
new shareprice:  1000442949039498353
growth:  1.0000620844637442
instant APR: 23.642798534864234 %
instant APY: 26.661937967659497 %
loop  8
old shareprice:  1000442949039498353
new shareprice:  1000479005035224559
growth:  1.0000360400318287
instant APR: 13.724644787553073 %
instant APY: 14.708122498585574 %
loop  9
old shareprice:  1000479005035224559
new shareprice:  1000479005035224559
growth:  1
instant APR: 0 %
instant APY: 0 %
earned!
APR: 18.24131008308575 %
APY: 20.005517445690145 %
      ✔ Farmer should earn money (32947ms)


  1 passing (37s)
  ```

## Develop

Under `contracts/strategies`, there are plenty of examples to choose from in the repository already, therefore, creating a strategy is no longer a complicated task. Copy-pasting existing strategies with minor modifications is acceptable.

Under `contracts/base`, there are existing base interfaces and contracts that can speed up development.

## Contribute

When ready, open a pull request with the following information:
1. Instructions on how to run the test and at which block number
2. A **mainnet fork test output** (like the one above in the README) clearly showing the increases of share price
3. Info about the protocol, including:
   - Live farm page(s)
   - GitHub link(s)
   - Etherscan link(s)
   - Start/end dates for rewards
   - Any limitations (e.g., maximum pool size)
   - Current pool sizes used for liquidation (to make sure they are not too shallow)

   The first few items can be omitted for well-known protocols (such as `curve.fi`).

5. A description of **potential value** for Harvest: why should your strategy be live? High APYs, decent pool sizes, longevity of rewards, well-secured protocols, high-potential collaborations, etc.

A more extensive checklist for assessing protocols and farming opportunities can be found [here](https://www.notion.so/harvestfinance/Farm-ops-check-list-7cd2e0d9da364252ac465cb8a176f0e0)

## Deployment

If your pull request is merged and given a green light for deployment, the Harvest team will take care of on-chain deployment.
