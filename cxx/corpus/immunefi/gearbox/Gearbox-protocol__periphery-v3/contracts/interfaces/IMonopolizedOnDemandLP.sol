// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOnDemandLiquidityProvider} from "./base/IOnDemandLiquidityProvider.sol";

interface IMonopolizedOnDemandLP is IOnDemandLiquidityProvider {
    // ----- //
    // TYPES //
    // ----- //

    struct Pool {
        address pool;
        address wrappedUnderlying;
        address unwrappedUnderlying;
        uint256 depositAllowance;
        uint256 claimableAmount;
    }

    // ------ //
    // EVENTS //
    // ------ //

    event AddPool(address indexed pool, address indexed wrappedUnderlying, address indexed unwrappedUnderlying);

    // ------ //
    // ERRORS //
    // ------ //

    error CallerIsNotDepositorException(address caller);
    error CallerIsNotMarketConfiguratorAdminException(address caller);
    error InvalidMarketConfiguratorException(address marketConfigurator);
    error UnderlyingAlreadyAddedException(address underlying);

    // --------- //
    // FUNCTIONS //
    // --------- //

    function getMarketConfigurator() external view returns (address);
    function getDepositor() external view returns (address);
    function getPools() external view returns (Pool[] memory);
    function isPool(address pool) external view returns (bool);
    function addPool(address pool) external;
    function claimableAmount(address pool) external view returns (uint256);
    function claim(address pool) external;
}
