// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import { AggregatorV3Interface } from "./interfaces/AggregatorV3Interface.sol";
import { MarketPriceAdapter } from "./utils/MarketPriceAdapter.sol";
import { PriceCapAdapterBase } from "./utils/PriceCapAdapterBase.sol";
import { IWstETH } from "./interfaces/IWstETH.sol";

/**
 * @title WstETHCorrelatedAssetsPriceOracle
 * @author WOOF!
 * @custom:security-contact dmitriy@woof.software
 */
contract WstETHCorrelatedAssetsPriceOracle is PriceCapAdapterBase, MarketPriceAdapter {
    uint8 internal immutable _ratioDecimals;

    /**
     * @param _manager address of the manager
     * @param _baseAggregatorAddress address of the base aggregator
     * @param _wstETH address of the WstETH contract
     * @param _description description of the pair
     * @param _priceFeedDecimals number of decimals for the price feed
     * @param _minimumSnapshotDelay minimum time that should have passed from the snapshot timestamp to the current block.timestamp
     * @param _priceCapSnapshot parameters to set price cap
     */
    constructor(
        address _manager,
        AggregatorV3Interface _baseAggregatorAddress,
        address _wstETH,
        AggregatorV3Interface _marketAggregator,
        string memory _description,
        uint8 _priceFeedDecimals,
        uint48 _minimumSnapshotDelay,
        PriceCapSnapshot memory _priceCapSnapshot
    )
        MarketPriceAdapter(_marketAggregator)
        PriceCapAdapterBase(_manager, _baseAggregatorAddress, _wstETH, _description, _priceFeedDecimals, _minimumSnapshotDelay, _priceCapSnapshot)
    {
        _ratioDecimals = 18;
    }

    ///  @inheritdoc PriceCapAdapterBase
    function getRatio() public view override returns (int256) {
        int256 ratio = int256(IWstETH(ratioProvider).stEthPerToken());
        return _convertWithMarketRate(ratio);
    }

    ///  @inheritdoc PriceCapAdapterBase
    function ratioDecimals() public view override returns (uint8) {
        return _ratioDecimals;
    }
}
