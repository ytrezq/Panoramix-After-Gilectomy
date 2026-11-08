// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity ^0.8.0;

import {BatchReports} from 'src/deployments/libraries/BatchReports.sol';
import {AaveV4AccessManagerEnumerableDeployProcedure} from 'src/deployments/procedures/deploy/AaveV4AccessManagerEnumerableDeployProcedure.sol';

/// @title AaveV4AuthorityBatch
/// @author Aave Labs
/// @notice Deploys the AccessManagerEnumerable contract and creates a batch report.
contract AaveV4AuthorityBatch is AaveV4AccessManagerEnumerableDeployProcedure {
  BatchReports.AuthorityBatchReport internal _report;

  /// @dev Constructor.
  /// @param admin_ The initial admin of the AccessManager.
  /// @param salt_ The CREATE2 salt for deterministic deployment.
  constructor(address admin_, bytes32 salt_) {
    address accessManager = _deployAccessManagerEnumerable(admin_, salt_);
    _report = BatchReports.AuthorityBatchReport({accessManager: accessManager});
  }

  /// @notice Returns the batch deployment report.
  function getReport() external view returns (BatchReports.AuthorityBatchReport memory) {
    return _report;
  }
}
