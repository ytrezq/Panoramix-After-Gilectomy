// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity ^0.8.0;

import {BatchReports} from 'src/deployments/libraries/BatchReports.sol';
import {AaveV4HubConfiguratorDeployProcedure} from 'src/deployments/procedures/deploy/hub/AaveV4HubConfiguratorDeployProcedure.sol';
import {AaveV4SpokeConfiguratorDeployProcedure} from 'src/deployments/procedures/deploy/spoke/AaveV4SpokeConfiguratorDeployProcedure.sol';

/// @title AaveV4ConfiguratorBatch
/// @author Aave Labs
/// @notice Deploys the HubConfigurator and SpokeConfigurator contracts, producing a batch report.
contract AaveV4ConfiguratorBatch is
  AaveV4HubConfiguratorDeployProcedure,
  AaveV4SpokeConfiguratorDeployProcedure
{
  BatchReports.ConfiguratorBatchReport internal _report;

  /// @dev Constructor.
  /// @param hubConfiguratorAuthority_ The authority for the HubConfigurator.
  /// @param spokeConfiguratorAuthority_ The authority for the SpokeConfigurator.
  /// @param salt_ The CREATE2 salt for deterministic deployment.
  constructor(
    address hubConfiguratorAuthority_,
    address spokeConfiguratorAuthority_,
    bytes32 salt_
  ) {
    address hubConfigurator = _deployHubConfigurator({
      authority: hubConfiguratorAuthority_,
      salt: salt_
    });
    address spokeConfigurator = _deploySpokeConfigurator({
      authority: spokeConfiguratorAuthority_,
      salt: salt_
    });

    _report = BatchReports.ConfiguratorBatchReport({
      hubConfigurator: hubConfigurator,
      spokeConfigurator: spokeConfigurator
    });
  }

  /// @notice Returns the batch deployment report.
  function getReport() external view returns (BatchReports.ConfiguratorBatchReport memory) {
    return _report;
  }
}
