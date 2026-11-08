pragma solidity ^0.5.8;

import "./Governor.sol";
import "../Blockability/Blockable.sol";

/**
  @title BlockableGovernor
  @notice Basic governor that handles its governed contracts changes
  through trusting an external address and can be blocked until a given threshold
  */
contract BlockableGovernor is Governor, Blockable {

  /**
    @notice Function to be called to make the changes in changeContract
    @param changeContract Address of the contract that will execute the changes
   */
  function executeChange(ChangeContract changeContract) external notBlocked {
    super._executeChange(changeContract);
  }

  /**
    @notice Initialize the contract with the basic settings
    @dev This initialize replaces the constructor but it is not called automatically.
    It is necessary because of the upgradeability of the contracts
    @param _owner Address enabled to determine which changes should be run
    @param _firstUnblockDate Timestamp of the first threshold that should be passed before the governor is active
      again
   */
  function initialize(address _owner, uint256 _firstUnblockDate) public initializer {
    super.initialize(_owner);
    Blockable.initialize(_firstUnblockDate);
  }


  /**
    @notice Defines which addresses are authorized to Block and which are not; in this case, the changes that come through the governor
    @param who Address that is being asked for
   */
  function isAuthorizedToBlock(address who) public view returns(bool) {
    return _isAuthorizedChanger(who);
  }

  // Leave a gap betweeen inherited contracts variables in order to be
  // able to add more variables in them later
  uint256[50] private upgradeGap;
}
