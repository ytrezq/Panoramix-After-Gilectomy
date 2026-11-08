// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Arithmetic library with operations for fixed-point numbers.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/FixedPointMathLib.sol)
library MathLib {
    /// @dev Returns the absolute value of `x`.
    function abs(int256 x) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            z := xor(sar(255, x), add(sar(255, x), x))
        }
    }

    /// @dev Returns the negative value of `x`.
    function neg(uint256 x) internal pure returns (int256 z) {
        assembly ("memory-safe") {
            z := sub(0, x)
        }
    }

    /// @dev Returns the minimum of `x` and `y`.
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }
}