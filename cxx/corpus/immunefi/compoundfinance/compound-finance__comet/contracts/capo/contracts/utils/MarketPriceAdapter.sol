// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";

/**@notice Base contract for price oracles that optionally adjust an LST-native ratio using an external market price feed.
 * @custom:security-contact dmitriy@woof.software
 */
abstract contract MarketPriceAdapter {
    /// @notice External price feed for LST-to-asset market rate.
    /// @dev If zero, assumes 1:1 ratio between LST and asset.
    AggregatorV3Interface public immutable marketAggregator;

    /// @notice Scaling factor based on marketAggregator's decimals (10^decimals).
    /// @dev If zero, market rate is skipped and raw ratio is used (1:1 mode).
    int256 internal immutable _marketPrecision;

    constructor(AggregatorV3Interface _marketAggregator) {
        marketAggregator = _marketAggregator;
        _marketPrecision = int256(address(_marketAggregator) == address(0) ? 0 : 10 ** _marketAggregator.decimals());
    }

    /// @notice Converts the raw ratio using the market rate if available.
    function _convertWithMarketRate(int256 rawRatio) internal view returns (int256) {
        if (_marketPrecision == 0) {
            return rawRatio;
        }

        (, int256 marketRate, , , ) = marketAggregator.latestRoundData();
        if (marketRate <= 0) {
            return 0;
        }

        return (rawRatio * marketRate) / _marketPrecision;
    }
}
