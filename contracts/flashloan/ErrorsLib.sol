// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title FlashLoan_ErrorsLib
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Library exposing all errors link to the FlashLoan contract.
library FlashLoan_ErrorsLib {
    /// @notice Thrown when the token is not supported.
    error UnsupportedToken();

    /// @notice Thrown when the amount is too big.
    error TooBigAmount();

    /// @notice Thrown when the new fees rate exceeds the maximum fees.
    error MaxFeesRateExceeded();

    /// @notice Thrown when the return message is invalid.
    error InvalidReturnMessage();
}