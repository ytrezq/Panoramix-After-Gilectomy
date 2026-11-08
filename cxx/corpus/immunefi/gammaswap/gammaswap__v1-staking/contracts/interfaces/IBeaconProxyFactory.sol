// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title Interface for Beacon Proxy Factory contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Beacon Proxy Factory creates Beacon Proxies that hold hold the state of the staking contracts
/// @dev There has to be a BeaconProxyFactory for each staking contract implementation
interface IBeaconProxyFactory {
    /// @dev Deploy beacon proxy Contract
    /// @return _beaconProxy address of beacon proxy contract
    function deploy() external returns (address _beaconProxy);
}
