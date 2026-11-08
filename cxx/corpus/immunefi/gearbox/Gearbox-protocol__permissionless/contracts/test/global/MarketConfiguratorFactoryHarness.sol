// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {MarketConfiguratorFactory} from "../../instance/MarketConfiguratorFactory.sol";

/// @title Market configurator factory harness
/// @notice Exposes internal state manipulation functions for testing
contract MarketConfiguratorFactoryHarness is MarketConfiguratorFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(address addressProvider_) MarketConfiguratorFactory(addressProvider_) {}

    function exposed_addRegisteredConfigurator(address configurator) external {
        _registeredMarketConfiguratorsSet.add(configurator);
    }

    function exposed_removeRegisteredConfigurator(address configurator) external {
        _registeredMarketConfiguratorsSet.remove(configurator);
    }

    function exposed_addShutdownConfigurator(address configurator) external {
        _shutdownMarketConfiguratorsSet.add(configurator);
    }

    function exposed_removeShutdownConfigurator(address configurator) external {
        _shutdownMarketConfiguratorsSet.remove(configurator);
    }
}
