// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity ^0.8.0;

import {BatchReports} from 'src/deployments/libraries/BatchReports.sol';
import {AaveV4NativeTokenGatewayDeployProcedure} from 'src/deployments/procedures/deploy/position-manager/AaveV4NativeTokenGatewayDeployProcedure.sol';
import {AaveV4SignatureGatewayDeployProcedure} from 'src/deployments/procedures/deploy/position-manager/AaveV4SignatureGatewayDeployProcedure.sol';

/// @title AaveV4GatewayBatch
/// @author Aave Labs
/// @notice Deploys the NativeTokenGateway and SignatureGateway contracts, producing a batch report.
contract AaveV4GatewayBatch is
  AaveV4NativeTokenGatewayDeployProcedure,
  AaveV4SignatureGatewayDeployProcedure
{
  BatchReports.GatewaysBatchReport internal _report;

  /// @dev Constructor.
  /// @param owner_ The owner of the gateway contracts.
  /// @param nativeWrapper_ The address of the native wrapper token (e.g. WETH).
  /// @param deployNativeTokenGateway_ Whether to deploy the NativeTokenGateway.
  /// @param deploySignatureGateway_ Whether to deploy the SignatureGateway.
  /// @param salt_ The CREATE2 salt for deterministic deployment.
  constructor(
    address owner_,
    address nativeWrapper_,
    bool deployNativeTokenGateway_,
    bool deploySignatureGateway_,
    bytes32 salt_
  ) {
    address nativeGateway;
    address signatureGateway;

    if (deployNativeTokenGateway_) {
      nativeGateway = _deployNativeTokenGateway({
        nativeWrapper: nativeWrapper_,
        owner: owner_,
        salt: salt_
      });
    }
    if (deploySignatureGateway_) {
      signatureGateway = _deploySignatureGateway({owner: owner_, salt: salt_});
    }

    _report = BatchReports.GatewaysBatchReport({
      signatureGateway: signatureGateway,
      nativeGateway: nativeGateway
    });
  }

  /// @notice Returns the batch deployment report.
  function getReport() external view returns (BatchReports.GatewaysBatchReport memory) {
    return _report;
  }
}
