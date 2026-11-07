pragma solidity ^0.4.6;

import "oracles-zeppelin/contracts/ownership/Ownable.sol";

/**
 * Registry of contracts deployed from ICO Wizard.
 */
contract Registry is Ownable {
  mapping (address => address[]) public deployedContracts;

  event Added(address indexed sender, address indexed deployAddress);

  function add(address deployAddress) public {
    deployedContracts[msg.sender].push(deployAddress);
    Added(msg.sender, deployAddress);
  }

  function count(address deployer) constant returns (uint) {
    return deployedContracts[deployer].length;
  }
}
