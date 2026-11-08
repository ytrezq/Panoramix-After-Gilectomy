// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { PercentageMathLib } from "contracts/libraries/PercentageMathLib.sol";

import { Users } from "./Types.sol";

/// @notice Contract with default values used throughout the tests.
contract Defaults {
    using PercentageMathLib for uint256;

    //----------------------------------------
    // Constants
    //----------------------------------------

    uint256 public constant ONE_DAY_IN_SECONDS = 1 days;
    uint256 public constant INITIAL_BALANCE = 100_000_000e18;
    uint16 public constant DEFAULT_FEE_RATE = 250; // 2.5%
    uint256 public constant DEFAULT_DAILY_CREDIT_LIMIT = 1_000e18;
    uint256 public constant DEFAULT_DAILY_DEBIT_LIMIT = 1_000e18;
    uint256 public constant DEFAULT_GLOBAL_CREDIT_LIMIT = 10_000e18;
    uint256 public constant DEFAULT_GLOBAL_DEBIT_LIMIT = 10_000e18;
    uint32 public constant aEid = 1;
    uint32 public constant bEid = 2;
    //----------------------------------------
    // State variables
    //----------------------------------------

    Users internal users;
}
