// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import "@openzeppelin/contracts/access/Ownable.sol";
contract AlchemistGate is Ownable {
    mapping(address => mapping( address => bool)) public authorized;

    constructor(address _owner) Ownable(_owner) {}

    function setAuthorization(address _vault, address _to, bool value) external onlyOwner {
        authorized[_vault][_to] = value;
    }
}
