// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title IValuationHandler Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IValuationHandler {
    function convertAssetAmountToValue(address _asset, uint256 _assetAmount) external view returns (uint256 value_);

    function convertValueToAssetAmount(uint256 _value, address _asset) external view returns (uint256 assetAmount_);

    function getDefaultSharePrice() external view returns (uint256);

    function getSharePrice() external view returns (uint256 price_, uint256 timestamp_);

    function getShareValue() external view returns (uint256 value_, uint256 timestamp_);
}
