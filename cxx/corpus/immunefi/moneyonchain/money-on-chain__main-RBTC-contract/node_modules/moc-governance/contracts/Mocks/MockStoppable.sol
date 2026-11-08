pragma solidity ^0.5.8;

// This contract is not intended to be used in a production system
// It was designed to be using in a testing environment only

import "../Stopper/Stoppable.sol";

contract MockStoppable is Stoppable {

  address public protectedParam;

  function initialize(address _stopper, IGovernor _governor, bool _startStoppable, address _protectedParam) public initializer {
    super.initialize(_stopper, _governor, _startStoppable);
    protectedParam = _protectedParam;
  }


  function setProtectedParam(address newProtectedParam) public whenNotPaused {
    protectedParam = newProtectedParam;
  }
}
