// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "./interfaces/IBeaconProxyFactory.sol";

/// @title Implementation of IBeaconProxyFactory
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Creates Beacon Proxies to the staking contract implementations
contract BeaconProxyFactory is IBeaconProxyFactory, UpgradeableBeacon {
    /// @dev Implementation contract set in constructor
    /// @notice Implementation contract can be upgraded because it inherits from UpgradeableBeacon
    /// @param _implementation - implementation contract stored in beacon
    constructor(address _implementation) UpgradeableBeacon(_implementation) {
    }

    /// @inheritdoc IBeaconProxyFactory
    function deploy() external override returns (address _proxy) {
        _proxy = address(new BeaconProxy(address(this), new bytes(0)));
    }
}