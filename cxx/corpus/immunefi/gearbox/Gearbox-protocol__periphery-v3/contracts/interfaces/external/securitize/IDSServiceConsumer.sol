// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IDSServiceConsumer {
    function REGISTRY_SERVICE() external view returns (uint256);
    function TRUST_SERVICE() external view returns (uint256);

    function getDSService(uint256 serviceId) external view returns (address);
}
