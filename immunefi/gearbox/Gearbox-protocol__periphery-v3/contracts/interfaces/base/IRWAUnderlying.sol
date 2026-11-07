// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IStateSerializer} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IStateSerializer.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

/// @title  RWA underlying interface
/// @author Gearbox Foundation
/// @notice Generic interface for a token wrapper that can be used as underlying in markets with RWA compliance
/// @dev    Implementations must have type `RWA_UNDERLYING::{POSTFIX}`
/// @dev    MUST always convert one-to-one with the underlying token
interface IRWAUnderlying is IVersion, IStateSerializer, IERC4626 {
    // ------ //
    // ERRORS //
    // ------ //

    error CallerIsNotWalletException(address caller, address creditAccount);
    error FrozenCreditAccountException(address creditAccount);
    error InvalidRWAFactoryException(address factory);

    // --------- //
    // FUNCTIONS //
    // --------- //

    function getFactory() external view returns (address);
    function beforeTokenBorrow(address creditAccount, uint256 underlyingAmount) external;
}
