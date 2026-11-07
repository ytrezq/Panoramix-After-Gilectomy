// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IChangeContract } from "../../interfaces/IChangeContract.sol";
import { Governed, IGovernor } from "../../governance/Governed.sol";

/**
  @title GovernanceChangerTemplate
  @notice This contract is a ChangeContract intended to be used with Moc Aeropulus 
  governance system.
 */
contract GovernanceChangerTemplate is IChangeContract {
  Governed public immutable governed;
  IGovernor public immutable newGovernor;

  /** 
    @notice Constructor
    @param governed_ Address of the contract who's Governor we want to change
    @param newGovernor_ Address of the new Governor
  */
  constructor(Governed governed_, IGovernor newGovernor_) {
    governed = governed_;
    newGovernor = newGovernor_;
  }

  /**
    @notice Execute the changes.
    @dev Should be called by the governor, but this contract does not check that explicitly
    because it is not its responsibility in the current architecture
   */
  function execute() external {
    governed.changeGovernor(newGovernor);
  }
}
