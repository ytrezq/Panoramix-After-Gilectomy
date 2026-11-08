// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IPriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";
import {IPriceOracleV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPriceOracleV3.sol";

import {IFactory} from "../interfaces/factories/IFactory.sol";
import {IMarketFactory} from "../interfaces/factories/IMarketFactory.sol";
import {IPriceOracleFactory} from "../interfaces/factories/IPriceOracleFactory.sol";
import {IPriceOracleConfigureActions} from "../interfaces/factories/IPriceOracleConfigureActions.sol";
import {IPriceOracleEmergencyConfigureActions} from "../interfaces/factories/IPriceOracleEmergencyConfigureActions.sol";
import {IMarketConfigurator} from "../interfaces/IMarketConfigurator.sol";
import {IPriceFeedStore} from "../interfaces/IPriceFeedStore.sol";
import {Call, DeployResult} from "../interfaces/Types.sol";

import {CallBuilder} from "../libraries/CallBuilder.sol";
import {
    AP_PRICE_FEED_STORE,
    AP_PRICE_ORACLE,
    AP_PRICE_ORACLE_FACTORY,
    NO_VERSION_CONTROL
} from "../libraries/ContractLiterals.sol";

import {AbstractFactory} from "./AbstractFactory.sol";
import {AbstractMarketFactory} from "./AbstractMarketFactory.sol";

interface IPriceOracleLegacy {
    /// @dev Older signature for fetching main and reserve feeds, reverts if price feed is not set
    function priceFeedsRaw(address token, bool reserve) external view returns (address);
}

contract PriceOracleFactory is AbstractMarketFactory, IPriceOracleFactory {
    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = AP_PRICE_ORACLE_FACTORY;

    address public immutable priceFeedStore;
    address public immutable zeroPriceFeed;

    error PriceFeedNotAllowedException(address token, address priceFeed);
    error PriceFeedAllowedTooRecentlyException(address token, address priceFeed);
    error TokenIsNotAddedException(address token);
    error ZeroPriceFeedException(address token);

    constructor(address addressProvider_) AbstractFactory(addressProvider_) {
        priceFeedStore = _getAddressOrRevert(AP_PRICE_FEED_STORE, NO_VERSION_CONTROL);
        zeroPriceFeed = IPriceFeedStore(priceFeedStore).zeroPriceFeed();
    }

    // ---------- //
    // DEPLOYMENT //
    // ---------- //

    function deployPriceOracle(address pool) external override onlyMarketConfigurators returns (DeployResult memory) {
        address acl = IMarketConfigurator(msg.sender).acl();

        address priceOracle = _deployLatestPatch({
            contractType: AP_PRICE_ORACLE,
            minorVersion: version,
            constructorParams: abi.encode(acl),
            salt: bytes32(bytes20(pool))
        });

        return DeployResult({
            newContract: priceOracle,
            onInstallOps: CallBuilder.build(_authorizeFactory(msg.sender, pool, priceOracle))
        });
    }

    function computePriceOracleAddress(address marketConfigurator, address pool)
        external
        view
        override
        returns (address)
    {
        address acl = IMarketConfigurator(marketConfigurator).acl();
        return _computeAddressLatestPatch({
            contractType: AP_PRICE_ORACLE,
            minorVersion: version,
            constructorParams: abi.encode(acl),
            salt: bytes32(bytes20(pool)),
            deployer: address(this)
        });
    }
    // ------------ //
    // MARKET HOOKS //
    // ------------ //

    function onCreateMarket(address pool, address priceOracle, address, address, address, address underlyingPriceFeed)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        address underlying = _underlying(pool);
        _revertOnZeroPriceFeed(underlying, underlyingPriceFeed);
        return CallBuilder.build(_setPriceFeed(priceOracle, underlying, underlyingPriceFeed, false));
    }

    function onUpdatePriceOracle(address pool, address newPriceOracle, address oldPriceOracle)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory calls)
    {
        address underlying = _underlying(pool);
        address[] memory tokens = _quotedTokens(_quotaKeeper(pool));
        uint256 numTokens = 1 + tokens.length;

        calls = new Call[](1 + 2 * numTokens);
        calls[0] = _unauthorizeFactory(msg.sender, pool, oldPriceOracle);

        uint256 numCalls = 1;
        for (uint256 i; i < numTokens; ++i) {
            address token = i == 0 ? underlying : tokens[i - 1];

            address main = _getPriceFeed(oldPriceOracle, token, false);
            calls[numCalls++] = _setPriceFeed(newPriceOracle, token, main, false);

            address reserve = _getPriceFeed(oldPriceOracle, token, true);
            if (reserve != address(0)) calls[numCalls++] = _setPriceFeed(newPriceOracle, token, reserve, true);
        }

        assembly {
            mstore(calls, numCalls)
        }
    }

    function onAddToken(address pool, address token, address priceFeed)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        return CallBuilder.build(_setPriceFeed(_priceOracle(pool), token, priceFeed, false));
    }

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function configure(address pool, bytes calldata callData)
        external
        view
        override(AbstractFactory, IFactory)
        returns (Call[] memory)
    {
        address priceOracle = _priceOracle(pool);

        bytes4 selector = bytes4(callData);
        if (selector == IPriceOracleConfigureActions.setPriceFeed.selector) {
            (address token, address priceFeed) = abi.decode(callData[4:], (address, address));
            _validatePriceFeed(pool, token, priceFeed, true);
            return CallBuilder.build(_setPriceFeed(priceOracle, token, priceFeed, false));
        } else if (selector == IPriceOracleConfigureActions.setReservePriceFeed.selector) {
            (address token, address priceFeed) = abi.decode(callData[4:], (address, address));
            _validatePriceFeed(pool, token, priceFeed, false);
            return CallBuilder.build(_setPriceFeed(priceOracle, token, priceFeed, true));
        } else {
            revert ForbiddenConfigurationCallException(selector);
        }
    }

    function emergencyConfigure(address pool, bytes calldata callData)
        external
        view
        override(AbstractFactory, IFactory)
        returns (Call[] memory)
    {
        address priceOracle = _priceOracle(pool);

        bytes4 selector = bytes4(callData);
        if (selector == IPriceOracleEmergencyConfigureActions.setPriceFeed.selector) {
            (address token, address priceFeed) = abi.decode(callData[4:], (address, address));
            _validatePriceFeed(pool, token, priceFeed, true);
            if (block.timestamp < IPriceFeedStore(priceFeedStore).getAllowanceTimestamp(token, priceFeed) + 1 days) {
                revert PriceFeedAllowedTooRecentlyException(token, priceFeed);
            }
            return CallBuilder.build(_setPriceFeed(priceOracle, token, priceFeed, false));
        } else {
            revert ForbiddenEmergencyConfigurationCallException(selector);
        }
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _validatePriceFeed(address pool, address token, address priceFeed, bool revertOnZeroPrice) internal view {
        address underlying = _underlying(pool);
        address quotaKeeper = _quotaKeeper(pool);
        if (token != underlying && !_isQuotedToken(quotaKeeper, token)) {
            revert TokenIsNotAddedException(token);
        }
        if (revertOnZeroPrice && (token == underlying || _quota(quotaKeeper, token) != 0)) {
            _revertOnZeroPriceFeed(token, priceFeed);
        }
    }

    function _revertOnZeroPriceFeed(address token, address priceFeed) internal view {
        (, int256 answer,,,) = IPriceFeed(priceFeed).latestRoundData();
        if (answer == 0) revert ZeroPriceFeedException(token);
    }

    function _getPriceFeed(address priceOracle, address token, bool reserve) internal view returns (address) {
        if (IPriceOracleV3(priceOracle).version() < 3_10) {
            try IPriceOracleLegacy(priceOracle).priceFeedsRaw(token, reserve) returns (address priceFeed) {
                return priceFeed;
            } catch {
                return address(0);
            }
        }
        return reserve
            ? IPriceOracleV3(priceOracle).reservePriceFeeds(token)
            : IPriceOracleV3(priceOracle).priceFeeds(token);
    }

    function _setPriceFeed(address priceOracle, address token, address priceFeed, bool reserve)
        internal
        view
        returns (Call memory)
    {
        bool isValid = IPriceFeedStore(priceFeedStore).isAllowedPriceFeed(token, priceFeed)
            || reserve && priceFeed == zeroPriceFeed;
        if (!isValid) revert PriceFeedNotAllowedException(token, priceFeed);

        uint32 stalenessPeriod = IPriceFeedStore(priceFeedStore).getStalenessPeriod(priceFeed);

        return reserve
            ? _setReservePriceFeedCall(priceOracle, token, priceFeed, stalenessPeriod)
            : _setPriceFeedCall(priceOracle, token, priceFeed, stalenessPeriod);
    }

    function _setPriceFeedCall(address priceOracle, address token, address priceFeed, uint32 stalenessPeriod)
        internal
        pure
        returns (Call memory)
    {
        return Call(priceOracle, abi.encodeCall(IPriceOracleV3.setPriceFeed, (token, priceFeed, stalenessPeriod)));
    }

    function _setReservePriceFeedCall(address priceOracle, address token, address priceFeed, uint32 stalenessPeriod)
        internal
        pure
        returns (Call memory)
    {
        return
            Call(priceOracle, abi.encodeCall(IPriceOracleV3.setReservePriceFeed, (token, priceFeed, stalenessPeriod)));
    }
}
