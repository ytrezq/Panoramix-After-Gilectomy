pragma solidity ^0.5.8;

// This contract is not intended to be used in a production system
// It was designed to be using in a testing environment only

import "zos-lib/contracts/Initializable.sol";

contract MockUpgradeable is Initializable {
  uint256 public firstVariable;
  uint256 public secondVariable;

  function initialize() public initializer {
    firstVariable = 4;
    secondVariable = 5;
  }

  function sumOfVars() public view returns (uint256) {
    return firstVariable + secondVariable;
  }
}
