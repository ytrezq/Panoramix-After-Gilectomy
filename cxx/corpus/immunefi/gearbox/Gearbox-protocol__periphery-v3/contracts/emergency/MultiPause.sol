// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IStateSerializer} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IStateSerializer.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {ACLTrait} from "@gearbox-protocol/core-v3/contracts/traits/ACLTrait.sol";
import {ContractsRegisterTrait} from "@gearbox-protocol/core-v3/contracts/traits/ContractsRegisterTrait.sol";

import {IContractsRegister} from "@gearbox-protocol/permissionless/contracts/interfaces/IContractsRegister.sol";
import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {MarketFactories} from "@gearbox-protocol/permissionless/contracts/interfaces/Types.sol";

import {IPausable} from "../interfaces/IPausable.sol";

/// @title MultiPause
/// @author Gearbox Foundation
/// @notice Allows pausable admins to pause multiple contracts via single call.
///         This contract itself is expected to have the `PAUSABLE_ADMIN` role in the ACL contract.
contract MultiPause is IVersion, IStateSerializer, ACLTrait, ContractsRegisterTrait {
    /// @notice Contract type
    bytes32 public constant override contractType = "MULTI_PAUSE";

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Market configurator address
    address public immutable marketConfigurator;

    /// @notice Constructor
    /// @param marketConfigurator_ Market configurator address
    constructor(address marketConfigurator_)
        ACLTrait(IMarketConfigurator(marketConfigurator_).acl())
        ContractsRegisterTrait(IMarketConfigurator(marketConfigurator_).contractsRegister())
    {
        marketConfigurator = marketConfigurator_;
    }

    /// @notice Empty state serialization
    function serialize() external pure override returns (bytes memory) {}

    /// @notice Pauses given contracts
    /// @dev Reverts if caller is not a pausable admin
    function pauseContracts(address[] calldata contracts) external pausableAdminsOnly {
        uint256 numContracts = contracts.length;
        for (uint256 i; i < numContracts; ++i) {
            _pause(contracts[i]);
        }
    }

    /// @notice Pauses all contracts within all registered markets and credit suites
    /// @dev Reverts if caller is not a pausable admin
    function pauseAllContracts() external pausableAdminsOnly {
        address[] memory pools = IContractsRegister(contractsRegister).getPools();
        uint256 numPools = pools.length;
        for (uint256 i; i < numPools; ++i) {
            _pauseMarket(pools[i]);
        }
    }

    /// @notice Pauses all contracts within a given market and connected credit suites
    /// @dev Reverts if caller is not a pausable admin
    /// @dev Reverts if `pool` is not registered
    function pauseMarket(address pool) external pausableAdminsOnly registeredPoolOnly(pool) {
        _pauseMarket(pool);
    }

    /// @notice Pauses all contracts within a given credit suite
    /// @dev Reverts if caller is not a pausable admin
    /// @dev Reverts if `creditManager` is not registered
    function pauseCreditSuite(address creditManager)
        external
        pausableAdminsOnly
        registeredCreditManagerOnly(creditManager)
    {
        _pauseCreditSuite(creditManager);
    }

    // --------- //
    // INTERNALS //
    // --------- //

    /// @dev Pauses all contracts within a given market and connected credit suites
    function _pauseMarket(address pool) internal {
        MarketFactories memory factories = IMarketConfigurator(marketConfigurator).getMarketFactories(pool);
        _pauseFactoryTargets(factories.poolFactory, pool);
        _pauseFactoryTargets(factories.priceOracleFactory, pool);
        _pauseFactoryTargets(factories.interestRateModelFactory, pool);
        _pauseFactoryTargets(factories.rateKeeperFactory, pool);
        _pauseFactoryTargets(factories.lossPolicyFactory, pool);
        address[] memory creditManagers = IContractsRegister(contractsRegister).getCreditManagers(pool);
        uint256 numCreditManagers = creditManagers.length;
        for (uint256 i; i < numCreditManagers; ++i) {
            _pauseCreditSuite(creditManagers[i]);
        }
    }

    /// @dev Pauses all contracts within a given credit suite
    function _pauseCreditSuite(address creditManager) internal {
        address factory = IMarketConfigurator(marketConfigurator).getCreditFactory(creditManager);
        _pauseFactoryTargets(factory, creditManager);
    }

    /// @dev Pauses all contracts configurable by `factory` in a given market or credit `suite`
    function _pauseFactoryTargets(address factory, address suite) internal {
        address[] memory targets = IMarketConfigurator(marketConfigurator).getFactoryTargets(factory, suite);
        uint256 numTargets = targets.length;
        for (uint256 i; i < numTargets; ++i) {
            _pause(targets[i]);
        }
    }

    /// @dev Pauses `target` if it's pausable and not already paused
    function _pause(address target) internal {
        try IPausable(target).paused() returns (bool paused) {
            if (!paused) try IPausable(target).pause{gas: 30_000}() {} catch {}
        } catch {}
    }
}
