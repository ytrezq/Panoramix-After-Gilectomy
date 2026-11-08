// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {
    ISyncRedeemHandlerPostRedeemHook
} from "src/components/issuance/interfaces/ISyncRedeemHandlerPostRedeemHook.sol";
import {IFeeHandler} from "src/interfaces/IFeeHandler.sol";
import {Shares} from "src/shares/Shares.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";
import {ValueHelpersLib} from "src/utils/ValueHelpersLib.sol";

/// @title SyncRedeemHandler Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A synchronous redeem handler where users burn their own shares and immediately receive pro-rated assets
/// @dev Considerations and limitations:
/// - pays `msg.sender` only
/// - may not support irregular asset behaviors (e.g., fee-on-transfer).
/// - the cached share price may be close to the real share price, which the vault manager accepts
contract SyncRedeemHandler is Initializable, ComponentHelpersMixin {
    //==================================================================================================================
    // Constants
    //==================================================================================================================

    uint24 internal constant MAX_SHARE_PRICE_STALENESS_DISABLED = type(uint24).max;

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant SYNC_REDEEM_HANDLER_STORAGE_LOCATION =
        0xeb990dd87e988d016a444e34ebedfa606d99753db55155434f2700b48c21bc00;
    string private constant SYNC_REDEEM_HANDLER_STORAGE_LOCATION_ID = "SyncRedeemHandler";

    /// @custom:storage-location erc7201:enzyme.SyncRedeemHandler
    /// @param asset The ERC20 asset paid out on redemption
    /// @param maxSharePriceStaleness Maximum allowed age of the share price in seconds
    /// @param postRedeemHook A hook called with redemptions after they settle (`address(0)` disables it)
    struct SyncRedeemHandlerStorage {
        address asset;
        uint24 maxSharePriceStaleness;
        address postRedeemHook;
    }

    function __getSyncRedeemHandlerStorage() private pure returns (SyncRedeemHandlerStorage storage $) {
        bytes32 location = SYNC_REDEEM_HANDLER_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event AssetSet(address asset);

    event Redeem(address redeemer, uint256 assetAmount, uint256 sharesAmount);

    event MaxSharePriceStalenessSet(uint24 maxStaleness);

    event PostRedeemHookSet(address hook);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error SyncRedeemHandler__Redeem__ZeroShares();

    error SyncRedeemHandler__Redeem__ZeroAssets();

    error SyncRedeemHandler__ValidateSharePriceTimestamp__SharePriceStale();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: SYNC_REDEEM_HANDLER_STORAGE_LOCATION, _id: SYNC_REDEEM_HANDLER_STORAGE_LOCATION_ID
        });

        _disableInitializers();
    }

    //==================================================================================================================
    // Init
    //==================================================================================================================

    /// @notice Initializer
    /// @param _asset The ERC20 asset to pay out on redemption
    function init(address _asset) external initializer {
        SyncRedeemHandlerStorage storage $ = __getSyncRedeemHandlerStorage();
        $.asset = _asset;

        emit AssetSet({asset: _asset});
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    /// @notice Sets the maximum allowed staleness of the share price
    /// @param _maxStaleness Maximum age in seconds (MAX_SHARE_PRICE_STALENESS_DISABLED = no check)
    function setMaxSharePriceStaleness(uint24 _maxStaleness) external onlyAdminOrOwner {
        __getSyncRedeemHandlerStorage().maxSharePriceStaleness = _maxStaleness;

        emit MaxSharePriceStalenessSet({maxStaleness: _maxStaleness});
    }

    /// @notice Sets the post-redeem hook (`address(0)` disables the post-redeem hook)
    function setPostRedeemHook(address _postRedeemHook) external onlyAdminOrOwner {
        __getSyncRedeemHandlerStorage().postRedeemHook = _postRedeemHook;

        emit PostRedeemHookSet(_postRedeemHook);
    }

    //==================================================================================================================
    // Redemptions (access: public)
    //==================================================================================================================

    /// @notice Burns the caller's shares and transfers the pro-rated asset amount to the caller
    /// @param _sharesAmount The gross amount of shares to redeem
    /// @return assetAmount_ The amount of assets paid to the caller
    function redeem(uint256 _sharesAmount) external returns (uint256 assetAmount_) {
        require(_sharesAmount > 0, SyncRedeemHandler__Redeem__ZeroShares());

        Shares shares = Shares(__getShares());
        ValuationHandler valuationHandler = ValuationHandler(shares.getValuationHandler());

        (uint256 sharePriceInValueAsset, uint256 sharePriceTimestamp) = valuationHandler.getSharePrice();
        __validateSharePriceTimestamp({_sharePriceTimestamp: sharePriceTimestamp});

        // Settle any exit fee, then price the shares the user is actually paid for.
        IFeeHandler feeHandler = IFeeHandler(shares.getFeeHandler());
        uint256 feeSharesAmount = address(feeHandler) == address(0)
            ? 0
            : feeHandler.settleExitFeeGivenGrossShares({_grossSharesAmount: _sharesAmount});

        uint256 valueDue = ValueHelpersLib.calcValueOfSharesAmount({
            _valuePerShare: sharePriceInValueAsset, _sharesAmount: _sharesAmount - feeSharesAmount
        });
        assetAmount_ = valuationHandler.convertValueToAssetAmount({_value: valueDue, _asset: getAsset()});
        require(assetAmount_ > 0, SyncRedeemHandler__Redeem__ZeroAssets());

        // Burn gross shares (exit-fee shares are burned, not paid).
        shares.burnFor({_from: msg.sender, _sharesAmount: _sharesAmount});

        shares.withdrawAssetTo({_asset: getAsset(), _to: msg.sender, _amount: assetAmount_});

        __runPostRedeemHook({_originator: msg.sender, _sharesAmount: _sharesAmount, _assetAmount: assetAmount_});

        emit Redeem({redeemer: msg.sender, assetAmount: assetAmount_, sharesAmount: _sharesAmount});
    }

    //==================================================================================================================
    // Internal helpers
    //==================================================================================================================

    /// @dev Validates that the share price is not stale
    function __validateSharePriceTimestamp(uint256 _sharePriceTimestamp) internal view {
        uint24 maxStaleness = getMaxSharePriceStaleness();
        if (maxStaleness == MAX_SHARE_PRICE_STALENESS_DISABLED) return;

        require(
            block.timestamp - _sharePriceTimestamp <= maxStaleness,
            SyncRedeemHandler__ValidateSharePriceTimestamp__SharePriceStale()
        );
    }

    /// @dev Runs the redemption through the attached post-redeem hook, if any. No-op when unset.
    function __runPostRedeemHook(address _originator, uint256 _sharesAmount, uint256 _assetAmount) internal {
        address hook = getPostRedeemHook();

        if (hook == address(0)) {
            return;
        }

        ISyncRedeemHandlerPostRedeemHook(hook).postRedeem({
            _originator: _originator, _sharesAmount: _sharesAmount, _assetAmount: _assetAmount
        });
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the redeem asset
    function getAsset() public view returns (address) {
        return __getSyncRedeemHandlerStorage().asset;
    }

    /// @notice Returns the maximum allowed share price staleness in seconds
    function getMaxSharePriceStaleness() public view returns (uint24) {
        return __getSyncRedeemHandlerStorage().maxSharePriceStaleness;
    }

    /// @notice Returns the hook called with redemptions after they settle
    function getPostRedeemHook() public view returns (address) {
        return __getSyncRedeemHandlerStorage().postRedeemHook;
    }
}
