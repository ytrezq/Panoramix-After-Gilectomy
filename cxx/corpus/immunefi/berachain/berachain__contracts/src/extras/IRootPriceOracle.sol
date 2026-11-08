// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IPriceOracle } from "./IPriceOracle.sol";

/// @title Root price oracle interface
/// @dev Extends IPriceOracle
interface IRootPriceOracle is IPriceOracle {
    /// @notice error thrown when the price is only deriveable from spotOracle
    error UnreliablePrice();

    /// @notice Emitted when the spot oracle is set.
    /// @param spotOracle The new address of the spot oracle.
    event SpotOracleSet(address spotOracle);

    /// @notice Emitted when the pyth oracle is set.
    /// @param pythOracle The new address of the pyth oracle.
    event PythOracleSet(address pythOracle);
}
