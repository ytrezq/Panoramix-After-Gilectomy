// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

/**
 * @notice A library which implements fixed point decimal math.
 */
library FixedPointMath {
    /**
     * @dev This will give approximately 60 bits of precision
     */
    uint256 public constant DECIMALS = 18;
    uint256 public constant ONE = 10 ** DECIMALS;

    error MulDivZeroDenominator();
    error MulDivOverflow();

    /**
     * @notice A struct representing a fixed point decimal.
     */
    struct Number {
        uint256 n;
    }

    /**
     * @notice Encodes a unsigned 256-bit integer into a fixed point decimal.
     *
     * @param value The value to encode.
     * @return      The fixed point decimal representation.
     */
    function encode(uint256 value) internal pure returns (Number memory) {
        return Number(FixedPointMath.encodeRaw(value));
    }

    /**
     * @notice Encodes a unsigned 256-bit integer into a uint256 representation of a
     *         fixed point decimal.
     *
     * @param value The value to encode.
     * @return      The fixed point decimal representation.
     */
    function encodeRaw(uint256 value) internal pure returns (uint256) {
        return value * ONE;
    }

    /**
     * @notice Encodes a uint256 MAX VALUE into a uint256 representation of a
     *         fixed point decimal.
     *
     * @return      The uint256 MAX VALUE fixed point decimal representation.
     */
    function max() internal pure returns (Number memory) {
        return Number(type(uint256).max);
    }

    /**
     * @notice Creates a rational fraction as a Number from 2 uint256 values
     *
     * @param n The numerator.
     * @param d The denominator.
     * @return  The fixed point decimal representation.
     */
    function rational(uint256 n, uint256 d) internal pure returns (Number memory) {
        Number memory numerator = encode(n);
        return FixedPointMath.div(numerator, d);
    }

    /**
     * @notice Adds two fixed point decimal numbers together.
     *
     * @param self  The left hand operand.
     * @param value The right hand operand.
     * @return      The result.
     */
    function add(Number memory self, Number memory value) internal pure returns (Number memory) {
        return Number(self.n + value.n);
    }

    /**
     * @notice Adds a fixed point number to a unsigned 256-bit integer.
     *
     * @param self  The left hand operand.
     * @param value The right hand operand. This will be converted to a fixed point decimal.
     * @return      The result.
     */
    function add(Number memory self, uint256 value) internal pure returns (Number memory) {
        return add(self, FixedPointMath.encode(value));
    }

    /**
     * @notice Subtract a fixed point decimal from another.
     *
     * @param self  The left hand operand.
     * @param value The right hand operand.
     * @return      The result.
     */
    function sub(Number memory self, Number memory value) internal pure returns (Number memory) {
        return Number(self.n - value.n);
    }

    /**
     * @notice Subtract a unsigned 256-bit integer from a fixed point decimal.
     *
     * @param self  The left hand operand.
     * @param value The right hand operand. This will be converted to a fixed point decimal.
     * @return      The result.
     */
    function sub(Number memory self, uint256 value) internal pure returns (Number memory) {
        return sub(self, FixedPointMath.encode(value));
    }

    /**
     * @notice Multiplies a fixed point decimal by another fixed point decimal.
     *
     * @param self  The fixed point decimal to multiply.
     * @param number The fixed point decimal to multiply by.
     * @return      The result.
     */
    function mul(Number memory self, Number memory number) internal pure returns (Number memory) {
        return Number((self.n * number.n) / ONE);
    }

    /**
     * @notice Multiplies a fixed point decimal by an unsigned 256-bit integer.
     *
     * @param self  The fixed point decimal to multiply.
     * @param value The unsigned 256-bit integer to multiply by.
     * @return      The result.
     */
    function mul(Number memory self, uint256 value) internal pure returns (Number memory) {
        return Number(self.n * value);
    }

    /**
     * @notice Divides a fixed point decimal by an unsigned 256-bit integer.
     *
     * @param self  The fixed point decimal to multiply by.
     * @param value The unsigned 256-bit integer to divide by.
     * @return      The result.
     */
    function div(Number memory self, uint256 value) internal pure returns (Number memory) {
        return Number(self.n / value);
    }

    /// @notice floor(x * y / denominator) with full precision.
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            if (denominator == 0) revert MulDivZeroDenominator();

            // 512-bit multiply: [prod1 prod0] = x * y
            uint256 prod0;
            uint256 prod1;
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow case (prod1 == 0)
            if (prod1 == 0) {
                return prod0 / denominator;
            }

            // Ensure result fits in 256 bits and denominator != 0
            if (denominator <= prod1) revert MulDivOverflow();

            // Make division exact by subtracting remainder from [prod1 prod0]
            uint256 remainder;
            assembly {
                remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                // twos = 2^256 / twos
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift high bits into prod0
            prod0 |= prod1 * twos;

            // Compute modular inverse of denominator mod 2^256 (denominator is now odd)
            uint256 inv = (3 * denominator) ^ 2;
            inv *= 2 - denominator * inv; // 8 bits
            inv *= 2 - denominator * inv; // 16
            inv *= 2 - denominator * inv; // 32
            inv *= 2 - denominator * inv; // 64
            inv *= 2 - denominator * inv; // 128
            inv *= 2 - denominator * inv; // 256

            // Multiply by inverse to get the quotient
            result = prod0 * inv;
        }
    }

    /// @notice ceil(x * y / denominator) with full precision.
    function mulDivUp(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        result = mulDiv(x, y, denominator);
        unchecked {
            if (mulmod(x, y, denominator) != 0) {
                if (result == type(uint256).max) revert MulDivOverflow();
                result += 1;
            }
        }
    }
    
    /**
     * @notice Compares two fixed point decimals.
     *
     * @param self  The left hand number to compare.
     * @param value The right hand number to compare.
     * @return      When the left hand number is less than the right hand number this returns -1,
     *              when the left hand number is greater than the right hand number this returns 1,
     *              when they are equal this returns 0.
     */
    function cmp(Number memory self, Number memory value) internal pure returns (int256) {
        if (self.n < value.n) {
            return -1;
        }

        if (self.n > value.n) {
            return 1;
        }

        return 0;
    }

    /**
     * @notice Gets if two fixed point numbers are equal.
     *
     * @param self  the first fixed point number.
     * @param value the second fixed point number.
     *
     * @return if they are equal.
     */
    function equals(Number memory self, Number memory value) internal pure returns (bool) {
        return self.n == value.n;
    }

    /**
     * @notice Truncates a fixed point decimal into an unsigned 256-bit integer.
     *
     * @return The integer portion of the fixed point decimal.
     */
    function truncate(Number memory self) internal pure returns (uint256) {
        return self.n / ONE;
    }

    // Math helpers for Q128.128
    function mulQ128(uint256 aQ, uint256 bQ) internal pure returns (uint256 z) {
        if (aQ == 0 || bQ == 0) return 0;
        uint256 lo;
        uint256 hi;
        assembly {
            // 512-bit product [hi lo] = aQ * bQ
            let mm := mulmod(aQ, bQ, not(0))
            lo := mul(aQ, bQ)
            hi := sub(sub(mm, lo), lt(mm, lo))
        }
        // floor((a*b) / 2^128)
        z = (hi << 128) | (lo >> 128);
        // if there are non-zero low bits, round up
        if (lo & ((uint256(1) << 128) - 1) != 0) {
            unchecked {
                z += 1;
            }
        }
    }

    function divQ128(uint256 numerQ128, uint256 denomQ128) internal pure returns (uint256) {
        if (numerQ128 == 0) return 0;
        unchecked {
            // Fast path: shifting is safe if numerQ128 < 2^128
            if (numerQ128 <= type(uint256).max >> 128) {
                return (numerQ128 << 128) / denomQ128;
            }
            // Slow path: numerQ128 can only be 2^128 here.
            uint256 q = numerQ128 / denomQ128; // 0 or 1 in our domain
            uint256 r = numerQ128 - q * denomQ128; // remainder
            return (q << 128) + ((r << 128) / denomQ128);
        }
    }
}