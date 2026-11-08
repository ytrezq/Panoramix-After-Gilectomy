// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library RoundingGuard {

    /** @notice Returns `original` when `candidate` differs by at most 1 wei, otherwise returns `candidate`.
     *  @dev Intended to suppress insignificant rounding noise in round-trip conversions such as
     *      assets -> shares -> assets, where the recalculated value may differ from the original
     *      by 1 wei due to integer division rounding. This helps preserve the original value when
     *      the difference is economically irrelevant, while still propagating meaningful changes.
     */
    function preferOriginalWithin1Wei(uint256 original, uint256 candidate) internal pure returns (uint256) {
        uint256 diff = original > candidate
            ? original - candidate
            : candidate - original;

        return diff <= 1 ? original : candidate;
    }
}
