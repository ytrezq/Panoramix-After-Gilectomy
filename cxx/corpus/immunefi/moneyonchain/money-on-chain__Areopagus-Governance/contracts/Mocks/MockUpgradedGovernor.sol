pragma solidity ^0.5.8;

// This contract is not intended to be used in a production system
// It was designed to be using in a testing environment only

import "../Governance/Governor.sol";

contract MockUpgradedGovernor is Governor {
  bool public initialized2;

  function initialize2() public {
    initialized2 = true;
  }

  function enableChangeContract(ChangeContract changeContract) internal {
    require(initialized2, "Not initialized");
    super.enableChangeContract(changeContract);
  }
}
