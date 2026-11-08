// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title TokenP_EventsLib
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Library exposing all events link to the TokenP contract.
library TokenP_EventsLib {
    /// @notice Event emitted when a new minter is toggled by the Guardian.
    /// @param minter the address of the new minter.
    event MinterToggled(address indexed minter);
}
