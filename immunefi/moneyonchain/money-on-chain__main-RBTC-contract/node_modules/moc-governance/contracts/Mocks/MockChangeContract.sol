pragma solidity ^0.5.8;

// This contract is not intended to be used in a production system
// It was designed to be using in a testing environment only

import "../Governance/ChangeContract.sol";

import "./MockGoverned.sol";

contract MockChangeContract is ChangeContract {
  MockGoverned contractToChange;
  address newParam;

  constructor(MockGoverned _contractToChange, address _newParam) public {
    contractToChange = _contractToChange;
    newParam = _newParam;
  }

  function execute() external {
    contractToChange.setProtectedParam(newParam);
  }
}
