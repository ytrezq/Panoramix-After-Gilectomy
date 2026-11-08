// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.0;

import {AToken} from '@aave/core-v2/contracts/protocol/tokenization/AToken.sol';
import {DataTypes, ConfiguratorInputTypes, ILendingPool} from 'aave-address-book/AaveV2.sol';
import {AaveMigrationCollector} from './AaveMigrationCollector.sol';
import {ICollectorController} from '../../interfaces/v2/ICollectorController.sol';
import {ILendingPoolConfigurator} from '../../interfaces/v2/ILendingPoolConfigurator.sol';
import {IInitializableAdminUpgradeabilityProxy} from '../../interfaces/IInitializableAdminUpgradeabilityProxy.sol';

contract MigrateV2CollectorPayload {
  ILendingPool public immutable POOL;
  ILendingPoolConfigurator public immutable POOL_CONFIGURATOR;
  IInitializableAdminUpgradeabilityProxy public immutable COLLECTOR_PROXY;

  address public immutable INCENTIVES_CONTROLLER;
  address public immutable NEW_COLLECTOR;
  address public immutable MIGRATION_COLLECTOR;
  address public immutable ATOKEN_IMPL;

  constructor(
    address pool,
    address poolConfigurator,
    address v2collector,
    address collector,
    address incentivesController,
    address migrationCollector,
    address aTokenImplementation
  ) public {
    POOL = ILendingPool(pool);
    POOL_CONFIGURATOR = ILendingPoolConfigurator(poolConfigurator);
    COLLECTOR_PROXY = IInitializableAdminUpgradeabilityProxy(v2collector);
    NEW_COLLECTOR = collector;
    INCENTIVES_CONTROLLER = incentivesController;
    MIGRATION_COLLECTOR = migrationCollector;
    ATOKEN_IMPL = aTokenImplementation;
  }

  function execute() external {
    address[] memory reserves = POOL.getReservesList();

    address[] memory aTokens = updateATokens(reserves);

    transferAssetsAndClaimRewards(aTokens);
  }

  function updateATokens(address[] memory reserves) internal returns (address[] memory) {
    DataTypes.ReserveData memory reserveData;
    address[] memory aTokens = new address[](reserves.length);

    for (uint256 i = 0; i < reserves.length; i++) {
      reserveData = POOL.getReserveData(reserves[i]);
      AToken aToken = AToken(reserveData.aTokenAddress);
      aTokens[i] = reserveData.aTokenAddress;

      // update implementation of the aToken and re-init
      ConfiguratorInputTypes.UpdateATokenInput memory input = ConfiguratorInputTypes
        .UpdateATokenInput({
          asset: reserves[i],
          treasury: NEW_COLLECTOR,
          incentivesController: address(aToken.getIncentivesController()),
          name: aToken.name(),
          symbol: aToken.symbol(),
          implementation: address(ATOKEN_IMPL),
          params: '0x10' // this parameter is not actually used anywhere
        });

      POOL_CONFIGURATOR.updateAToken(input);
    }

    return aTokens;
  }

  // upgrade collector to the new implementation which will transfer all the assets on the init
  function transferAssetsAndClaimRewards(address[] memory aTokens) internal {
    bytes memory initParams = abi.encodeWithSelector(
      AaveMigrationCollector.initialize.selector,
      aTokens,
      INCENTIVES_CONTROLLER,
      NEW_COLLECTOR
    );

    COLLECTOR_PROXY.upgradeToAndCall(MIGRATION_COLLECTOR, initParams);
  }
}
