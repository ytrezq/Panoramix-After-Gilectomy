// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity ^0.8.0;

import {AaveV4DeployBatchBaseScript} from 'scripts/deploy/AaveV4DeployBatchBase.s.sol';

/// @title AaveV4DeployEthereum
/// @author Aave Labs
/// @notice Ethereum-specific deploy script from which custom deployment scripts can extend.
abstract contract AaveV4DeployEthereum is AaveV4DeployBatchBaseScript {
  /// @dev Constructor.
  constructor() AaveV4DeployBatchBaseScript('ethereum') {}

  function _expectedChainId() internal pure virtual override returns (uint256) {
    return 1;
  }
}
