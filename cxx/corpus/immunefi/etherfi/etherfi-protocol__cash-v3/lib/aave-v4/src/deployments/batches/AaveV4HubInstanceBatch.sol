// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity ^0.8.0;

import {BatchReports} from 'src/deployments/libraries/BatchReports.sol';
import {AaveV4HubDeployProcedure} from 'src/deployments/procedures/deploy/hub/AaveV4HubDeployProcedure.sol';
import {AaveV4InterestRateStrategyDeployProcedure} from 'src/deployments/procedures/deploy/hub/AaveV4InterestRateStrategyDeployProcedure.sol';

/// @title AaveV4HubInstanceBatch
/// @author Aave Labs
/// @notice Deploys a Hub (proxy + implementation) and its InterestRateStrategy, producing a batch report.
contract AaveV4HubInstanceBatch is
  AaveV4HubDeployProcedure,
  AaveV4InterestRateStrategyDeployProcedure
{
  BatchReports.HubInstanceBatchReport internal _report;

  /// @dev Constructor.
  /// @param proxyAdminOwner_ The owner of the proxy admin.
  /// @param authority_ The access-control authority for the Hub.
  /// @param hubBytecode_ The creation bytecode of the Hub implementation.
  /// @param salt_ The CREATE2 salt for deterministic deployment.
  constructor(
    address proxyAdminOwner_,
    address authority_,
    bytes memory hubBytecode_,
    bytes32 salt_
  ) {
    (address hubProxy, address hubImplementation) = _deployUpgradeableHubInstance({
      proxyAdminOwner: proxyAdminOwner_,
      authority: authority_,
      hubBytecode: hubBytecode_,
      salt: salt_
    });
    address irStrategy = _deployInterestRateStrategy({hub: hubProxy, salt: salt_});

    _report = BatchReports.HubInstanceBatchReport({
      hubImplementation: hubImplementation,
      hubProxy: hubProxy,
      irStrategy: irStrategy
    });
  }

  /// @notice Returns the batch deployment report.
  function getReport() external view returns (BatchReports.HubInstanceBatchReport memory) {
    return _report;
  }
}
