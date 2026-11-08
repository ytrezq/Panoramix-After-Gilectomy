// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {SyncRedeemHandler} from "src/components/issuance/redeem-handlers/SyncRedeemHandler.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {
    ISyncRedeemHandlerPostRedeemHook
} from "src/components/issuance/interfaces/ISyncRedeemHandlerPostRedeemHook.sol";
import {Shares} from "src/shares/Shares.sol";

import {FeeHandlerHarness} from "test/harnesses/FeeHandlerHarness.sol";
import {SyncDepositHandlerHarness} from "test/harnesses/SyncDepositHandlerHarness.sol";
import {SyncRedeemHandlerHarness} from "test/harnesses/SyncRedeemHandlerHarness.sol";
import {ValuationHandlerHarness} from "test/harnesses/ValuationHandlerHarness.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract SyncRedeemHandlerTest is TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");
    address redeemer = makeAddr("redeemer");
    ValuationHandlerHarness valuationHandler;
    SyncDepositHandlerHarness depositHandler;
    SyncRedeemHandlerHarness redeemHandler;

    address redeemAsset;
    uint8 constant ASSET_DECIMALS = 6;
    uint128 constant ONE_TO_ONE_RATE = 1e18;

    function setUp() public {
        vm.warp(100);

        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        redeemAsset = address(new MockERC20(ASSET_DECIMALS));

        depositHandler = new SyncDepositHandlerHarness(address(shares));
        depositHandler.init(redeemAsset);
        vm.prank(admin);
        shares.addDepositHandler(address(depositHandler));

        redeemHandler = new SyncRedeemHandlerHarness(address(shares));
        redeemHandler.init(redeemAsset);
        vm.prank(admin);
        shares.addRedeemHandler(address(redeemHandler));

        valuationHandler = new ValuationHandlerHarness(address(shares));
        vm.prank(admin);
        shares.setValuationHandler(address(valuationHandler));

        deal(redeemAsset, redeemer, 1000e6, true);
        vm.prank(redeemer);
        IERC20(redeemAsset).approve(address(depositHandler), type(uint256).max);
    }

    modifier whenInitializingTheHandler() {
        _;
    }

    function test_WhenTheHandlerIsAlreadyInitialized() external whenInitializingTheHandler {
        // It should revert with {InvalidInitialization} from the handler.
        vm.expectRevert(Initializable.InvalidInitialization.selector, address(redeemHandler));
        redeemHandler.init(redeemAsset);
    }

    function test_WhenTheHandlerIsNotInitialized() external whenInitializingTheHandler {
        SyncRedeemHandlerHarness handler = new SyncRedeemHandlerHarness(address(shares));
        address asset = makeAddr("asset");

        // It should emit {AssetSet}.
        vm.expectEmit(address(handler));
        emit SyncRedeemHandler.AssetSet(asset);

        handler.init(asset);

        // It should store the asset and the default config.
        assertEq(handler.getAsset(), asset, "asset not set");
        assertEq(handler.getMaxSharePriceStaleness(), 0, "staleness should default to zero");
        assertEq(handler.getPostRedeemHook(), address(0), "hook should default to zero");
    }

    modifier whenSettingTheMaxSharePriceStaleness() {
        _;
    }

    function test_WhenTheStalenessSetterIsNotTheAdminOrOwner() external whenSettingTheMaxSharePriceStaleness {
        // It should revert with {ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized} from the handler.
        vm.expectRevert(
            ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector, address(redeemHandler)
        );
        vm.prank(makeAddr("randomUser"));
        redeemHandler.setMaxSharePriceStaleness(100);
    }

    function test_WhenTheStalenessSetterIsTheAdminOrOwner() external whenSettingTheMaxSharePriceStaleness {
        uint24 maxStaleness = 3600;

        // It should emit {MaxSharePriceStalenessSet}.
        vm.expectEmit(address(redeemHandler));
        emit SyncRedeemHandler.MaxSharePriceStalenessSet({maxStaleness: maxStaleness});

        vm.prank(admin);
        redeemHandler.setMaxSharePriceStaleness(maxStaleness);

        // It should store the max share price staleness.
        assertEq(redeemHandler.getMaxSharePriceStaleness(), maxStaleness, "staleness not set");
    }

    modifier whenSettingThePost_redeemHook() {
        _;
    }

    function test_WhenTheHookSetterIsNotTheAdminOrOwner() external whenSettingThePost_redeemHook {
        // It should revert with {ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized} from the handler.
        vm.expectRevert(
            ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector, address(redeemHandler)
        );
        vm.prank(makeAddr("randomUser"));
        redeemHandler.setPostRedeemHook(makeAddr("validator"));
    }

    function test_WhenTheHookSetterIsTheAdminOrOwner() external whenSettingThePost_redeemHook {
        address validator = makeAddr("validator");

        // It should emit {PostRedeemHookSet}.
        vm.expectEmit(address(redeemHandler));
        emit SyncRedeemHandler.PostRedeemHookSet(validator);

        vm.prank(admin);
        redeemHandler.setPostRedeemHook(validator);

        // It should store the post-redeem hook.
        assertEq(redeemHandler.getPostRedeemHook(), validator, "hook not set");
    }

    modifier whenRedeemingShares() {
        _;
    }

    function test_WhenTheRedeemedSharesAmountIsZero() external whenRedeemingShares {
        __setFreshSharePrice();

        // It should revert with {SyncRedeemHandler__Redeem__ZeroShares} from the handler.
        vm.expectRevert(SyncRedeemHandler.SyncRedeemHandler__Redeem__ZeroShares.selector, address(redeemHandler));
        vm.prank(redeemer);
        redeemHandler.redeem({_sharesAmount: 0});
    }

    modifier whenTheRedeemedSharesAmountIsNon_zero() {
        _;
    }

    modifier givenTheSharePriceIsOlderThanTheStalenessCap() {
        _;
    }

    function test_GivenTheStalenessCapIsTheDefaultOfZero()
        external
        whenRedeemingShares
        whenTheRedeemedSharesAmountIsNon_zero
        givenTheSharePriceIsOlderThanTheStalenessCap
    {
        __setFreshSharePrice();
        __deposit({_assetAmount: 100e6});

        assertEq(redeemHandler.getMaxSharePriceStaleness(), 0, "staleness default");
        vm.warp(block.timestamp + 1);

        // It should revert with {SyncRedeemHandler__ValidateSharePriceTimestamp__SharePriceStale} from the handler.
        vm.expectRevert(
            SyncRedeemHandler.SyncRedeemHandler__ValidateSharePriceTimestamp__SharePriceStale.selector,
            address(redeemHandler)
        );
        vm.prank(redeemer);
        redeemHandler.redeem({_sharesAmount: 100e18});
    }

    function test_GivenTheStalenessCapIsAPositiveDuration()
        external
        whenRedeemingShares
        whenTheRedeemedSharesAmountIsNon_zero
        givenTheSharePriceIsOlderThanTheStalenessCap
    {
        __setFreshSharePrice();
        __deposit({_assetAmount: 100e6});

        vm.prank(admin);
        redeemHandler.setMaxSharePriceStaleness(60);
        vm.warp(block.timestamp + 61);

        // It should revert with {SyncRedeemHandler__ValidateSharePriceTimestamp__SharePriceStale} from the handler.
        vm.expectRevert(
            SyncRedeemHandler.SyncRedeemHandler__ValidateSharePriceTimestamp__SharePriceStale.selector,
            address(redeemHandler)
        );
        vm.prank(redeemer);
        redeemHandler.redeem({_sharesAmount: 100e18});
    }

    function test_GivenThePayoutAssetRateIsExpired()
        external
        whenRedeemingShares
        whenTheRedeemedSharesAmountIsNon_zero
    {
        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});
        vm.prank(admin);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({
                asset: redeemAsset, rate: ONE_TO_ONE_RATE, expiry: uint40(block.timestamp)
            })
        );

        // It should revert with {ValuationHandler__ValidateRate__RateExpired} from ValuationHandler.
        vm.expectRevert(
            ValuationHandler.ValuationHandler__ValidateRate__RateExpired.selector, address(valuationHandler)
        );
        vm.prank(redeemer);
        redeemHandler.redeem({_sharesAmount: 1e18});
    }

    function test_GivenThePayoutRoundsToZeroAssets()
        external
        whenRedeemingShares
        whenTheRedeemedSharesAmountIsNon_zero
    {
        __setFreshSharePrice();
        // 1 wei of a 6-decimal asset mints shares. 1 share rounds to 0 assets at a 1:1 price.
        __deposit({_assetAmount: 1});

        // It should revert with {SyncRedeemHandler__Redeem__ZeroAssets} from the handler.
        vm.expectRevert(SyncRedeemHandler.SyncRedeemHandler__Redeem__ZeroAssets.selector, address(redeemHandler));
        vm.prank(redeemer);
        redeemHandler.redeem({_sharesAmount: 1});
    }

    function test_GivenTheVaultHoldsLessOfThePayoutAssetThanTheQuotedAmount()
        external
        whenRedeemingShares
        whenTheRedeemedSharesAmountIsNon_zero
    {
        __setFreshSharePrice();
        __deposit({_assetAmount: 100e6});

        uint256 payout = IERC20(redeemAsset).balanceOf(address(shares));
        vm.prank(admin);
        shares.withdrawAssetTo({_asset: redeemAsset, _to: admin, _amount: payout});

        uint256 sharesBefore = shares.balanceOf(redeemer);

        // It should revert with {ERC20InsufficientBalance} from the payout asset.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(shares), 0, payout),
            redeemAsset
        );
        vm.prank(redeemer);
        redeemHandler.redeem({_sharesAmount: sharesBefore});

        // It should leave the caller's share balance unchanged.
        assertEq(shares.balanceOf(redeemer), sharesBefore, "shares burned despite revert");
    }

    function test_GivenTheCallerDoesNotHoldTheShares()
        external
        whenRedeemingShares
        whenTheRedeemedSharesAmountIsNon_zero
    {
        __setFreshSharePrice();
        __deposit({_assetAmount: 100e6});

        address stranger = makeAddr("stranger");
        uint256 redeemerShares = shares.balanceOf(redeemer);

        // It should revert with {ERC20InsufficientBalance} from Shares.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, stranger, 0, redeemerShares),
            address(shares)
        );
        vm.prank(stranger);
        redeemHandler.redeem({_sharesAmount: redeemerShares});
    }

    modifier givenTheVaultCanPayTheRedeem() {
        _;
    }

    function test_GivenNoExitFeeAndNoPost_redeemHook()
        external
        whenRedeemingShares
        whenTheRedeemedSharesAmountIsNon_zero
        givenTheVaultCanPayTheRedeem
    {
        __setFreshSharePrice();
        __deposit({_assetAmount: 100e6});

        // It should pay the computed assets to the caller.
        // It should burn the gross shares from the caller.
        // It should emit {Redeem}.
        __redeemAndAssert({_sharesAmount: 40e18, _expectedAssets: 40e6});
    }

    function test_GivenTheSharePriceIsExactlyMaxStalenessSecondsOld()
        external
        whenRedeemingShares
        whenTheRedeemedSharesAmountIsNon_zero
        givenTheVaultCanPayTheRedeem
    {
        __setFreshSharePrice();
        __deposit({_assetAmount: 100e6});

        vm.prank(admin);
        redeemHandler.setMaxSharePriceStaleness(60);
        vm.warp(block.timestamp + 60);

        // It should pay the computed assets to the caller.
        __redeemAndAssert({_sharesAmount: 10e18, _expectedAssets: 10e6});
    }

    function test_GivenStalenessCheckingIsDisabled()
        external
        whenRedeemingShares
        whenTheRedeemedSharesAmountIsNon_zero
        givenTheVaultCanPayTheRedeem
    {
        __setFreshSharePrice();
        __deposit({_assetAmount: 100e6});

        vm.prank(admin);
        redeemHandler.setMaxSharePriceStaleness(type(uint24).max);
        vm.warp(block.timestamp + 365 days);

        // It should pay the computed assets to the caller.
        __redeemAndAssert({_sharesAmount: 10e18, _expectedAssets: 10e6});
    }

    function test_GivenAnExitFeeIsSet()
        external
        whenRedeemingShares
        whenTheRedeemedSharesAmountIsNon_zero
        givenTheVaultCanPayTheRedeem
    {
        __setFreshSharePrice();
        __deposit({_assetAmount: 100e6});

        FeeHandlerHarness feeHandler = new FeeHandlerHarness(address(shares));
        vm.prank(admin);
        shares.setFeeHandler(address(feeHandler));

        address feeRecipient = makeAddr("feeRecipient");
        vm.prank(admin);
        feeHandler.setExitFee({_feeBps: 100, _recipient: feeRecipient});

        // 100e18 gross shares, 1% fee => 99e18 net => 99e6 assets at 1:1.
        // It should pay assets computed on the shares after the exit fee.
        __redeemAndAssert({_sharesAmount: 100e18, _expectedAssets: 99e6});

        // It should book the exit fee value owed to the fee recipient.
        assertEq(feeHandler.getValueOwedToUser(feeRecipient), 1e18, "exit fee value owed");
    }

    modifier givenAPost_redeemHookIsSet() {
        _;
    }

    function test_WhenTheHookReturns()
        external
        whenRedeemingShares
        whenTheRedeemedSharesAmountIsNon_zero
        givenTheVaultCanPayTheRedeem
        givenAPost_redeemHookIsSet
    {
        __setFreshSharePrice();
        __deposit({_assetAmount: 100e6});

        uint256 sharesAmount = 40e18;
        uint256 expectedAssets = 40e6;

        address validator = makeAddr("postRedeemValidator");
        vm.prank(admin);
        redeemHandler.setPostRedeemHook(validator);

        bytes memory expectedCall =
            abi.encodeCall(ISyncRedeemHandlerPostRedeemHook.postRedeem, (redeemer, sharesAmount, expectedAssets));
        vm.mockCall(validator, expectedCall, bytes(""));
        vm.expectCall(validator, expectedCall);

        vm.prank(redeemer);
        uint256 assetsReceived = redeemHandler.redeem({_sharesAmount: sharesAmount});

        // It should call the hook with the originator, gross shares, and assets paid.
        assertEq(assetsReceived, expectedAssets, "unexpected assets");
    }

    function test_WhenTheHookReverts()
        external
        whenRedeemingShares
        whenTheRedeemedSharesAmountIsNon_zero
        givenTheVaultCanPayTheRedeem
        givenAPost_redeemHookIsSet
    {
        __setFreshSharePrice();
        __deposit({_assetAmount: 100e6});

        uint256 sharesAmount = 40e18;
        uint256 sharesBefore = shares.balanceOf(redeemer);
        uint256 redeemerAssetsBefore = IERC20(redeemAsset).balanceOf(redeemer);
        uint256 vaultAssetsBefore = IERC20(redeemAsset).balanceOf(address(shares));

        address validator = makeAddr("postRedeemValidator");
        vm.prank(admin);
        redeemHandler.setPostRedeemHook(validator);

        vm.mockCallRevert(validator, ISyncRedeemHandlerPostRedeemHook.postRedeem.selector, bytes("rejected"));

        vm.expectRevert(bytes("rejected"), address(validator));
        vm.prank(redeemer);
        redeemHandler.redeem({_sharesAmount: sharesAmount});

        // It should leave share and asset balances unchanged.
        assertEq(shares.balanceOf(redeemer), sharesBefore, "shares burned");
        assertEq(IERC20(redeemAsset).balanceOf(redeemer), redeemerAssetsBefore, "assets paid");
        assertEq(IERC20(redeemAsset).balanceOf(address(shares)), vaultAssetsBefore, "vault assets changed");
    }

    function __setFreshSharePrice() internal {
        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});
        vm.prank(admin);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({
                asset: redeemAsset, rate: ONE_TO_ONE_RATE, expiry: uint40(type(uint40).max)
            })
        );
    }

    function __deposit(uint256 _assetAmount) internal {
        vm.prank(redeemer);
        depositHandler.deposit({_assetAmount: _assetAmount});
    }

    function __redeemAndAssert(uint256 _sharesAmount, uint256 _expectedAssets) internal {
        uint256 preRedeemerAssetBalance = IERC20(redeemAsset).balanceOf(redeemer);
        uint256 preSharesAssetBalance = IERC20(redeemAsset).balanceOf(address(shares));
        uint256 preRedeemerSharesBalance = shares.balanceOf(redeemer);

        vm.expectEmit(address(redeemHandler));
        emit SyncRedeemHandler.Redeem({redeemer: redeemer, assetAmount: _expectedAssets, sharesAmount: _sharesAmount});

        vm.prank(redeemer);
        uint256 assetsReceived = redeemHandler.redeem({_sharesAmount: _sharesAmount});

        assertEq(assetsReceived, _expectedAssets, "incorrect assets return value");
        assertEq(shares.balanceOf(redeemer), preRedeemerSharesBalance - _sharesAmount, "incorrect shares balance");
        assertEq(
            IERC20(redeemAsset).balanceOf(redeemer),
            preRedeemerAssetBalance + _expectedAssets,
            "incorrect redeemer asset balance"
        );
        assertEq(
            IERC20(redeemAsset).balanceOf(address(shares)),
            preSharesAssetBalance - _expectedAssets,
            "incorrect Shares asset balance"
        );
    }
}
