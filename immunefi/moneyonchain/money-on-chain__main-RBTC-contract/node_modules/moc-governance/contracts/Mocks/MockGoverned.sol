pragma solidity ^0.5.8;

// This contract is not intended to be used in a production system
// It was designed to be using in a testing environment only

import "../Governance/Governed.sol";

contract MockGoverned is Governed {

  address public protectedParam;


  constructor(address _protectedParam) public {
    protectedParam = _protectedParam;
  }


  function setProtectedParam(address newProtectedParam) public onlyAuthorizedChanger {
    protectedParam = newProtectedParam;
  }
}
