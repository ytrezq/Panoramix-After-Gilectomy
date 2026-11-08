# benqi

- Scope: 36 smart-contract assets, Avalanche C-Chain addresses (snowtrace): BENQI Core Markets (Unitroller, qiTokens:
  qiAVAX, qiBTC, qiETH, qiUSDC, qiUSDT, qiDAI, qiLINK, qiQi, qisAVAX...), Isolated "Avalanche Ecosystem" Markets
  (Unitroller and qiTokens), JumpRateModel, Maximillion, Pause Guardian, Benqi Dual Oracle, MultiRewardDistributor,
  QI token, sAVAX (StakedAvax) and its reward timelock, veQI and GaugeController, Ignite, PGL / JLP staking proxies,
  QiTokenSaleDistributor; plus the website and app.
- No repository link on the page. Found by web search: Benqi-fi/BENQI-Smart-Contracts @ master (default branch):
  lending (Comptroller, QiToken*, rate models, Maximillion, Chainlink oracle, governance), sAVAX, veQI, PGL staking,
  token sale.
- Recorded by reference only: the repository has no licence file and no package.json, and only 12 of its 51 .sol files
  carry an open SPDX header (MIT 9, GPL-3.0 3; 39 have none), so copy_repo.py did not copy it.
- Not obviously covered: the Isolated Markets, Ignite, MultiRewardDistributor, the Dual Oracle and the JLP staking
  contract (no public repository found; docs.benqi.fi links only the Benqi-fi organisation).
