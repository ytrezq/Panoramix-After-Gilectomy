// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IProxyAuthorization {
    function canUpgradeFrom(address previousImplementation) external view returns (bool);
}
