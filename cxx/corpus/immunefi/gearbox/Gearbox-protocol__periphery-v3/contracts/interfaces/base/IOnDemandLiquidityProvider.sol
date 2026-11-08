// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IStateSerializer} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IStateSerializer.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

/// @title  On-demand liquidity provider interface
/// @author Gearbox Foundation
/// @notice Generic interface for a contract that can provide liquidity to pools on demand
/// @dev    Implementations must have type `ON_DEMAND_LP::{POSTFIX}`
interface IOnDemandLiquidityProvider is IVersion, IStateSerializer {
    // ------ //
    // ERRORS //
    // ------ //

    error CallerIsNotUnderlyingTokenException(address caller);
    error InvalidPoolException(address pool);
    error InvalidUnderlyingTokenException(address underlying);
    error PoolAlreadyAddedException(address pool);

    // --------- //
    // FUNCTIONS //
    // --------- //

    function depositAllowance(address pool) external view returns (uint256);
    function deposit(address pool, address creditAccount, uint256 underlyingAmount) external;
}
