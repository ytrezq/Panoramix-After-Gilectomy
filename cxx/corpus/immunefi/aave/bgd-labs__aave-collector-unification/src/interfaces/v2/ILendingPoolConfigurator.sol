// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.0;

import {ConfiguratorInputTypes} from 'aave-address-book/AaveV2.sol';

interface ILendingPoolConfigurator {
  function updateAToken(ConfiguratorInputTypes.UpdateATokenInput calldata input) external;
}
