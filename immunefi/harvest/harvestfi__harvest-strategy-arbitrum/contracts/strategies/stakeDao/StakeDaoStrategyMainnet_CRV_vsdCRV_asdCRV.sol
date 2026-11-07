// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./StakeDaoStrategy.sol";

contract StakeDaoStrategyMainnet_CRV_vsdCRV_asdCRV is StakeDaoStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x5C959D2c1a49B637Fb988c40d663265F8Bf6d289); // Info -> LP Token address
    address rewardPool = address(0xe535a11f2716C6912d263987326A97D6d3A8a9DA); // Info -> Stake DAO Vault
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    StakeDaoStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      crv, // depositToken
      0, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      3, //nTokens -> total number of deposit tokens
      false // ICurveDeposit_3token add_liquidity
    );
    rewardTokens = [crv];
  }
}
