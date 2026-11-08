// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title TokenP_ErrorsLib
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Library exposing all errors link to the TokenP contract.
library TokenP_ErrorsLib {
    /// @notice Thrown when the amount of token to burn exceeds the allowance.  
    error BurnAmountExceedsAllowance();

    /// @notice Thrown when the caller is not a minter.
    error NotMinter();
}
