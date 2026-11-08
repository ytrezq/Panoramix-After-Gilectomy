// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IPriceFeed, IUpdatablePriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";
import {PriceFeedValidationTrait} from "@gearbox-protocol/core-v3/contracts/traits/PriceFeedValidationTrait.sol";
import {SanityCheckTrait} from "@gearbox-protocol/core-v3/contracts/traits/SanityCheckTrait.sol";

import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IBytecodeRepository} from "../interfaces/IBytecodeRepository.sol";
import {IPriceFeedStore, PriceUpdate} from "../interfaces/IPriceFeedStore.sol";
import {Call, ConnectedPriceFeed, PriceFeedInfo} from "../interfaces/Types.sol";

import {
    AP_BYTECODE_REPOSITORY,
    AP_INSTANCE_MANAGER_PROXY,
    AP_PRICE_FEED_STORE,
    AP_ZERO_PRICE_FEED,
    NO_VERSION_CONTROL
} from "../libraries/ContractLiterals.sol";
import {NestedPriceFeeds} from "../libraries/NestedPriceFeeds.sol";

import {DeployerTrait} from "../traits/DeployerTrait.sol";
import {ImmutableOwnableTrait} from "../traits/ImmutableOwnableTrait.sol";

/// @title Price feed store
contract PriceFeedStore is
    DeployerTrait,
    ImmutableOwnableTrait,
    PriceFeedValidationTrait,
    SanityCheckTrait,
    IPriceFeedStore
{
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using NestedPriceFeeds for IPriceFeed;

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_PRICE_FEED_STORE;

    /// @notice Zero price feed address
    address public immutable override zeroPriceFeed;

    /// @dev Set of all known price feeds
    EnumerableSet.AddressSet internal _knownPriceFeeds;

    /// @dev Set of all known tokens
    EnumerableSet.AddressSet internal _knownTokens;

    /// @dev Set of all updatable price feeds
    EnumerableSet.AddressSet internal _updatablePriceFeeds;

    /// @dev Mapping from `token` to its set of allowed price feeds
    mapping(address token => EnumerableSet.AddressSet) internal _allowedPriceFeeds;

    /// @dev Mapping from a `(token, priceFeed)` pair to a timestamp when `priceFeed` was allowed for `token`
    mapping(address token => mapping(address priceFeed => uint256)) internal _allowanceTimestamps;

    /// @dev Mapping from `priceFeed` to its info
    mapping(address priceFeed => PriceFeedInfo) internal _priceFeedInfo;

    /// @notice Constructor
    /// @param addressProvider_ Address provider contract address
    constructor(address addressProvider_)
        DeployerTrait(addressProvider_)
        ImmutableOwnableTrait(
            IAddressProvider(addressProvider_).getAddressOrRevert(AP_INSTANCE_MANAGER_PROXY, NO_VERSION_CONTROL)
        )
    {
        zeroPriceFeed = _deploy(AP_ZERO_PRICE_FEED, 3_10, "", bytes32(0));
    }

    // ------- //
    // GETTERS //
    // ------- //

    /// @notice Returns the list of price feeds allowed for `token`
    function getPriceFeeds(address token) public view override returns (address[] memory) {
        return _allowedPriceFeeds[token].values();
    }

    /// @notice Returns whether `priceFeed` is allowed for `token`
    function isAllowedPriceFeed(address token, address priceFeed) external view override returns (bool) {
        return _allowedPriceFeeds[token].contains(priceFeed);
    }

    /// @notice Returns the staleness period of `priceFeed`
    /// @dev Reverts if `priceFeed` is not known
    function getStalenessPeriod(address priceFeed) external view override returns (uint32) {
        if (!_knownPriceFeeds.contains(priceFeed)) revert PriceFeedIsNotKnownException(priceFeed);
        return _priceFeedInfo[priceFeed].stalenessPeriod;
    }

    /// @notice Returns the timestamp when `priceFeed` was allowed for `token`
    /// @dev Reverts if `priceFeed` is not allowed for `token`
    function getAllowanceTimestamp(address token, address priceFeed) external view override returns (uint256) {
        if (!_allowedPriceFeeds[token].contains(priceFeed)) revert PriceFeedIsNotAllowedException(token, priceFeed);
        return _allowanceTimestamps[token][priceFeed];
    }

    /// @notice Returns whether `token` is known
    function isKnownToken(address token) external view override returns (bool) {
        return _knownTokens.contains(token);
    }

    /// @notice Returns the list of known tokens
    function getKnownTokens() external view override returns (address[] memory) {
        return _knownTokens.values();
    }

    /// @notice Returns the list of tokens with their allowed price feeds
    function getTokenPriceFeedsMap() external view override returns (ConnectedPriceFeed[] memory connectedPriceFeeds) {
        address[] memory tokens = _knownTokens.values();
        uint256 len = tokens.length;

        connectedPriceFeeds = new ConnectedPriceFeed[](len);
        for (uint256 i; i < len; ++i) {
            connectedPriceFeeds[i].token = tokens[i];
            connectedPriceFeeds[i].priceFeeds = getPriceFeeds(tokens[i]);
        }
    }

    /// @notice Returns whether `priceFeed` is known
    function isKnownPriceFeed(address priceFeed) external view override returns (bool) {
        return _knownPriceFeeds.contains(priceFeed);
    }

    /// @notice Returns the list of known price feeds
    function getKnownPriceFeeds() external view override returns (address[] memory) {
        return _knownPriceFeeds.values();
    }

    /// @notice Returns the info for `priceFeed`
    function priceFeedInfo(address priceFeed) external view override returns (PriceFeedInfo memory) {
        return _priceFeedInfo[priceFeed];
    }

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    /// @notice Adds a new price feed to the store
    /// @param priceFeed The address of the new price feed
    /// @param stalenessPeriod Staleness period of the new price feed
    /// @param name Name of the new price feed
    /// @dev Reverts if caller is not owner
    /// @dev Reverts if `priceFeed` is zero address or is already added
    /// @dev Validates `priceFeed`'s tree and adds all updatable price feeds from it to the store.
    function addPriceFeed(address priceFeed, uint32 stalenessPeriod, string calldata name)
        external
        override
        onlyOwner
        nonZeroAddress(priceFeed)
    {
        if (!_knownPriceFeeds.add(priceFeed)) revert PriceFeedIsAlreadyAddedException(priceFeed);

        _validatePriceFeed(priceFeed, stalenessPeriod);
        bool isExternal = _validatePriceFeedTree(priceFeed);

        _priceFeedInfo[priceFeed] = PriceFeedInfo({
            stalenessPeriod: stalenessPeriod,
            priceFeedType: isExternal ? bytes32("PRICE_FEED::EXTERNAL") : IPriceFeed(priceFeed).contractType(),
            version: isExternal ? 0 : IPriceFeed(priceFeed).version(),
            name: name
        });

        emit AddPriceFeed(priceFeed, stalenessPeriod, name);
    }

    /// @notice Forbids `priceFeed` for all tokens and removes it from the store
    /// @dev Reverts if caller is not owner
    /// @dev Reverts if `priceFeed` is not known
    function removePriceFeed(address priceFeed) external override onlyOwner {
        if (!_knownPriceFeeds.remove(priceFeed)) revert PriceFeedIsNotKnownException(priceFeed);
        delete _priceFeedInfo[priceFeed];

        uint256 numTokens = _knownTokens.length();
        for (uint256 i; i < numTokens; ++i) {
            address token = _knownTokens.at(i);
            if (_allowedPriceFeeds[token].remove(priceFeed)) {
                _allowanceTimestamps[token][priceFeed] = 0;
                emit ForbidPriceFeed(token, priceFeed);
            }
        }

        emit RemovePriceFeed(priceFeed);
    }

    /// @notice Sets `priceFeed`'s staleness period to `stalenessPeriod`
    /// @dev Reverts if caller is not owner
    /// @dev Reverts if `priceFeed` is not known
    function setStalenessPeriod(address priceFeed, uint32 stalenessPeriod) external override onlyOwner {
        if (!_knownPriceFeeds.contains(priceFeed)) revert PriceFeedIsNotKnownException(priceFeed);
        if (_priceFeedInfo[priceFeed].stalenessPeriod == stalenessPeriod) return;

        _validatePriceFeed(priceFeed, stalenessPeriod);
        _priceFeedInfo[priceFeed].stalenessPeriod = stalenessPeriod;

        emit SetStalenessPeriod(priceFeed, stalenessPeriod);
    }

    /// @notice Allows `priceFeed` for `token`
    /// @dev Reverts if caller is not owner
    /// @dev Reverts if `token` is zero address
    /// @dev Reverts if `priceFeed` is not known or is already allowed for `token`
    function allowPriceFeed(address token, address priceFeed) external override onlyOwner nonZeroAddress(token) {
        if (!_knownPriceFeeds.contains(priceFeed)) revert PriceFeedIsNotKnownException(priceFeed);
        if (!_allowedPriceFeeds[token].add(priceFeed)) revert PriceFeedIsAlreadyAllowedException(token, priceFeed);

        _allowanceTimestamps[token][priceFeed] = block.timestamp;
        _knownTokens.add(token);

        emit AllowPriceFeed(token, priceFeed);
    }

    /// @notice Forbids `priceFeed` for `token`
    /// @dev Reverts if caller is not owner
    /// @dev Reverts if `priceFeed` is not known or is not allowed for `token`
    function forbidPriceFeed(address token, address priceFeed) external override onlyOwner {
        if (!_knownPriceFeeds.contains(priceFeed)) revert PriceFeedIsNotKnownException(priceFeed);
        if (!_allowedPriceFeeds[token].remove(priceFeed)) revert PriceFeedIsNotAllowedException(token, priceFeed);

        _allowanceTimestamps[token][priceFeed] = 0;

        emit ForbidPriceFeed(token, priceFeed);
    }

    /// @notice Executes price feed configuration `calls` with owner privileges
    /// @dev Reverts if caller is not owner
    /// @dev Reverts if any of call targets is not a known price feed
    /// @dev Reverts if any of calls renounces ownership over price feed
    function configurePriceFeeds(Call[] calldata calls) external override onlyOwner {
        uint256 numCalls = calls.length;
        for (uint256 i; i < numCalls; ++i) {
            if (!_knownPriceFeeds.contains(calls[i].target)) revert PriceFeedIsNotKnownException(calls[i].target);
            bytes4 selector = bytes4(calls[i].callData);
            if (selector == Ownable.renounceOwnership.selector) {
                revert ForbiddenConfigurationMethodException(selector);
            }
            calls[i].target.functionCall(calls[i].callData);
        }
    }

    // ------------- //
    // PRICE UPDATES //
    // ------------- //

    /// @notice Returns the list of updatable price feeds
    function getUpdatablePriceFeeds() external view override returns (address[] memory) {
        return _updatablePriceFeeds.values();
    }

    /// @notice Performs on-demand price feed updates
    /// @dev Reverts if any of the price feeds is not added to the updatable price feeds set
    function updatePrices(PriceUpdate[] calldata updates) external override {
        uint256 numUpdates = updates.length;
        for (uint256 i; i < numUpdates; ++i) {
            if (!_updatablePriceFeeds.contains(updates[i].priceFeed)) {
                revert PriceFeedIsNotUpdatableException(updates[i].priceFeed);
            }
            IUpdatablePriceFeed(updates[i].priceFeed).updatePrice(updates[i].data);
        }
    }

    // --------- //
    // INTERNALS //
    // --------- //

    /// @dev Validates `priceFeed`'s tree and adds all updatable price feeds from it to the store.
    ///      Returns whether `priceFeed` is deployed externally or via BCR.
    ///      Externally deployed price feeds are assumed to be non-updatable leaves of the tree.
    function _validatePriceFeedTree(address priceFeed) internal returns (bool) {
        if (_validatePriceFeedDeployment(priceFeed)) return true;

        if (_isUpdatable(priceFeed) && _updatablePriceFeeds.add(priceFeed)) emit AddUpdatablePriceFeed(priceFeed);
        address[] memory underlyingFeeds = IPriceFeed(priceFeed).getUnderlyingFeeds();
        uint256 numFeeds = underlyingFeeds.length;
        for (uint256 i; i < numFeeds; ++i) {
            _validatePriceFeedTree(underlyingFeeds[i]);
        }

        return false;
    }

    /// @dev Returns whether `priceFeed` is deployed externally or via BCR.
    ///      For latter case, also ensures that price feed is owned by the store.
    function _validatePriceFeedDeployment(address priceFeed) internal returns (bool) {
        if (!IBytecodeRepository(bytecodeRepository).isDeployedFromRepository(priceFeed)) return true;

        try Ownable2Step(priceFeed).acceptOwnership() {} catch {}
        try Ownable(priceFeed).owner() returns (address owner_) {
            if (owner_ != address(this)) revert PriceFeedIsNotOwnedByStore(priceFeed);
        } catch {}

        return false;
    }

    /// @dev Returns whether `priceFeed` is updatable
    function _isUpdatable(address priceFeed) internal view returns (bool) {
        try IUpdatablePriceFeed(priceFeed).updatable() returns (bool updatable) {
            return updatable;
        } catch {
            return false;
        }
    }
}
