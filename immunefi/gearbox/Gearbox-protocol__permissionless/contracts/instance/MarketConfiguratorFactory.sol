// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IContractsRegister} from "../interfaces/IContractsRegister.sol";
import {IMarketConfigurator} from "../interfaces/IMarketConfigurator.sol";
import {IMarketConfiguratorFactory} from "../interfaces/IMarketConfiguratorFactory.sol";

import {
    AP_CROSS_CHAIN_GOVERNANCE,
    AP_MARKET_CONFIGURATOR,
    AP_MARKET_CONFIGURATOR_FACTORY,
    NO_VERSION_CONTROL
} from "../libraries/ContractLiterals.sol";

import {DeployerTrait} from "../traits/DeployerTrait.sol";

/// @title Market configurator factory
contract MarketConfiguratorFactory is DeployerTrait, IMarketConfiguratorFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_MARKET_CONFIGURATOR_FACTORY;

    /// @dev Set of registered market configurators
    EnumerableSet.AddressSet internal _registeredMarketConfiguratorsSet;

    /// @dev Set of shutdown market configurators
    EnumerableSet.AddressSet internal _shutdownMarketConfiguratorsSet;

    /// @dev Reverts if caller is not cross-chain governance
    modifier onlyCrossChainGovernance() {
        if (msg.sender != _getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE, NO_VERSION_CONTROL)) {
            revert CallerIsNotCrossChainGovernanceException(msg.sender);
        }
        _;
    }

    /// @dev Reverts if `msg.sender` is not the admin of `marketConfigurator`
    modifier onlyMarketConfiguratorAdmin(address marketConfigurator) {
        if (msg.sender != IMarketConfigurator(marketConfigurator).admin()) {
            revert CallerIsNotMarketConfiguratorAdminException(msg.sender);
        }
        _;
    }

    /// @notice Constructor
    /// @param addressProvider_ Address provider contract address
    constructor(address addressProvider_) DeployerTrait(addressProvider_) {}

    // ------- //
    // GETTERS //
    // ------- //

    /// @notice Returns whether `account` is a registered market configurator
    function isMarketConfigurator(address account) external view override returns (bool) {
        return _registeredMarketConfiguratorsSet.contains(account);
    }

    /// @notice Returns all registered market configurators
    function getMarketConfigurators() external view override returns (address[] memory) {
        return _registeredMarketConfiguratorsSet.values();
    }

    /// @notice Returns the market configurator at `index`
    function getMarketConfigurator(uint256 index) external view override returns (address) {
        return _registeredMarketConfiguratorsSet.at(index);
    }

    /// @notice Returns the number of registered market configurators
    function getNumMarketConfigurators() external view override returns (uint256) {
        return _registeredMarketConfiguratorsSet.length();
    }

    /// @notice Returns all shutdown market configurators
    function getShutdownMarketConfigurators() external view override returns (address[] memory) {
        return _shutdownMarketConfiguratorsSet.values();
    }

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    /// @notice Allows anyone to permissionlessly deploy a new market configurator
    /// @param emergencyAdmin Address to set as emergency admin
    /// @param adminFeeTreasury Address to set as the second admin of the fee splitter, with the first one being the
    ///        DAO treasury. If `address(0)`, the splitter is not deployed and all fees will be sent to the treasury.
    /// @param curatorName Risk curator name
    /// @param deployGovernor If true, a governor contract is deployed and set as market configurator's admin.
    ///        `msg.sender` is set as its owner, queue and execution admin, while `emergencyAdmin` is set as veto admin.
    ///        Otherwise, `msg.sender` is set as the admin of the market configurator.
    /// @return marketConfigurator Address of the newly deployed market configurator
    function createMarketConfigurator(
        address emergencyAdmin,
        address adminFeeTreasury,
        string calldata curatorName,
        bool deployGovernor
    ) external override returns (address marketConfigurator) {
        marketConfigurator = _deployLatestPatch({
            contractType: AP_MARKET_CONFIGURATOR,
            minorVersion: 3_10,
            constructorParams: abi.encode(
                addressProvider, msg.sender, emergencyAdmin, adminFeeTreasury, curatorName, deployGovernor
            ),
            salt: bytes32(bytes20(msg.sender))
        });

        _registeredMarketConfiguratorsSet.add(marketConfigurator);
        emit CreateMarketConfigurator(marketConfigurator, curatorName);
    }

    /// @notice Allows the admin of `marketConfigurator` to shut it down
    /// @dev Reverts if caller is not the admin of `marketConfigurator`
    /// @dev Reverts if `marketConfigurator` is not registered or already shutdown
    /// @dev Reverts if `marketConfigurator` has non-shutdown pools
    function shutdownMarketConfigurator(address marketConfigurator)
        external
        override
        onlyMarketConfiguratorAdmin(marketConfigurator)
    {
        if (!_shutdownMarketConfiguratorsSet.add(marketConfigurator)) {
            revert MarketConfiguratorIsAlreadyShutdownException(marketConfigurator);
        }
        if (!_registeredMarketConfiguratorsSet.remove(marketConfigurator)) {
            revert MarketConfiguratorIsNotRegisteredException(marketConfigurator);
        }
        address contractsRegister = IMarketConfigurator(marketConfigurator).contractsRegister();
        if (IContractsRegister(contractsRegister).getPools().length != 0) {
            revert CantShutdownMarketConfiguratorException(marketConfigurator);
        }
        emit ShutdownMarketConfigurator(marketConfigurator);
    }

    /// @notice Allows cross-chain governance to register an externally deployed legacy market configurator
    /// @dev Reverts if caller is not cross-chain governance
    /// @dev Reverts if `marketConfigurator` is already registered or shutdown
    function addMarketConfigurator(address marketConfigurator) external override onlyCrossChainGovernance {
        if (!_registeredMarketConfiguratorsSet.add(marketConfigurator)) {
            revert MarketConfiguratorIsAlreadyAddedException(marketConfigurator);
        }
        if (_shutdownMarketConfiguratorsSet.contains(marketConfigurator)) {
            revert MarketConfiguratorIsAlreadyShutdownException(marketConfigurator);
        }
        emit CreateMarketConfigurator(marketConfigurator, IMarketConfigurator(marketConfigurator).curatorName());
    }
}
