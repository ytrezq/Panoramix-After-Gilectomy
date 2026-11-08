// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title IFeeHandler Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IFeeHandler {
    function getTotalValueOwed() external view returns (uint256 totalValueOwed_);

    function settleDynamicFeesGivenPositionsValue(uint256 _totalPositionsValue) external;

    function settleEntranceFeeGivenGrossShares(uint256 _grossSharesAmount) external returns (uint256 feeShares_);

    function settleExitFeeGivenGrossShares(uint256 _grossSharesAmount) external returns (uint256 feeShares_);
}
