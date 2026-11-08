// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev The maximum fees rate in basic point (10%)
uint16 constant MAX_FEE = 10_00;

/// @dev The amount of seconds in a day
uint256 constant DAY_IN_SECONDS = 86400;

/// @dev The maximum global limit allowed
uint256 constant MAX_GLOBAL_LIMIT = uint256(type(int256).max);