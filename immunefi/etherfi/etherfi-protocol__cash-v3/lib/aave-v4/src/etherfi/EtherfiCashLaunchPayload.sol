// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV4Payload} from 'src/config-engine/AaveV4Payload.sol';
import {
  AaveV4EtherfiCash,
  AaveV4EtherfiCashHubs,
  AaveV4EtherfiCashSpokes,
  AaveV4EtherfiCashAssets,
  AaveV4EtherfiCashCaps
} from 'src/etherfi/AaveV4EtherfiCash.sol';
import {IAaveV4ConfigEngine} from 'src/config-engine/interfaces/IAaveV4ConfigEngine.sol';
import {EngineFlags} from 'src/config-engine/libraries/EngineFlags.sol';
import {IHubConfigurator} from 'src/hub/interfaces/IHubConfigurator.sol';
import {ISpokeConfigurator} from 'src/spoke/interfaces/ISpokeConfigurator.sol';
import {IHub} from 'src/hub/interfaces/IHub.sol';
import {ISpoke} from 'src/spoke/interfaces/ISpoke.sol';
import {IAssetInterestRateStrategy} from 'src/hub/interfaces/IAssetInterestRateStrategy.sol';

/// @title EtherfiCashLaunchPayload
/// @author ether.fi
/// - Discussion: https://governance.aave.com/t/arfc-deploy-a-dedicated-aave-v4-whitelabel-instance-fully-managed-by-etherfi-on-op-mainnet-to-power-ether-fi-cash/25314
/// @notice Launch payload for the ether.fi Cash Aave V4 instance on OP Mainnet (whitelabel:
/// executed by the OWNER Safe via a delegatecall Safe transaction — no Aave Governance V3).
/// The executing Safe must hold the AccessManager admin role (0) and the configurator domain
/// admin roles (200/400), which the instance deployment grants.
///
/// Every address comes from the AaveV4EtherfiCash address-book libraries; every parameter is a
/// compile-time constant below — the payload takes no constructor arguments.
///
/// PHASE 1 of the two-phase launch (config-dormant -> verify -> activate, mirroring the Aave V4
/// Avalanche launch, proposal 504): this payload configures everything but registers every
/// spoke with active = false, so the market stays unusable until the on-chain state has been
/// verified and the Owner Safe executes EtherfiCashActivationPayload (phase 2).
///
/// Executes, in the AaveV4Payload fixed order:
///   1. AccessManager actions, in the engine's fixed sub-order: grants the curator roles
///      (201/401) to the Operator Safe (Nonce risk curator) and the Owner Safe and the
///      guardian roles (202/402) to both Safes plus the staged guardian executors, labels all
///      four roles, then reassigns the curator parameter selectors and the guardian one-way
///      stop selectors to them (see the role notes above the role ID constants).
///   2. Hub asset listings — every launch asset, with its interest rate curve and liquidity fee.
///   3. Hub spoke-to-assets addition — registers the Cash Spoke for every launch asset with its
///      add/draw caps, DORMANT (active = false).
///   4. Spoke reserve listings — lists every launch asset as a reserve on the Cash Spoke with its
///      collateral factor, max liquidation bonus and liquidation fee.
///   5. Spoke liquidation config — target health factor 1.24, health factor for max bonus 0.90
///      (liquidation bonus factor kept at the deploy default).
///
/// Parameter source: "Proposal — Aave V4 Parameters by Nonce", 'Submit to AAVE' section
/// (FINAL, 2026-07-23 17:25 revision):
///   - Only USDC and WETH are borrowable at launch; every other asset is collateral-only
///     (flat 0% curve, 0% liquidity fee, draw cap 0).
///   - Borrowable curves copied from the equivalent Aave asset with the liquidity fee halved.
///   - Risk premium (collateralRisk) is 0 bps across the board.
///
/// An asset is only included when BOTH its underlying and its price source address are set in
/// the address book; staged (zero) entries are skipped so future listings can be prepared
/// without touching payload logic.
///
/// SAFE-DELEGATECALL SAFETY: this contract must never write storage — it holds only constants,
/// so delegatecalling it from the Safe cannot corrupt Safe state.
contract EtherfiCashLaunchPayload is AaveV4Payload {
  /// @notice Full per-asset launch configuration.
  struct AssetSpec {
    string symbol;
    address underlying;
    address priceFeed;
    uint16 collateralFactor; // BPS
    uint32 maxLiquidationBonus; // BPS, 100_00 = 0% bonus
    uint16 liquidationFee; // BPS
    bool borrowable;
    uint256 liquidityFee; // BPS
    IAssetInterestRateStrategy.InterestRateData irData;
    uint40 addCap; // whole tokens
    uint40 drawCap; // whole tokens
  }

  // ------------------------------- liquidation engine (global) --------------------------------
  uint256 public constant TARGET_HEALTH_FACTOR = 1.24e18; // WAD
  uint256 public constant HEALTH_FACTOR_FOR_MAX_BONUS = 0.9e18; // WAD

  // ------------------------- curator + guardian roles (Nonce curator) -------------------------
  // Granular roles carved out of the configurator domain-admin roles, following the Roles.sol
  // evolution rules (next free IDs; domain admins are granted the new roles to retain access).
  //
  // Curator roles (Operator Safe + Owner Safe): day-to-day market management — caps, IR data,
  // liquidity fee, risk-premium threshold, dynamic reserve config, collateral factor / max
  // liquidation bonus / liquidation fee setters, reserve flags, liquidation-engine parameters,
  // and the resume switches (un-halt / un-pause / un-freeze).
  //
  // Guardian roles (Safes + staged Hypernative / automation executors, see the address book):
  // ONE-WAY EMERGENCY STOPS ONLY (halt / pause / freeze). The resume switches are deliberately
  // on the curator roles instead, so a compromised guardian hot key can at worst cause a
  // recoverable outage — it can never re-open a market mid-incident, loosen a parameter, or
  // move funds. Do not add bidirectional selectors to the guardian roles.
  //
  // CURATOR COMPROMISE BOUND — deliberately NOT delegated (stay on domain-admin 200/400, Owner
  // Safe only): updateReservePriceSource (oracle swap), updatePositionManager (see the SECURITY
  // INVARIANT in EtherFiSpokeInstance), asset/reserve/spoke listings, activation/deactivation,
  // cap resets, fee receiver/config, IR-strategy and reinvestment-controller contract swaps,
  // receive-shares flag, and the whole-struct updateLiquidationConfig.
  uint64 public constant HUB_RISK_CURATOR_ROLE = 201;
  uint64 public constant HUB_GUARDIAN_ROLE = 202;
  uint64 public constant SPOKE_RISK_CURATOR_ROLE = 401;
  uint64 public constant SPOKE_GUARDIAN_ROLE = 402;

  // ------------------------------- shared reserve parameters ----------------------------------
  uint16 internal constant LIQUIDATION_FEE = 10_00; // 10% for every reserve
  uint24 internal constant COLLATERAL_RISK = 0; // risk premium unused at launch

  // maxLiquidationBonus encoding: 100_00 == 0.00% bonus
  uint32 internal constant BONUS_1_0 = 101_00;
  uint32 internal constant BONUS_2_0 = 102_00;
  uint32 internal constant BONUS_3_5 = 103_50;
  uint32 internal constant BONUS_4_0 = 104_00;
  uint32 internal constant BONUS_5_0 = 105_00;

  constructor() AaveV4Payload(IAaveV4ConfigEngine(AaveV4EtherfiCash.CONFIG_ENGINE)) {}

  // ============================================================================================
  //                                     asset specifications
  // ============================================================================================

  /// @notice Launch asset specs, excluding any asset whose underlying or price source is unset.
  function getAssetSpecs() public pure returns (AssetSpec[] memory specs) {
    AssetSpec[19] memory all = _allAssetSpecs();

    uint256 count;
    for (uint256 i; i < all.length; i++) {
      if (all[i].underlying != address(0) && all[i].priceFeed != address(0)) count++;
    }

    specs = new AssetSpec[](count);
    uint256 j;
    for (uint256 i; i < all.length; i++) {
      if (all[i].underlying != address(0) && all[i].priceFeed != address(0)) {
        specs[j++] = all[i];
      }
    }
  }

  function _allAssetSpecs() internal pure returns (AssetSpec[19] memory specs) {
    // -------- borrowable reserves (final sheet: USDC and WETH only) --------
    // USDC — CF 95%, bonus 1%; fee 5%; kink 92%, base 0%, slope1 4%, slope2 10% (max 14%)
    specs[0] = AssetSpec({
      symbol: 'USDC',
      underlying: AaveV4EtherfiCashAssets.USDC_UNDERLYING,
      priceFeed: AaveV4EtherfiCashAssets.USDC_ORACLE,
      collateralFactor: 95_00,
      maxLiquidationBonus: BONUS_1_0,
      liquidationFee: LIQUIDATION_FEE,
      borrowable: true,
      liquidityFee: 5_00,
      irData: _ir(92_00, 0, 4_00, 10_00),
      addCap: AaveV4EtherfiCashCaps.USDC_ADD_CAP,
      drawCap: AaveV4EtherfiCashCaps.USDC_DRAW_CAP
    });
    // WETH — CF 75%, bonus 3.5%; fee 7%; kink 92%, slope1 2.35%, slope2 14% (max 16.35%)
    specs[1] = AssetSpec({
      symbol: 'WETH',
      underlying: AaveV4EtherfiCashAssets.WETH_UNDERLYING,
      priceFeed: AaveV4EtherfiCashAssets.WETH_ORACLE,
      collateralFactor: 75_00,
      maxLiquidationBonus: BONUS_3_5,
      liquidationFee: LIQUIDATION_FEE,
      borrowable: true,
      liquidityFee: 7_00,
      irData: _ir(92_00, 0, 2_35, 14_00),
      addCap: AaveV4EtherfiCashCaps.WETH_ADD_CAP,
      drawCap: AaveV4EtherfiCashCaps.WETH_DRAW_CAP
    });

    // -------- collateral-only reserves: flat 0% curve, 0% liquidity fee --------
    specs[2] = _collateralOnly(
      'USDT',
      AaveV4EtherfiCashAssets.USDT_UNDERLYING,
      AaveV4EtherfiCashAssets.USDT_ORACLE,
      95_00,
      BONUS_1_0,
      AaveV4EtherfiCashCaps.USDT_ADD_CAP
    );
    specs[3] = _collateralOnly(
      'EURC',
      AaveV4EtherfiCashAssets.EURC_UNDERLYING,
      AaveV4EtherfiCashAssets.EURC_ORACLE,
      95_00,
      BONUS_1_0,
      AaveV4EtherfiCashCaps.EURC_ADD_CAP
    );
    specs[4] = _collateralOnly(
      'frxUSD',
      AaveV4EtherfiCashAssets.FRXUSD_UNDERLYING,
      AaveV4EtherfiCashAssets.FRXUSD_ORACLE,
      95_00,
      BONUS_1_0,
      AaveV4EtherfiCashCaps.FRXUSD_ADD_CAP
    );
    specs[5] = _collateralOnly(
      'weETH',
      AaveV4EtherfiCashAssets.WEETH_UNDERLYING,
      AaveV4EtherfiCashAssets.WEETH_ORACLE,
      75_00,
      BONUS_3_5,
      AaveV4EtherfiCashCaps.WEETH_ADD_CAP
    );
    specs[6] = _collateralOnly(
      'eBTC',
      AaveV4EtherfiCashAssets.EBTC_UNDERLYING,
      AaveV4EtherfiCashAssets.EBTC_ORACLE,
      72_00,
      BONUS_5_0,
      AaveV4EtherfiCashCaps.EBTC_ADD_CAP
    );
    specs[7] = _collateralOnly(
      'eUSD',
      AaveV4EtherfiCashAssets.EUSD_UNDERLYING,
      AaveV4EtherfiCashAssets.EUSD_ORACLE,
      90_00,
      BONUS_2_0,
      AaveV4EtherfiCashCaps.EUSD_ADD_CAP
    );
    specs[8] = _collateralOnly(
      'ETHFI',
      AaveV4EtherfiCashAssets.ETHFI_UNDERLYING,
      AaveV4EtherfiCashAssets.ETHFI_ORACLE,
      30_00,
      BONUS_5_0,
      AaveV4EtherfiCashCaps.ETHFI_ADD_CAP
    );
    specs[9] = _collateralOnly(
      'sETHFI',
      AaveV4EtherfiCashAssets.SETHFI_UNDERLYING,
      AaveV4EtherfiCashAssets.SETHFI_ORACLE,
      30_00,
      BONUS_5_0,
      AaveV4EtherfiCashCaps.SETHFI_ADD_CAP
    );
    specs[10] = _collateralOnly(
      'OP',
      AaveV4EtherfiCashAssets.OP_UNDERLYING,
      AaveV4EtherfiCashAssets.OP_ORACLE,
      30_00,
      BONUS_5_0,
      AaveV4EtherfiCashCaps.OP_ADD_CAP
    );
    specs[11] = _collateralOnly(
      'WHYPE',
      AaveV4EtherfiCashAssets.WHYPE_UNDERLYING,
      AaveV4EtherfiCashAssets.WHYPE_ORACLE,
      65_00,
      BONUS_4_0,
      AaveV4EtherfiCashCaps.WHYPE_ADD_CAP
    );
    specs[12] = _collateralOnly(
      'beHYPE',
      AaveV4EtherfiCashAssets.BEHYPE_UNDERLYING,
      AaveV4EtherfiCashAssets.BEHYPE_ORACLE,
      60_00,
      BONUS_5_0,
      AaveV4EtherfiCashCaps.BEHYPE_ADD_CAP
    );
    specs[13] = _collateralOnly(
      'liquidETH',
      AaveV4EtherfiCashAssets.LIQUID_ETH_UNDERLYING,
      AaveV4EtherfiCashAssets.LIQUID_ETH_ORACLE,
      70_00,
      BONUS_5_0,
      AaveV4EtherfiCashCaps.LIQUID_ETH_ADD_CAP
    );
    specs[14] = _collateralOnly(
      'liquidBTC',
      AaveV4EtherfiCashAssets.LIQUID_BTC_UNDERLYING,
      AaveV4EtherfiCashAssets.LIQUID_BTC_ORACLE,
      70_00,
      BONUS_5_0,
      AaveV4EtherfiCashCaps.LIQUID_BTC_ADD_CAP
    );
    specs[15] = _collateralOnly(
      'liquidUSD',
      AaveV4EtherfiCashAssets.LIQUID_USD_UNDERLYING,
      AaveV4EtherfiCashAssets.LIQUID_USD_ORACLE,
      80_00,
      BONUS_2_0,
      AaveV4EtherfiCashCaps.LIQUID_USD_ADD_CAP
    );
    specs[16] = _collateralOnly(
      'liquidRESERVE',
      AaveV4EtherfiCashAssets.LIQUID_RESERVE_UNDERLYING,
      AaveV4EtherfiCashAssets.LIQUID_RESERVE_ORACLE,
      80_00,
      BONUS_2_0,
      AaveV4EtherfiCashCaps.LIQUID_RESERVE_ADD_CAP
    );
    specs[17] = _collateralOnly(
      'weEUR',
      AaveV4EtherfiCashAssets.WEEUR_UNDERLYING,
      AaveV4EtherfiCashAssets.WEEUR_ORACLE,
      80_00,
      BONUS_2_0,
      AaveV4EtherfiCashCaps.WEEUR_ADD_CAP
    );
    specs[18] = _collateralOnly(
      'liquidRWA',
      AaveV4EtherfiCashAssets.LIQUID_RWA_UNDERLYING,
      AaveV4EtherfiCashAssets.LIQUID_RWA_ORACLE,
      80_00,
      BONUS_2_0,
      AaveV4EtherfiCashCaps.LIQUID_RWA_ADD_CAP
    );
  }

  function _ir(
    uint16 optimalUsageRatio,
    uint32 baseDrawnRate,
    uint32 rateGrowthBeforeOptimal,
    uint32 rateGrowthAfterOptimal
  ) internal pure returns (IAssetInterestRateStrategy.InterestRateData memory) {
    return
      IAssetInterestRateStrategy.InterestRateData({
        optimalUsageRatio: optimalUsageRatio,
        baseDrawnRate: baseDrawnRate,
        rateGrowthBeforeOptimal: rateGrowthBeforeOptimal,
        rateGrowthAfterOptimal: rateGrowthAfterOptimal
      });
  }

  function _collateralOnly(
    string memory symbol,
    address underlying,
    address priceFeed,
    uint16 collateralFactor,
    uint32 maxLiquidationBonus,
    uint40 addCap
  ) internal pure returns (AssetSpec memory) {
    return
      AssetSpec({
        symbol: symbol,
        underlying: underlying,
        priceFeed: priceFeed,
        collateralFactor: collateralFactor,
        maxLiquidationBonus: maxLiquidationBonus,
        liquidationFee: LIQUIDATION_FEE,
        borrowable: false,
        liquidityFee: 0,
        irData: _ir(99_00, 0, 0, 0), // flat 0% — no borrow use case at launch
        addCap: addCap,
        drawCap: 0
      });
  }

  // ============================================================================================
  //                                       payload actions
  // ============================================================================================

  /// @notice Labels the curator and guardian roles on the AccessManager.
  function accessManagerRoleUpdates()
    public
    pure
    override
    returns (IAaveV4ConfigEngine.RoleUpdate[] memory updates)
  {
    updates = new IAaveV4ConfigEngine.RoleUpdate[](4);
    updates[0] = _label(HUB_RISK_CURATOR_ROLE, 'HUB_RISK_CURATOR_ROLE');
    updates[1] = _label(HUB_GUARDIAN_ROLE, 'HUB_GUARDIAN_ROLE');
    updates[2] = _label(SPOKE_RISK_CURATOR_ROLE, 'SPOKE_RISK_CURATOR_ROLE');
    updates[3] = _label(SPOKE_GUARDIAN_ROLE, 'SPOKE_GUARDIAN_ROLE');
  }

  /// @notice Moves the curator parameter selectors and the guardian stop selectors from the
  /// domain-admin roles (200/400) to the curator (201/401) and guardian (202/402) roles.
  function accessManagerTargetFunctionRoleUpdates()
    public
    pure
    override
    returns (IAaveV4ConfigEngine.TargetFunctionRoleUpdate[] memory updates)
  {
    // hub curator: caps, IR/fee/threshold parameters, resume-after-halt
    bytes4[] memory hubCuratorSelectors = new bytes4[](7);
    hubCuratorSelectors[0] = IHubConfigurator.updateSpokeCaps.selector;
    hubCuratorSelectors[1] = IHubConfigurator.updateSpokeAddCap.selector;
    hubCuratorSelectors[2] = IHubConfigurator.updateSpokeDrawCap.selector;
    hubCuratorSelectors[3] = IHubConfigurator.updateInterestRateData.selector;
    hubCuratorSelectors[4] = IHubConfigurator.updateLiquidityFee.selector;
    hubCuratorSelectors[5] = IHubConfigurator.updateSpokeRiskPremiumThreshold.selector;
    hubCuratorSelectors[6] = IHubConfigurator.updateSpokeHalted.selector;

    // hub guardian: one-way stops only (see the GUARDIAN note above the role IDs)
    bytes4[] memory hubGuardianSelectors = new bytes4[](2);
    hubGuardianSelectors[0] = IHubConfigurator.haltAsset.selector;
    hubGuardianSelectors[1] = IHubConfigurator.haltSpoke.selector;

    // spoke curator: dynamic reserve config, liquidation-economics field setters, reserve
    // flags, liquidation-engine parameters, resume-after-pause/freeze
    bytes4[] memory spokeCuratorSelectors = new bytes4[](15);
    spokeCuratorSelectors[0] = ISpokeConfigurator.addDynamicReserveConfig.selector;
    spokeCuratorSelectors[1] = ISpokeConfigurator.updateDynamicReserveConfig.selector;
    spokeCuratorSelectors[2] = ISpokeConfigurator.addCollateralFactor.selector;
    spokeCuratorSelectors[3] = ISpokeConfigurator.updateCollateralFactor.selector;
    spokeCuratorSelectors[4] = ISpokeConfigurator.addMaxLiquidationBonus.selector;
    spokeCuratorSelectors[5] = ISpokeConfigurator.updateMaxLiquidationBonus.selector;
    spokeCuratorSelectors[6] = ISpokeConfigurator.addLiquidationFee.selector;
    spokeCuratorSelectors[7] = ISpokeConfigurator.updateLiquidationFee.selector;
    spokeCuratorSelectors[8] = ISpokeConfigurator.updateBorrowable.selector;
    spokeCuratorSelectors[9] = ISpokeConfigurator.updateCollateralRisk.selector;
    spokeCuratorSelectors[10] = ISpokeConfigurator.updateLiquidationTargetHealthFactor.selector;
    spokeCuratorSelectors[11] = ISpokeConfigurator.updateHealthFactorForMaxBonus.selector;
    spokeCuratorSelectors[12] = ISpokeConfigurator.updateLiquidationBonusFactor.selector;
    spokeCuratorSelectors[13] = ISpokeConfigurator.updatePaused.selector;
    spokeCuratorSelectors[14] = ISpokeConfigurator.updateFrozen.selector;

    // spoke guardian: one-way stops only (see the GUARDIAN note above the role IDs)
    bytes4[] memory spokeGuardianSelectors = new bytes4[](4);
    spokeGuardianSelectors[0] = ISpokeConfigurator.pauseReserve.selector;
    spokeGuardianSelectors[1] = ISpokeConfigurator.freezeReserve.selector;
    spokeGuardianSelectors[2] = ISpokeConfigurator.pauseAllReserves.selector;
    spokeGuardianSelectors[3] = ISpokeConfigurator.freezeAllReserves.selector;

    updates = new IAaveV4ConfigEngine.TargetFunctionRoleUpdate[](4);
    updates[0] = IAaveV4ConfigEngine.TargetFunctionRoleUpdate({
      authority: AaveV4EtherfiCash.ACCESS_MANAGER,
      target: AaveV4EtherfiCash.HUB_CONFIGURATOR,
      selectors: hubCuratorSelectors,
      roleId: HUB_RISK_CURATOR_ROLE
    });
    updates[1] = IAaveV4ConfigEngine.TargetFunctionRoleUpdate({
      authority: AaveV4EtherfiCash.ACCESS_MANAGER,
      target: AaveV4EtherfiCash.HUB_CONFIGURATOR,
      selectors: hubGuardianSelectors,
      roleId: HUB_GUARDIAN_ROLE
    });
    updates[2] = IAaveV4ConfigEngine.TargetFunctionRoleUpdate({
      authority: AaveV4EtherfiCash.ACCESS_MANAGER,
      target: AaveV4EtherfiCash.SPOKE_CONFIGURATOR,
      selectors: spokeCuratorSelectors,
      roleId: SPOKE_RISK_CURATOR_ROLE
    });
    updates[3] = IAaveV4ConfigEngine.TargetFunctionRoleUpdate({
      authority: AaveV4EtherfiCash.ACCESS_MANAGER,
      target: AaveV4EtherfiCash.SPOKE_CONFIGURATOR,
      selectors: spokeGuardianSelectors,
      roleId: SPOKE_GUARDIAN_ROLE
    });
  }

  /// @notice Grants the curator roles to the Operator Safe (Nonce risk curator) and the Owner
  /// Safe — required by the Roles.sol evolution rules, since reassigning selectors away from
  /// the domain-admin roles would otherwise strip the Owner Safe of cap/risk access — and the
  /// guardian roles to both Safes plus the staged guardian executors from the address book
  /// (zero entries skipped until onboarded).
  function accessManagerRoleMemberships()
    public
    pure
    override
    returns (IAaveV4ConfigEngine.RoleMembership[] memory memberships)
  {
    address[4] memory guardians = [
      AaveV4EtherfiCash.OWNER_SAFE,
      AaveV4EtherfiCash.OPERATOR_SAFE,
      AaveV4EtherfiCash.GUARDIAN_HYPERNATIVE,
      AaveV4EtherfiCash.GUARDIAN_CURATOR
    ];
    uint256 guardianCount;
    for (uint256 i; i < guardians.length; i++) {
      if (guardians[i] != address(0)) guardianCount++;
    }

    memberships = new IAaveV4ConfigEngine.RoleMembership[](4 + guardianCount * 2);
    memberships[0] = _grant(HUB_RISK_CURATOR_ROLE, AaveV4EtherfiCash.OPERATOR_SAFE);
    memberships[1] = _grant(SPOKE_RISK_CURATOR_ROLE, AaveV4EtherfiCash.OPERATOR_SAFE);
    memberships[2] = _grant(HUB_RISK_CURATOR_ROLE, AaveV4EtherfiCash.OWNER_SAFE);
    memberships[3] = _grant(SPOKE_RISK_CURATOR_ROLE, AaveV4EtherfiCash.OWNER_SAFE);

    uint256 j = 4;
    for (uint256 i; i < guardians.length; i++) {
      if (guardians[i] == address(0)) continue;
      memberships[j++] = _grant(HUB_GUARDIAN_ROLE, guardians[i]);
      memberships[j++] = _grant(SPOKE_GUARDIAN_ROLE, guardians[i]);
    }
  }

  function _label(
    uint64 roleId,
    string memory label
  ) internal pure returns (IAaveV4ConfigEngine.RoleUpdate memory) {
    return
      IAaveV4ConfigEngine.RoleUpdate({
        authority: AaveV4EtherfiCash.ACCESS_MANAGER,
        roleId: roleId,
        admin: EngineFlags.KEEP_CURRENT_UINT64,
        guardian: EngineFlags.KEEP_CURRENT_UINT64,
        grantDelay: EngineFlags.KEEP_CURRENT_UINT32,
        label: label,
        labelUpdate: false
      });
  }

  function _grant(
    uint64 roleId,
    address account
  ) internal pure returns (IAaveV4ConfigEngine.RoleMembership memory) {
    return
      IAaveV4ConfigEngine.RoleMembership({
        authority: AaveV4EtherfiCash.ACCESS_MANAGER,
        roleId: roleId,
        account: account,
        granted: true,
        executionDelay: 0
      });
  }

  function hubAssetListings()
    public
    pure
    override
    returns (IAaveV4ConfigEngine.AssetListing[] memory listings)
  {
    AssetSpec[] memory specs = getAssetSpecs();
    listings = new IAaveV4ConfigEngine.AssetListing[](specs.length);
    for (uint256 i; i < specs.length; i++) {
      listings[i] = IAaveV4ConfigEngine.AssetListing({
        hubConfigurator: IHubConfigurator(AaveV4EtherfiCash.HUB_CONFIGURATOR),
        hub: AaveV4EtherfiCashHubs.CASH_HUB,
        underlying: specs[i].underlying,
        feeReceiver: AaveV4EtherfiCashSpokes.TREASURY_SPOKE,
        liquidityFee: specs[i].liquidityFee,
        irStrategy: AaveV4EtherfiCashHubs.CASH_HUB_IR_STRATEGY,
        irData: specs[i].irData,
        tokenization: IAaveV4ConfigEngine.TokenizationSpokeConfig({
          addCap: 0,
          proxyAdminOwner: address(0),
          name: '',
          symbol: ''
        })
      });
    }
  }

  function hubSpokeToAssetsAdditions()
    public
    pure
    override
    returns (IAaveV4ConfigEngine.SpokeToAssetsAddition[] memory additions)
  {
    AssetSpec[] memory specs = getAssetSpecs();
    IAaveV4ConfigEngine.SpokeAssetConfig[]
      memory assets = new IAaveV4ConfigEngine.SpokeAssetConfig[](specs.length);
    for (uint256 i; i < specs.length; i++) {
      assets[i] = IAaveV4ConfigEngine.SpokeAssetConfig({
        underlying: specs[i].underlying,
        config: IHub.SpokeConfig({
          addCap: specs[i].addCap,
          drawCap: specs[i].drawCap,
          riskPremiumThreshold: 0,
          // DORMANT LAUNCH (two-phase, mirroring the Aave V4 Avalanche activation): the market
          // is fully configured but unusable until EtherfiCashActivationPayload flips every
          // spoke active — after the live state has been verified on-chain.
          active: false,
          halted: false
        })
      });
    }

    additions = new IAaveV4ConfigEngine.SpokeToAssetsAddition[](1);
    additions[0] = IAaveV4ConfigEngine.SpokeToAssetsAddition({
      hubConfigurator: IHubConfigurator(AaveV4EtherfiCash.HUB_CONFIGURATOR),
      hub: AaveV4EtherfiCashHubs.CASH_HUB,
      spoke: AaveV4EtherfiCashSpokes.CASH_SPOKE,
      assets: assets
    });
  }

  function spokeReserveListings()
    public
    pure
    override
    returns (IAaveV4ConfigEngine.ReserveListing[] memory listings)
  {
    AssetSpec[] memory specs = getAssetSpecs();
    listings = new IAaveV4ConfigEngine.ReserveListing[](specs.length);
    for (uint256 i; i < specs.length; i++) {
      listings[i] = IAaveV4ConfigEngine.ReserveListing({
        spokeConfigurator: ISpokeConfigurator(AaveV4EtherfiCash.SPOKE_CONFIGURATOR),
        spoke: AaveV4EtherfiCashSpokes.CASH_SPOKE,
        hub: AaveV4EtherfiCashHubs.CASH_HUB,
        underlying: specs[i].underlying,
        priceSource: specs[i].priceFeed,
        config: ISpoke.ReserveConfig({
          collateralRisk: COLLATERAL_RISK,
          paused: false,
          frozen: false,
          borrowable: specs[i].borrowable,
          receiveSharesEnabled: true
        }),
        dynamicConfig: ISpoke.DynamicReserveConfig({
          collateralFactor: specs[i].collateralFactor,
          maxLiquidationBonus: specs[i].maxLiquidationBonus,
          liquidationFee: specs[i].liquidationFee
        })
      });
    }
  }

  function spokeLiquidationConfigUpdates()
    public
    pure
    override
    returns (IAaveV4ConfigEngine.LiquidationConfigUpdate[] memory updates)
  {
    updates = new IAaveV4ConfigEngine.LiquidationConfigUpdate[](1);
    updates[0] = IAaveV4ConfigEngine.LiquidationConfigUpdate({
      spokeConfigurator: ISpokeConfigurator(AaveV4EtherfiCash.SPOKE_CONFIGURATOR),
      spoke: AaveV4EtherfiCashSpokes.CASH_SPOKE,
      targetHealthFactor: TARGET_HEALTH_FACTOR,
      healthFactorForMaxBonus: HEALTH_FACTOR_FOR_MAX_BONUS,
      liquidationBonusFactor: EngineFlags.KEEP_CURRENT // deploy default, unchanged from core
    });
  }
}
