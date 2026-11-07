// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {
    IPriceFeedStore as IPriceFeedStoreBase,
    PriceUpdate
} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeedStore.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {IDeployerTrait} from "./base/IDeployerTrait.sol";
import {IImmutableOwnableTrait} from "./base/IImmutableOwnableTrait.sol";
import {Call, ConnectedPriceFeed, PriceFeedInfo} from "./Types.sol";

/// @title Price feed store interface
interface IPriceFeedStore is IPriceFeedStoreBase, IVersion, IDeployerTrait, IImmutableOwnableTrait {
    // ------ //
    // ERRORS //
    // ------ //

    /// @notice Thrown when attempting to use a price feed that is not known by the price feed store
    error PriceFeedIsNotKnownException(address priceFeed);

    /// @notice Thrown when attempting to add a price feed that is already known by the price feed store
    error PriceFeedIsAlreadyAddedException(address priceFeed);

    /// @notice Thrown when attempting to forbid a price feed that is not allowed for a token
    error PriceFeedIsNotAllowedException(address token, address priceFeed);

    /// @notice Thrown when attempting to allow a price feed that is already allowed for a token
    error PriceFeedIsAlreadyAllowedException(address token, address priceFeed);

    /// @notice Thrown when attempting to add a price feed that is not owned by the store
    error PriceFeedIsNotOwnedByStore(address priceFeed);

    /// @notice Thrown when attempting to update a price feed that is not added to the updatable price feeds set
    error PriceFeedIsNotUpdatableException(address priceFeed);

    /// @notice Thrown when attempting to call a forbidden configuration method
    error ForbiddenConfigurationMethodException(bytes4 selector);

    // ------ //
    // EVENTS //
    // ------ //

    /// @notice Emitted when a new price feed is added to the store
    event AddPriceFeed(address indexed priceFeed, uint32 stalenessPeriod, string name);

    /// @notice Emitted when a price feed is removed from the store
    event RemovePriceFeed(address indexed priceFeed);

    /// @notice Emitted when the staleness period is set for a price feed
    event SetStalenessPeriod(address indexed priceFeed, uint32 stalenessPeriod);

    /// @notice Emitted when a price feed is allowed for a token
    event AllowPriceFeed(address indexed token, address indexed priceFeed);

    /// @notice Emitted when a price feed is forbidden for a token
    event ForbidPriceFeed(address indexed token, address indexed priceFeed);

    /// @notice Emitted when a price feed is added to the updatable price feeds set
    event AddUpdatablePriceFeed(address indexed priceFeed);

    // ------- //
    // GETTERS //
    // ------- //

    function zeroPriceFeed() external view returns (address);
    function getPriceFeeds(address token) external view returns (address[] memory);
    function isAllowedPriceFeed(address token, address priceFeed) external view returns (bool);
    function getStalenessPeriod(address priceFeed) external view override returns (uint32);
    function getAllowanceTimestamp(address token, address priceFeed) external view returns (uint256);
    function getTokenPriceFeedsMap() external view returns (ConnectedPriceFeed[] memory);
    function getKnownTokens() external view returns (address[] memory);
    function isKnownToken(address token) external view returns (bool);
    function getKnownPriceFeeds() external view returns (address[] memory);
    function isKnownPriceFeed(address priceFeed) external view returns (bool);
    function priceFeedInfo(address priceFeed) external view returns (PriceFeedInfo memory);

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function addPriceFeed(address priceFeed, uint32 stalenessPeriod, string calldata name) external;
    function removePriceFeed(address priceFeed) external;
    function setStalenessPeriod(address priceFeed, uint32 stalenessPeriod) external;
    function allowPriceFeed(address token, address priceFeed) external;
    function forbidPriceFeed(address token, address priceFeed) external;
    function configurePriceFeeds(Call[] calldata calls) external;

    // ------------- //
    // PRICE UPDATES //
    // ------------- //

    function getUpdatablePriceFeeds() external view returns (address[] memory);
    function updatePrices(PriceUpdate[] calldata updates) external override;
}
