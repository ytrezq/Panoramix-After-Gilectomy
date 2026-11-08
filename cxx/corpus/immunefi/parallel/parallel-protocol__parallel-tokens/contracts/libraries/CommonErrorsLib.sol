// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title CommonErrorsLib
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Library exposing all commun errors.
library CommonErrorsLib {
    /// @notice Thrown when the address is zero.
    error AddressZero();

    /// @notice Thrown when the assets are insufficient.
    error InsufficientAssets();
}
