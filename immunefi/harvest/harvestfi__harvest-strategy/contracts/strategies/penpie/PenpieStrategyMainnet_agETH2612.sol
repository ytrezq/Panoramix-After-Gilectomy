//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_agETH2612 is PenpieStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6010676Bc2534652aD1Ef5Fa8073DcF9AD7EBFBe); //agETH Pendle Market
    address rewardPool = address(0x16296859C15289731521F199F0a5f762dF6347d0); //MasterPenpie
    address ageth = address(0xe1B4d34E8754600962Cd944B535180Bd758E6c2e);
    address syageth = address(0xb1B9150f2085f6a553b547099977181CA802752A);
    address pendle = address(0x808507121B80c02388fAd14726482e061B8da827);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      pendle,
      ageth,
      syageth
    );
    rewardTokens = [pendle];
  }
}
