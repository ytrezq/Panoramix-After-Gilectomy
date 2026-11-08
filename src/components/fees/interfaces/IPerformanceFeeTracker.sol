// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

/// @title IPerformanceFeeTracker Interface
/// @author Enzyme Foundation <security@enzyme.finance>
/// @dev Keep namespaces specific so management and performance fee could be handled by same contract
interface IPerformanceFeeTracker {
    /// @notice Settles the performance fee
    /// @param _netValue Net value of the portfolio, in shares value asset
    /// @return valueDue_ The performance fee due, in shares value asset
    function settlePerformanceFee(uint256 _netValue) external returns (uint256 valueDue_);
}
