// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title BridgeableTokenP_ErrorsLib
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Library exposing all errors link to the BridgeableTokenP contract.
library BridgeableTokenP_ErrorsLib {
    /// @notice Thrown when the amount of token to bridge from the current chain exceed the daily limit.
    error DailyDebitLimitReached();

    /// @notice Thrown when the amount of token to bridge from the current chain exceed the global limit allowed.
    error GlobalDebitLimitReached();

    /// @notice Thrown when the new fees rate exceeds the maximum fees.
    error MaxFeesRateExceeded();

    /// @notice Thrown when in isolate mode the amount to bridge exceed the total amount minted on the current chain.
    error IsolateModeLimitReach();

    /// @notice Thrown when the new globalLimit value exceed `MAX_GLOBAL_LIMIT`.
    error GlobalLimitOverFlow();

    /// @notice Thrown when the msg length is invalid.
    error InvalidMsgLength();

    /// @notice Thrown when the amount of OFT token to swap in principalToken is 0.
    error NothingToSwap();
}
