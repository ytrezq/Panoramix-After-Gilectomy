// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import {IGovernor} from "./IGovernor.sol";

/**
  @title Governed
  @notice Base contract to be inherited by governed contracts
  @dev This contract is not usable on its own since it does not have any _productive useful_ behaviour
  The only purpose of this contract is to define some useful modifiers and functions to be used on the
  governance aspect of the child contract
  */
contract Governed {
    /**
      @notice The address of the contract which governs this one
     */
    IGovernor public governor;

    string private constant NOT_AUTHORIZED_CHANGER = "not_authorized_changer";

    /**
      @notice Modifier that protects the function
      @dev You should use this modifier in any function that should be called through
      the governance system
     */
    modifier onlyAuthorizedChanger() {
        require(governor.isAuthorizedChanger(msg.sender), NOT_AUTHORIZED_CHANGER);
        _;
    }

    /**
      @notice Initialize the contract with the basic settings
      @dev This initialize replaces the constructor but it is not called automatically.
      It is necessary because of the upgradeability of the contracts
      @param _governor Governor address
     */
    function _initialize(IGovernor _governor) internal {
        governor = _governor;
    }

    /**
      @notice Change the contract's governor. Should be called through the old governance system
      @param newIGovernor New governor address
     */
    function changeIGovernor(IGovernor newIGovernor) external onlyAuthorizedChanger {
        governor = newIGovernor;
    }

    /**
      @notice This method is used by a change contract to access the storage freely even without a setter.
      @param data the serialized function arguments
     */
    function delegateCallToChanger(bytes calldata data) external onlyAuthorizedChanger returns (bytes memory) {
        address changerContrat = msg.sender;
        (bool success, bytes memory result) = changerContrat.delegatecall(
            abi.encodeWithSignature("impersonate(bytes)", data)
        );
        require(success, "Error in delegate call");
        return result;
    }

    // Leave a gap betweeen inherited contracts variables in order to be
    // able to add more variables in them later
    uint256[50] private upgradeGap;
}
