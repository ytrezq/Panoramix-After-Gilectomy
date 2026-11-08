// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity ^0.8.0;

import {BatchReports} from 'src/deployments/libraries/BatchReports.sol';
import {AaveV4TokenizationSpokeDeployProcedure} from 'src/deployments/procedures/deploy/spoke/AaveV4TokenizationSpokeDeployProcedure.sol';
import {ITokenizationSpoke} from 'src/spoke/interfaces/ITokenizationSpoke.sol';

/// @title AaveV4TokenizationSpokeBatch
/// @author Aave Labs
/// @notice Deploys a TokenizationSpoke instance (proxy + implementation), producing a batch report.
contract AaveV4TokenizationSpokeBatch is AaveV4TokenizationSpokeDeployProcedure {
  BatchReports.TokenizationSpokeBatchReport internal _report;

  /// @dev Constructor.
  /// @param hub_ The address of the Hub the TokenizationSpoke connects to.
  /// @param underlying_ The address of the underlying asset to tokenize.
  /// @param proxyAdminOwner_ The owner of the proxy admin.
  /// @param shareName_ The name of the share token.
  /// @param shareSymbol_ The symbol of the share token.
  /// @param salt_ The CREATE2 salt for deterministic deployment.
  constructor(
    address hub_,
    address underlying_,
    address proxyAdminOwner_,
    string memory shareName_,
    string memory shareSymbol_,
    bytes32 salt_
  ) {
    (
      address tokenizationSpokeProxy,
      address tokenizationSpokeImplementation
    ) = _deployUpgradeableTokenizationSpokeInstance({
        hub: hub_,
        underlying: underlying_,
        proxyAdminOwner: proxyAdminOwner_,
        shareName: shareName_,
        shareSymbol: shareSymbol_,
        salt: salt_
      });

    _report = BatchReports.TokenizationSpokeBatchReport({
      tokenizationSpokeImplementation: tokenizationSpokeImplementation,
      tokenizationSpokeProxy: tokenizationSpokeProxy
    });
  }

  /// @notice Returns the batch deployment report.
  function getReport() external view returns (BatchReports.TokenizationSpokeBatchReport memory) {
    return _report;
  }
}
