pragma solidity ^0.5.8;

import "../Blockability/Blockable.sol";
import "../Governance/ChangeContract.sol";

/**
  @title Blocker
  @notice This contract is a ChangeContract intended to be used when
  you want to block a Blockable (example: BlockableGovernor )
 */
contract Blocker is ChangeContract {

  Blockable public blockable;
  uint256 public unblockDate;

  /**
    @notice Constructor
    @param _blockable Address of the contract to be blocked
    @param _unblockDate Date that marks when the blockable will be unblocked
  */
  constructor(Blockable _blockable, uint256 _unblockDate) public {
    blockable = _blockable;
    unblockDate = _unblockDate;
  }

  /**
    @notice Execute the changes.
    @dev Should be called by the governor, but this contract does not check that explicitly because it is not its responsability in
    the current architecture
   */
  function execute() external {
    blockable.blockUntil(unblockDate);
  }
}
