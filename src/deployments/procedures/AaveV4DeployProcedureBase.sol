// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity ^0.8.0;

import {Vm} from 'forge-std/Vm.sol';

/// @title AaveV4DeployProcedureBase
/// @author Aave Labs
/// @notice Base contract for all Aave V4 deployment procedures, providing access to Foundry cheat codes.
contract AaveV4DeployProcedureBase {
  Vm internal constant vm = Vm(address(uint160(uint256(keccak256('hevm cheat code')))));
}
