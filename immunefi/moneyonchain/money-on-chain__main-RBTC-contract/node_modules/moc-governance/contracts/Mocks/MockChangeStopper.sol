pragma solidity ^0.5.8;

// This contract is not intended to be used in a production system
// It was designed to be using in a testing environment only

import "../Governance/ChangeContract.sol";

import "./MockStoppable.sol";

contract MockChangeStopper is ChangeContract {
  MockStoppable contractToChange;
  address stopper;

  constructor(MockStoppable _stoppedContractntractToChange, address _stopper) public {
    contractToChange = _stoppedContractntractToChange;
    stopper = _stopper;
  }

  function execute() external {
    contractToChange.setStopper(stopper);
  }
}
