// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {IDeployerTrait} from "./base/IDeployerTrait.sol";

/// @title Market configurator factory interface
interface IMarketConfiguratorFactory is IVersion, IDeployerTrait {
    // ------ //
    // EVENTS //
    // ------ //

    event CreateMarketConfigurator(address indexed marketConfigurator, string name);
    event ShutdownMarketConfigurator(address indexed marketConfigurator);

    // ------ //
    // ERRORS //
    // ------ //

    error CallerIsNotCrossChainGovernanceException(address caller);
    error CallerIsNotMarketConfiguratorAdminException(address caller);
    error CantShutdownMarketConfiguratorException(address marketConfigurator);
    error MarketConfiguratorIsAlreadyAddedException(address marketConfigurator);
    error MarketConfiguratorIsAlreadyShutdownException(address marketConfigruator);
    error MarketConfiguratorIsNotRegisteredException(address marketConfigurator);

    // ------- //
    // GETTERS //
    // ------- //

    function isMarketConfigurator(address account) external view returns (bool);
    function getMarketConfigurators() external view returns (address[] memory);
    function getMarketConfigurator(uint256 index) external view returns (address);
    function getNumMarketConfigurators() external view returns (uint256);
    function getShutdownMarketConfigurators() external view returns (address[] memory);

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function createMarketConfigurator(
        address emergencyAdmin,
        address adminFeeTreasury,
        string calldata curatorName,
        bool deployGovernor
    ) external returns (address marketConfigurator);
    function shutdownMarketConfigurator(address marketConfigurator) external;
    function addMarketConfigurator(address marketConfigurator) external;
}
