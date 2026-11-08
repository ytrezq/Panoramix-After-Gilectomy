// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title PercentageMath library
/// @notice Optimized version of Aave V3 math library PercentageMath to conduct percentage manipulations:
/// https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/math/PercentageMath.sol
library PercentageMathLib {
    uint256 internal constant PERCENTAGE_FACTOR = 10_000;
    uint256 internal constant HALF_PERCENTAGE_FACTOR = 5000;
    uint256 internal constant MAX_UINT256 = 2 ** 256 - 1;
    uint256 internal constant MAX_UINT256_MINUS_HALF_PERCENTAGE_FACTOR = 2 ** 256 - 1 - 5000;

    /// @notice Executes the bps-based multiplication (x * p), rounded half up.
    /// @param x The value to multiply by the percentage.
    /// @param percentage The percentage of the value to multiply (in bps).
    /// @return y The result of the multiplication.
    function percentMul(uint256 x, uint256 percentage) internal pure returns (uint256 y) {
        // to avoid overflow, value <= (type(uint256).max - HALF_PERCENTAGE_FACTOR) / percentage
        assembly ("memory-safe") {
            if mul(percentage, gt(x, div(MAX_UINT256_MINUS_HALF_PERCENTAGE_FACTOR, percentage))) {
                revert(0, 0)
            }

            y := div(add(mul(x, percentage), HALF_PERCENTAGE_FACTOR), PERCENTAGE_FACTOR)
        }
    }

    /// @notice Executes the bps-based division (x / p), rounded half up.
    /// @param x The value to divide by the percentage.
    /// @param percentage The percentage of the value to divide (in bps).
    /// @return y The result of the division.
    function percentDiv(uint256 x, uint256 percentage) internal pure returns (uint256 y) {
        // 1. Division by 0 if
        //        percentage == 0
        // 2. Overflow if
        //        x * PERCENTAGE_FACTOR + percentage / 2 > type(uint256).max
        //    <=> x > (type(uint256).max - percentage / 2) / PERCENTAGE_FACTOR
        assembly ("memory-safe") {
            y := div(percentage, 2) // Temporary assignment to save gas.

            if iszero(mul(percentage, iszero(gt(x, div(sub(MAX_UINT256, y), PERCENTAGE_FACTOR))))) {
                revert(0, 0)
            }

            y := div(add(mul(PERCENTAGE_FACTOR, x), y), percentage)
        }
    }
}