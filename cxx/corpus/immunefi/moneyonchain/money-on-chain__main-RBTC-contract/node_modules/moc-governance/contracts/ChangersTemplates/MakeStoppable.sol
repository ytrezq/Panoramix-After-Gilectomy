pragma solidity ^0.5.8;

// This contract is not intended to be used in a production system
// It was designed to be using in a testing environment only

import "../Governance/ChangeContract.sol";

import "../Stopper/Stoppable.sol";

contract MakeStoppable is ChangeContract {
  Stoppable contractToChange;

  constructor(Stoppable _stoppedContractntractToChange) public {
    contractToChange = _stoppedContractntractToChange;
  }

  function execute() external {
    contractToChange.makeStoppable();
  }
}
