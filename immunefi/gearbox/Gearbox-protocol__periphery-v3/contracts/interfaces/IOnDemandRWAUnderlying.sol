// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IRWAUnderlying} from "./base/IRWAUnderlying.sol";

interface IOnDemandRWAUnderlying is IRWAUnderlying {
    // ------ //
    // EVENTS //
    // ------ //

    event SetDepositorStatus(address indexed account, bool allowed);
    event SetPool(address indexed pool);

    // ------ //
    // ERRORS //
    // ------ //

    error AccountIsNotAllowedDepositorException(address account);
    error CallerIsNotMarketConfiguratorAdminException(address caller);
    error InvalidCreditAccountException(address creditAccount);
    error InvalidLiquidityProviderException(address liquidityProvider);
    error InvalidMarketConfiguratorException(address marketConfigurator);
    error InvalidPoolException(address pool);
    error PoolAlreadySetException();
    error PoolNotSetException();

    // --------- //
    // FUNCTIONS //
    // --------- //

    function getLiquidityProvider() external view returns (address);
    function getMarketConfigurator() external view returns (address);
    function getPool() external view returns (address);
    function setPool(address pool) external;
    function getAllowedDepositors() external view returns (address[] memory);
    function isAllowedDepositor(address account) external view returns (bool);
    function setDepositorStatus(address account, bool allowed) external;
}
