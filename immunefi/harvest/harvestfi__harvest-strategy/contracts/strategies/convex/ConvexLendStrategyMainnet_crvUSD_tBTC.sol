// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./ConvexLendStrategy.sol";

contract ConvexLendStrategyMainnet_crvUSD_tBTC is ConvexLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    address lendingVault = address(0xb2b23C87a4B6d1b03Ba603F7C3EB9A81fDC0AAC9);
    address rewardPool = address(0xDdeeADfDA45FD674a95e578DF2b57c98a2B1BF0e);
    address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ConvexLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      lendingVault,
      rewardPool,
      crv,
      328
    );
    rewardTokens = [crv, cvx];
  }
}
