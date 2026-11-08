//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_weETHs2612 is PenpieStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x40789E8536C668c6A249aF61c81b9dfaC3EB8F32); //weETHs Pendle Market
    address rewardPool = address(0x16296859C15289731521F199F0a5f762dF6347d0); //MasterPenpie
    address weeths = address(0x917ceE801a67f933F2e6b33fC0cD1ED2d5909D88);
    address syweeths = address(0x9e8f10574ACc2c62C6e5d19500CEd39163Da37A9);
    address pendle = address(0x808507121B80c02388fAd14726482e061B8da827);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      pendle,
      weeths,
      syweeths
    );
    rewardTokens = [pendle];
  }
}
