# compoundfinance

- Scope: 150 smart-contract assets, explorer addresses on Ethereum, Polygon, Arbitrum, Base, Optimism and Scroll:
  Compound v2 (Comptroller, cTokens cDAI/cUSDC/cETH/...), Compound III per market (cUSDCv3 / cUSDTv3 proxies and Ext,
  Configurator, Comet Factory, Rewards, Bulker, Proxy Admin, Timelock, Bridge Receiver, Governor), the markets'
  collateral and base tokens (USDC, WETH, WBTC, COMP, ARB, OP, ...), and Primacy of Impact. The one GitHub asset is a
  pull request of compound-finance/compound-protocol (#127).
- Copied (default branches): compound-finance/compound-protocol @ master (v2: cTokens, Comptroller, interest-rate
  models, GovernorBravo, Timelock) and compound-finance/comet @ main (Compound III: Comet, CometExt, Configurator,
  factories, CometRewards, bulkers, bridge receivers), the two repositories linked from the page.
- Left out: the collateral and base tokens (third-party contracts: Circle, WETH9, WBTC, ...) and
  trailofbits/publications (audit reports).
- The deployed markets were upgraded over time; the copies are the current heads, not each market's deployed version.
