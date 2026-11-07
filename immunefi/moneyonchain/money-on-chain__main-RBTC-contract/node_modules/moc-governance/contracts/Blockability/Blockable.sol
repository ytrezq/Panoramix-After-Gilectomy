pragma solidity ^0.5.8;

import "zos-lib/contracts/Initializable.sol";

/**
  @title Blockable
  @notice Base contract to be able to define a blockable contract. The blocked contract
  is blocked until a certain date. That date cannot be changed while the contract is blocked so
  it is guaranteed that you will be blocked until that date
  */
contract Blockable is Initializable {

  string constant private NOT_AUTHORIZED_TO_BLOCK = "not_authorized_to_block";
  string constant private BLOCKED = "blocked";
  string constant private THRESHOLD_TOO_LOW = "threshold_too_low";

  uint256 public unblockDate;

  /**
    @notice Disables functions that should be disabled when the governor is blocked
   */
  modifier notBlocked() {
    require(!isBlocked(), BLOCKED);
    _;
  }

  /**
    @notice Returns true if no change can be executed in the current block
   */
  function isBlocked() public view returns (bool) {
    // solium-disable-next-line security/no-block-members
    return now < unblockDate;
  }

  /**
    @notice Initialize the contract with the basic settings
    @dev This initialize replaces the constructor but it is not called automatically.
    It is necessary because of the upgradeability of the contracts
    @param _firstUnblockDate Timestamp of the first threshold that should be passed before the governor is active
      again
   */
  function initialize(uint256 _firstUnblockDate) public initializer {
    unblockDate = _firstUnblockDate;
  }


  /**
    @notice Defines which addresses are authorized to Block and which are not
    @dev Should be defined by subclasses
    @param who Address that is being asked for
   */
  function isAuthorizedToBlock(address who) public view returns(bool);
  /**
    @notice Blocks the governor until unblockAt
    @dev The new threshold should be big enough to block the governor after the tx and the contract should not be blocked, but that is enforced
    in the executeChange function which ALWAYS should be called before calling this function because it is the only one authorizing a changer
    @param newUnblockDate Timestamp of the next threshold that should be passed before the governor is active
      again
   */
  function blockUntil(uint256 newUnblockDate) public notBlocked {
    require(isAuthorizedToBlock(msg.sender), NOT_AUTHORIZED_TO_BLOCK);
    // solium-disable-next-line security/no-block-members
    require(now < newUnblockDate, THRESHOLD_TOO_LOW);
    unblockDate = newUnblockDate;
  }


  // Leave a gap betweeen inherited contracts variables in order to be
  // able to add more variables in them later
  uint256[50] private upgradeGap;
}
