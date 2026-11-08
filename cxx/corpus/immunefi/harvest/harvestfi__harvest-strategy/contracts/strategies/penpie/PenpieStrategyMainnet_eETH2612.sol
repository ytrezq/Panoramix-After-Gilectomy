//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_eETH2612 is PenpieStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x7d372819240D14fB477f17b964f95F33BeB4c704); //eETH Pendle Market
    address rewardPool = address(0x16296859C15289731521F199F0a5f762dF6347d0); //MasterPenpie
    address weeth = address(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
    address syweeth = address(0xAC0047886a985071476a1186bE89222659970d65);
    address pendle = address(0x808507121B80c02388fAd14726482e061B8da827);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      pendle,
      weeth,
      syweeth
    );
    rewardTokens = [pendle];
  }
}
