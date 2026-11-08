pragma solidity ^0.5.8;

// This contract is not intended to be used in a production system
// It was designed to be using in a testing environment only

import "./MockUpgradeable.sol";

contract MockUpgraded is MockUpgradeable {
  bool public initialized2;
  uint256 public thirdVariable;

  modifier initializer2() {
    require(!initialized2, "Already initialized upgraded");
    _;
    initialized2 = true;
  }

  function initialize2() public initializer2 {
    firstVariable = 6;
    thirdVariable = 4;
  }

  function sumOfVars() public view returns (uint256) {
    return super.sumOfVars() + thirdVariable;
  }
}
