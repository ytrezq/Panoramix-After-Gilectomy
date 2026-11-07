// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./IMarket.sol";

interface IReader {
    struct PriceProps {
        uint256 min;
        uint256 max;
    }
    struct MarketProps {
        address marketToken;
        address indexToken;
        address longToken;
        address shortToken;
    }
    struct MarketPrices {
        PriceProps indexTokenPrice;
        PriceProps longTokenPrice;
        PriceProps shortTokenPrice;
    }
    enum SwapPricingType {
        TwoStep,
        Shift,
        Atomic
    }

    function getMarket(address dataStore, address key) external view returns (MarketProps memory);

    function getDepositAmountOut(
        address dataStore,
        MarketProps memory market,
        MarketPrices memory prices,
        uint256 longTokenAmount,
        uint256 shortTokenAmount,
        address uiFeeReceiver,
        SwapPricingType swapPricingType,
        bool includeVirtualInventoryImpact
    ) external view returns (uint256);

    function getWithdrawalAmountOut(
        address dataStore,
        MarketProps memory market,
        MarketPrices memory prices,
        uint256 marketTokenAmount,
        address uiFeeReceiver,
        SwapPricingType swapPricingType
    ) external view returns (uint256, uint256);
}