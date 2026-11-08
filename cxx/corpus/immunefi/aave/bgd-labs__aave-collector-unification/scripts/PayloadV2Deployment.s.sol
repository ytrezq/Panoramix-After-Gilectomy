// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.6.0;

import {Script} from 'forge-std/Script.sol';

import {AaveV2Avalanche, AaveV2AvalancheAssets} from 'aave-address-book/AaveV2Avalanche.sol';
import {AaveV2Polygon, AaveV2PolygonAssets} from 'aave-address-book/AaveV2Polygon.sol';
import {MigrateV2CollectorPayload} from '../src/contracts/payloads/MigrateV2CollectorPayload.sol';

import {ILendingPool as ILendingPoolForInit} from '@aave/core-v2/contracts/interfaces/ILendingPool.sol';
import {IAaveIncentivesController} from '@aave/core-v2/contracts/interfaces/IAaveIncentivesController.sol';
import {AToken} from '@aave/core-v2/contracts/protocol/tokenization/AToken.sol';
import {AaveMigrationCollector} from '../src/contracts/payloads/AaveMigrationCollector.sol';

contract DeployPolygon is Script {
  // it is impossible to import v3 from address-book due to solc versions mismatch
  address constant POLYGON_COLLECTOR = 0xe8599F3cc5D38a9aD6F3684cd5CEa72f10Dbc383;

  function run() external {
    vm.startBroadcast();

    AaveMigrationCollector migrationCollector = new AaveMigrationCollector();
    address[] memory assets = new address[](0);
    migrationCollector.initialize(
      assets,
      AaveV2Polygon.DEFAULT_INCENTIVES_CONTROLLER,
      POLYGON_COLLECTOR
    );

    AToken aTokenImplementation = new AToken();

    // initialise aTokenImpl for security reasons
    aTokenImplementation.initialize(
      ILendingPoolForInit(address(AaveV2Polygon.POOL)),
      POLYGON_COLLECTOR,
      AaveV2PolygonAssets.AAVE_UNDERLYING, // AAVE Token
      IAaveIncentivesController(AaveV2Polygon.DEFAULT_INCENTIVES_CONTROLLER),
      18,
      'Aave Token',
      'AAVE',
      '0x10' // this parameter is not actually used anywhere
    );

    new MigrateV2CollectorPayload(
      address(AaveV2Polygon.POOL),
      address(AaveV2Polygon.POOL_CONFIGURATOR),
      AaveV2Polygon.COLLECTOR,
      POLYGON_COLLECTOR,
      AaveV2Polygon.DEFAULT_INCENTIVES_CONTROLLER,
      address(migrationCollector),
      address(aTokenImplementation)
    );

    vm.stopBroadcast();
  }
}

contract DeployAvalanche is Script {
  // it is impossible to import v3 from address-book due to solc versions mismatch
  address constant AVALANCHE_COLLECTOR = 0x5ba7fd868c40c16f7aDfAe6CF87121E13FC2F7a0;

  function run() external {
    vm.startBroadcast();

    AaveMigrationCollector migrationCollector = new AaveMigrationCollector();

    // initialise aTokenImpl for security reasons
    address[] memory assets = new address[](0);
    migrationCollector.initialize(
      assets,
      AaveV2Avalanche.DEFAULT_INCENTIVES_CONTROLLER,
      AVALANCHE_COLLECTOR
    );

    AToken aTokenImplementation = new AToken();

    // initialise aTokenImpl for security reasons
    aTokenImplementation.initialize(
      ILendingPoolForInit(address(AaveV2Polygon.POOL)),
      AVALANCHE_COLLECTOR,
      AaveV2AvalancheAssets.AAVEe_UNDERLYING, // AAVE Token
      IAaveIncentivesController(AaveV2Avalanche.DEFAULT_INCENTIVES_CONTROLLER),
      18,
      'Aave Token',
      'AAVE',
      '0x10' // this parameter is not actually used anywhere
    );

    new MigrateV2CollectorPayload(
      address(AaveV2Avalanche.POOL),
      address(AaveV2Avalanche.POOL_CONFIGURATOR),
      AaveV2Avalanche.COLLECTOR,
      AVALANCHE_COLLECTOR,
      AaveV2Avalanche.DEFAULT_INCENTIVES_CONTROLLER, // Avalanche v2 Incentives Controller
      address(migrationCollector),
      address(aTokenImplementation)
    );

    vm.stopBroadcast();
  }
}
