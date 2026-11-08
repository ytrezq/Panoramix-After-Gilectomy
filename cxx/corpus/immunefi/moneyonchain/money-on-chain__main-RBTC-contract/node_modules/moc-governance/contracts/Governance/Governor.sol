pragma solidity ^0.5.8;

import "openzeppelin-eth/contracts/ownership/Ownable.sol";
import "openzeppelin-eth/contracts/utils/ReentrancyGuard.sol";

import "./ChangeContract.sol";
import "./IGovernor.sol";

/**
  @title Governor
  @notice Basic governor that handles its governed contracts changes
  through trusting an external address
  */
contract Governor is ReentrancyGuard, Ownable, IGovernor {

  address private currentChangeContract;

  /**
    @notice Function to be called to make the changes in changeContract
    @param changeContract Address of the contract that will execute the changes
   */
  function executeChange(ChangeContract changeContract) external {
    _executeChange(changeContract);
  }


  /**
    @notice Returns true if the _changer address is currently authorized to make
    changes within the system
    @param _changer Address of the contract that will be tested
   */
  function isAuthorizedChanger(address _changer) external view returns (bool) {
    return _isAuthorizedChanger(_changer);
  }



  /**
    @notice Function to be called to make the changes in changeContract
    @param changeContract Address of the contract that will execute the changes
   */
  function _executeChange(ChangeContract changeContract) internal nonReentrant onlyOwner {
    enableChangeContract(changeContract);
    changeContract.execute();
    disableChangeContract();
  }

  /**
    @notice Returns true if the _changer address is currently authorized to make
    changes within the system
    @param _changer Address of the contract that will be tested
   */
  function _isAuthorizedChanger(address _changer) internal view returns (bool) {
    return currentChangeContract == _changer;
  }

  /**
    @notice Authorize the changeContract address to make changes
    @param changeContract Address of the contract that will be authorized
   */
  function enableChangeContract(ChangeContract changeContract) internal {
    currentChangeContract = address(changeContract);
  }

  /**
    @notice UNAuthorize the currentChangeContract address to make changes
   */
  function disableChangeContract() internal {
    currentChangeContract = address(0x0);
  }

  // Leave a gap betweeen inherited contracts variables in order to be
  // able to add more variables in them later
  uint256[50] private upgradeGap;
}
