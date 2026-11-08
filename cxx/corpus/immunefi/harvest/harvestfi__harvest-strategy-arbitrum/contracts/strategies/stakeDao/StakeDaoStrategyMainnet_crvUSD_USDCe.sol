// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./StakeDaoStrategy.sol";

contract StakeDaoStrategyMainnet_crvUSD_USDCe is StakeDaoStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x3aDf984c937FA6846E5a24E0A68521Bdaf767cE1); // Info -> LP Token address
    address rewardPool = address(0x983a16D3eB1b81A806Ac960E506C19960eb21076); // Info -> Stake DAO Vault
    address crvusd = address(0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5);
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    StakeDaoStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      crvusd, // depositToken
      0, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      true //metaPool -> if LP token address == pool address (at curve)
    );
    rewardTokens = [crv];
  }
}
