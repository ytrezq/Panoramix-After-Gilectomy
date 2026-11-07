// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Shared revert decoding and forwarding helpers for strategy tests.
/// @dev Use this mixin from base modules/handlers to keep revert handling consistent.
abstract contract StrategyRevertUtils {
    error UnexpectedRevert(bytes4 selector, bytes data);

    function _revertSelector(bytes memory errData) internal pure returns (bytes4 sel) {
        if (errData.length < 4) return bytes4(0);
        assembly {
            sel := mload(add(errData, 32))
        }
    }

    function _revertUnlessWhitelisted(bytes memory errData, bool isWhitelisted) internal pure {
        if (isWhitelisted) return;
        bytes4 sel = _revertSelector(errData);
        revert UnexpectedRevert(sel, errData);
    }
}
