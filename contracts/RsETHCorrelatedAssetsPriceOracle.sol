// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import { AggregatorV3Interface } from "./interfaces/AggregatorV3Interface.sol";
import { PriceCapAdapterBase } from "./utils/PriceCapAdapterBase.sol";
import { ILRTOracle } from "./interfaces/ILRTOracle.sol";

/**
 * @title RsETHCorrelatedAssetsPriceOracle
 * @author WOOF!
 * @custom:security-contact dmitriy@woof.software
 */
contract RsETHCorrelatedAssetsPriceOracle is PriceCapAdapterBase {
    /**
     * @param _manager address of the manager
     * @param _baseAggregatorAddress address of the base aggregator
     * @param _lrtOracleAddress address of the RsETH oracle
     * @param _description description of the pair
     * @param _priceFeedDecimals number of decimals for the price feed
     * @param _minimumSnapshotDelay minimum time that should have passed from the snapshot timestamp to the current block.timestamp
     * @param _priceCapSnapshot parameters to set price cap
     */
    constructor(
        address _manager,
        AggregatorV3Interface _baseAggregatorAddress,
        address _lrtOracleAddress,
        string memory _description,
        uint8 _priceFeedDecimals,
        uint48 _minimumSnapshotDelay,
        PriceCapSnapshot memory _priceCapSnapshot
    )
        PriceCapAdapterBase(
            _manager,
            _baseAggregatorAddress,
            _lrtOracleAddress,
            _description,
            _priceFeedDecimals,
            _minimumSnapshotDelay,
            _priceCapSnapshot
        )
    {}

    /// @inheritdoc PriceCapAdapterBase
    function getRatio() public view override returns (int256) {
        return int256(ILRTOracle(ratioProvider).rsETHPrice());
    }

    /// @inheritdoc PriceCapAdapterBase
    function ratioDecimals() public pure override returns (uint8) {
        return 18;
    }
}
