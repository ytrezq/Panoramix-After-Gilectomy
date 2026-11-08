// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';

import {EtherfiCashLaunchPayload} from 'src/etherfi/EtherfiCashLaunchPayload.sol';
import {
  AaveV4EtherfiCash,
  AaveV4EtherfiCashHubs,
  AaveV4EtherfiCashSpokes,
  AaveV4EtherfiCashAssets
} from 'src/etherfi/AaveV4EtherfiCash.sol';
import {IAaveV4ConfigEngine} from 'src/config-engine/interfaces/IAaveV4ConfigEngine.sol';
import {IHubConfigurator} from 'src/hub/interfaces/IHubConfigurator.sol';
import {ISpokeConfigurator} from 'src/spoke/interfaces/ISpokeConfigurator.sol';

/// @dev The payload is fully hardcoded from the AaveV4EtherfiCash address-book libraries, so
/// these tests assert the generated actions and parameters DIRECTLY against the final
/// parameter sheet ('Submit to AAVE' section, 2026-07-23 17:25 revision). Execution against a
/// live instance is covered by the fork dress rehearsal (EtherfiCashLaunchFork.t.sol), which
/// runs the full two-phase sequence and verifies the resulting on-chain state field by field.
contract EtherfiCashLaunchPayloadTest is Test {
  uint256 internal constant NUM_ASSETS = 19;

  EtherfiCashLaunchPayload internal payload;

  function setUp() public {
    payload = new EtherfiCashLaunchPayload();
  }

  function _spec(
    string memory symbol
  ) internal view returns (EtherfiCashLaunchPayload.AssetSpec memory) {
    EtherfiCashLaunchPayload.AssetSpec[] memory specs = payload.getAssetSpecs();
    for (uint256 i; i < specs.length; i++) {
      if (keccak256(bytes(specs[i].symbol)) == keccak256(bytes(symbol))) return specs[i];
    }
    revert('spec not found');
  }

  function test_specs_fullRoster() public view {
    EtherfiCashLaunchPayload.AssetSpec[] memory specs = payload.getAssetSpecs();
    assertEq(specs.length, NUM_ASSETS);

    uint256 borrowables;
    for (uint256 i; i < specs.length; i++) {
      if (specs[i].borrowable) borrowables++;
    }
    // final parameter sheet: only USDC and WETH borrowable; everything else collateral-only
    assertEq(borrowables, 2);
  }

  function test_specs_borrowableParameters() public view {
    EtherfiCashLaunchPayload.AssetSpec memory usdc = _spec('USDC');
    assertEq(usdc.underlying, AaveV4EtherfiCashAssets.USDC_UNDERLYING);
    assertEq(usdc.priceFeed, AaveV4EtherfiCashAssets.USDC_ORACLE);
    assertEq(usdc.collateralFactor, 95_00);
    assertEq(usdc.maxLiquidationBonus, 101_00); // 1%
    assertEq(usdc.liquidationFee, 10_00);
    assertTrue(usdc.borrowable);
    assertEq(usdc.liquidityFee, 5_00);
    assertEq(usdc.irData.optimalUsageRatio, 92_00);
    assertEq(usdc.irData.baseDrawnRate, 0);
    assertEq(usdc.irData.rateGrowthBeforeOptimal, 4_00);
    assertEq(usdc.irData.rateGrowthAfterOptimal, 10_00);
    assertEq(usdc.addCap, 10_000_000);
    assertEq(usdc.drawCap, 7_000_000);

    EtherfiCashLaunchPayload.AssetSpec memory weth = _spec('WETH');
    assertEq(weth.underlying, AaveV4EtherfiCashAssets.WETH_UNDERLYING);
    assertEq(weth.collateralFactor, 75_00);
    assertEq(weth.maxLiquidationBonus, 103_50); // 3.5%
    assertTrue(weth.borrowable);
    assertEq(weth.liquidityFee, 7_00);
    assertEq(weth.irData.optimalUsageRatio, 92_00);
    assertEq(weth.irData.rateGrowthBeforeOptimal, 2_35);
    assertEq(weth.irData.rateGrowthAfterOptimal, 14_00);
    assertEq(weth.addCap, 1_000);
    assertEq(weth.drawCap, 100);
  }

  function test_specs_collateralOnlyParameters() public view {
    // representative spot checks per the final sheet
    EtherfiCashLaunchPayload.AssetSpec memory weEth = _spec('weETH');
    assertEq(weEth.collateralFactor, 75_00);
    assertEq(weEth.maxLiquidationBonus, 103_50);
    assertEq(weEth.addCap, 1_000);

    EtherfiCashLaunchPayload.AssetSpec memory usdt = _spec('USDT');
    assertEq(usdt.collateralFactor, 95_00);
    assertEq(usdt.addCap, 10_000_000);

    EtherfiCashLaunchPayload.AssetSpec memory liquidUsd = _spec('liquidUSD');
    assertEq(liquidUsd.collateralFactor, 80_00);
    assertEq(liquidUsd.maxLiquidationBonus, 102_00);
    assertEq(liquidUsd.addCap, 5_000_000);

    EtherfiCashLaunchPayload.AssetSpec memory ethfi = _spec('ETHFI');
    assertEq(ethfi.collateralFactor, 30_00);
    assertEq(ethfi.maxLiquidationBonus, 105_00);
    assertEq(ethfi.addCap, 2_000_000);

    EtherfiCashLaunchPayload.AssetSpec[] memory specs = payload.getAssetSpecs();
    for (uint256 i; i < specs.length; i++) {
      if (specs[i].borrowable) continue;
      assertEq(specs[i].liquidityFee, 0, 'collateral-only must have 0 liquidity fee');
      assertEq(specs[i].drawCap, 0, 'collateral-only must have 0 draw cap');
      assertEq(specs[i].irData.optimalUsageRatio, 99_00, 'collateral-only flat curve kink');
      assertEq(specs[i].irData.rateGrowthBeforeOptimal, 0);
      assertEq(specs[i].irData.rateGrowthAfterOptimal, 0);
      assertEq(specs[i].liquidationFee, 10_00, 'liquidation fee 10% everywhere');
    }
  }

  function test_actions_hubListings() public view {
    IAaveV4ConfigEngine.AssetListing[] memory listings = payload.hubAssetListings();
    assertEq(listings.length, NUM_ASSETS);
    for (uint256 i; i < listings.length; i++) {
      assertEq(address(listings[i].hubConfigurator), AaveV4EtherfiCash.HUB_CONFIGURATOR);
      assertEq(listings[i].hub, AaveV4EtherfiCashHubs.CASH_HUB);
      assertEq(listings[i].feeReceiver, AaveV4EtherfiCashSpokes.TREASURY_SPOKE);
      assertEq(listings[i].irStrategy, AaveV4EtherfiCashHubs.CASH_HUB_IR_STRATEGY);
      assertEq(listings[i].tokenization.proxyAdminOwner, address(0), 'no tokenization at launch');
    }
  }

  function test_actions_spokeRegistrationDormant() public view {
    IAaveV4ConfigEngine.SpokeToAssetsAddition[] memory additions = payload
      .hubSpokeToAssetsAdditions();
    assertEq(additions.length, 1);
    assertEq(additions[0].spoke, AaveV4EtherfiCashSpokes.CASH_SPOKE);
    assertEq(additions[0].assets.length, NUM_ASSETS);
    for (uint256 i; i < additions[0].assets.length; i++) {
      assertFalse(
        additions[0].assets[i].config.active,
        'spoke must register DORMANT (two-phase launch)'
      );
      assertFalse(additions[0].assets[i].config.halted);
      assertEq(additions[0].assets[i].config.riskPremiumThreshold, 0);
    }
  }

  function test_actions_reserveListings() public view {
    IAaveV4ConfigEngine.ReserveListing[] memory listings = payload.spokeReserveListings();
    assertEq(listings.length, NUM_ASSETS);
    for (uint256 i; i < listings.length; i++) {
      assertEq(address(listings[i].spokeConfigurator), AaveV4EtherfiCash.SPOKE_CONFIGURATOR);
      assertEq(listings[i].spoke, AaveV4EtherfiCashSpokes.CASH_SPOKE);
      assertEq(listings[i].hub, AaveV4EtherfiCashHubs.CASH_HUB);
      assertEq(listings[i].config.collateralRisk, 0, 'risk premium unused at launch');
      assertFalse(listings[i].config.paused);
      assertFalse(listings[i].config.frozen);
      assertTrue(listings[i].config.receiveSharesEnabled);
    }
  }

  function test_actions_liquidationConfig() public view {
    IAaveV4ConfigEngine.LiquidationConfigUpdate[] memory updates = payload
      .spokeLiquidationConfigUpdates();
    assertEq(updates.length, 1);
    assertEq(updates[0].spoke, AaveV4EtherfiCashSpokes.CASH_SPOKE);
    assertEq(updates[0].targetHealthFactor, 1.24e18);
    assertEq(updates[0].healthFactorForMaxBonus, 0.9e18);
  }

  function test_actions_roleIds_followEvolutionRules() public view {
    // domain-namespaced next-free IDs (HubConfigurator 2xx, SpokeConfigurator 4xx)
    assertEq(payload.HUB_RISK_CURATOR_ROLE(), 201);
    assertEq(payload.HUB_GUARDIAN_ROLE(), 202);
    assertEq(payload.SPOKE_RISK_CURATOR_ROLE(), 401);
    assertEq(payload.SPOKE_GUARDIAN_ROLE(), 402);

    IAaveV4ConfigEngine.RoleUpdate[] memory updates = payload.accessManagerRoleUpdates();
    assertEq(updates.length, 4);
    assertEq(updates[0].label, 'HUB_RISK_CURATOR_ROLE');
    assertEq(updates[1].label, 'HUB_GUARDIAN_ROLE');
    assertEq(updates[2].label, 'SPOKE_RISK_CURATOR_ROLE');
    assertEq(updates[3].label, 'SPOKE_GUARDIAN_ROLE');
    for (uint256 i; i < updates.length; i++) {
      assertEq(updates[i].authority, AaveV4EtherfiCash.ACCESS_MANAGER);
      assertFalse(updates[i].labelUpdate); // roles are created fresh by this payload
    }
  }

  function test_actions_curatorAndGuardianRoleWiring() public view {
    // grants: curator roles to both Safes, guardian roles to both Safes + onboarded executors
    IAaveV4ConfigEngine.RoleMembership[] memory memberships = payload
      .accessManagerRoleMemberships();

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
    assertEq(memberships.length, 4 + guardianCount * 2);

    assertEq(memberships[0].account, AaveV4EtherfiCash.OPERATOR_SAFE);
    assertEq(memberships[0].roleId, payload.HUB_RISK_CURATOR_ROLE());
    assertEq(memberships[1].account, AaveV4EtherfiCash.OPERATOR_SAFE);
    assertEq(memberships[1].roleId, payload.SPOKE_RISK_CURATOR_ROLE());
    assertEq(memberships[2].account, AaveV4EtherfiCash.OWNER_SAFE);
    assertEq(memberships[3].account, AaveV4EtherfiCash.OWNER_SAFE);
    // both Safes always hold both guardian roles
    assertEq(memberships[4].account, AaveV4EtherfiCash.OWNER_SAFE);
    assertEq(memberships[4].roleId, payload.HUB_GUARDIAN_ROLE());
    assertEq(memberships[5].account, AaveV4EtherfiCash.OWNER_SAFE);
    assertEq(memberships[5].roleId, payload.SPOKE_GUARDIAN_ROLE());
    assertEq(memberships[6].account, AaveV4EtherfiCash.OPERATOR_SAFE);
    assertEq(memberships[6].roleId, payload.HUB_GUARDIAN_ROLE());
    assertEq(memberships[7].account, AaveV4EtherfiCash.OPERATOR_SAFE);
    assertEq(memberships[7].roleId, payload.SPOKE_GUARDIAN_ROLE());
    for (uint256 i; i < memberships.length; i++) {
      assertTrue(memberships[i].granted);
      assertEq(memberships[i].executionDelay, 0);
      assertEq(memberships[i].authority, AaveV4EtherfiCash.ACCESS_MANAGER);
      assertNotEq(memberships[i].account, address(0)); // staged entries must be skipped
    }

    // selector reassignments: exact partition across the four roles
    IAaveV4ConfigEngine.TargetFunctionRoleUpdate[] memory fnUpdates = payload
      .accessManagerTargetFunctionRoleUpdates();
    assertEq(fnUpdates.length, 4);

    assertEq(fnUpdates[0].target, AaveV4EtherfiCash.HUB_CONFIGURATOR);
    assertEq(fnUpdates[0].roleId, payload.HUB_RISK_CURATOR_ROLE());
    assertEq(fnUpdates[0].selectors.length, 7);
    assertEq(fnUpdates[0].selectors[0], IHubConfigurator.updateSpokeCaps.selector);
    assertEq(fnUpdates[0].selectors[1], IHubConfigurator.updateSpokeAddCap.selector);
    assertEq(fnUpdates[0].selectors[2], IHubConfigurator.updateSpokeDrawCap.selector);
    assertEq(fnUpdates[0].selectors[3], IHubConfigurator.updateInterestRateData.selector);
    assertEq(fnUpdates[0].selectors[4], IHubConfigurator.updateLiquidityFee.selector);
    assertEq(fnUpdates[0].selectors[5], IHubConfigurator.updateSpokeRiskPremiumThreshold.selector);
    assertEq(fnUpdates[0].selectors[6], IHubConfigurator.updateSpokeHalted.selector);

    assertEq(fnUpdates[1].target, AaveV4EtherfiCash.HUB_CONFIGURATOR);
    assertEq(fnUpdates[1].roleId, payload.HUB_GUARDIAN_ROLE());
    assertEq(fnUpdates[1].selectors.length, 2);
    assertEq(fnUpdates[1].selectors[0], IHubConfigurator.haltAsset.selector);
    assertEq(fnUpdates[1].selectors[1], IHubConfigurator.haltSpoke.selector);

    assertEq(fnUpdates[2].target, AaveV4EtherfiCash.SPOKE_CONFIGURATOR);
    assertEq(fnUpdates[2].roleId, payload.SPOKE_RISK_CURATOR_ROLE());
    assertEq(fnUpdates[2].selectors.length, 15);
    assertEq(fnUpdates[2].selectors[0], ISpokeConfigurator.addDynamicReserveConfig.selector);
    assertEq(fnUpdates[2].selectors[1], ISpokeConfigurator.updateDynamicReserveConfig.selector);
    assertEq(fnUpdates[2].selectors[2], ISpokeConfigurator.addCollateralFactor.selector);
    assertEq(fnUpdates[2].selectors[3], ISpokeConfigurator.updateCollateralFactor.selector);
    assertEq(fnUpdates[2].selectors[4], ISpokeConfigurator.addMaxLiquidationBonus.selector);
    assertEq(fnUpdates[2].selectors[5], ISpokeConfigurator.updateMaxLiquidationBonus.selector);
    assertEq(fnUpdates[2].selectors[6], ISpokeConfigurator.addLiquidationFee.selector);
    assertEq(fnUpdates[2].selectors[7], ISpokeConfigurator.updateLiquidationFee.selector);
    assertEq(fnUpdates[2].selectors[8], ISpokeConfigurator.updateBorrowable.selector);
    assertEq(fnUpdates[2].selectors[9], ISpokeConfigurator.updateCollateralRisk.selector);
    assertEq(
      fnUpdates[2].selectors[10],
      ISpokeConfigurator.updateLiquidationTargetHealthFactor.selector
    );
    assertEq(fnUpdates[2].selectors[11], ISpokeConfigurator.updateHealthFactorForMaxBonus.selector);
    assertEq(fnUpdates[2].selectors[12], ISpokeConfigurator.updateLiquidationBonusFactor.selector);
    assertEq(fnUpdates[2].selectors[13], ISpokeConfigurator.updatePaused.selector);
    assertEq(fnUpdates[2].selectors[14], ISpokeConfigurator.updateFrozen.selector);

    assertEq(fnUpdates[3].target, AaveV4EtherfiCash.SPOKE_CONFIGURATOR);
    assertEq(fnUpdates[3].roleId, payload.SPOKE_GUARDIAN_ROLE());
    assertEq(fnUpdates[3].selectors.length, 4);
    assertEq(fnUpdates[3].selectors[0], ISpokeConfigurator.pauseReserve.selector);
    assertEq(fnUpdates[3].selectors[1], ISpokeConfigurator.freezeReserve.selector);
    assertEq(fnUpdates[3].selectors[2], ISpokeConfigurator.pauseAllReserves.selector);
    assertEq(fnUpdates[3].selectors[3], ISpokeConfigurator.freezeAllReserves.selector);
  }

  /// @dev GUARDIAN INVARIANT: guardian roles must hold one-way stop selectors only. A resume
  /// selector on a guardian role would let a compromised hot key re-open a market mid-incident.
  function test_actions_guardianRoles_holdNoResumeSelectors() public view {
    IAaveV4ConfigEngine.TargetFunctionRoleUpdate[] memory fnUpdates = payload
      .accessManagerTargetFunctionRoleUpdates();

    bytes4[3] memory resumeSelectors = [
      IHubConfigurator.updateSpokeHalted.selector,
      ISpokeConfigurator.updatePaused.selector,
      ISpokeConfigurator.updateFrozen.selector
    ];

    for (uint256 i; i < fnUpdates.length; i++) {
      if (
        fnUpdates[i].roleId != payload.HUB_GUARDIAN_ROLE() &&
        fnUpdates[i].roleId != payload.SPOKE_GUARDIAN_ROLE()
      ) continue;
      for (uint256 j; j < fnUpdates[i].selectors.length; j++) {
        for (uint256 k; k < resumeSelectors.length; k++) {
          assertNotEq(fnUpdates[i].selectors[j], resumeSelectors[k]);
        }
      }
    }
  }

  /// @dev CURATOR COMPROMISE BOUND: the owner-only selectors must not be assigned to any role
  /// by this payload — they stay on the domain-admin roles (200/400) with the Owner Safe.
  function test_actions_noOwnerOnlySelectorLeaks() public view {
    IAaveV4ConfigEngine.TargetFunctionRoleUpdate[] memory fnUpdates = payload
      .accessManagerTargetFunctionRoleUpdates();

    bytes4[8] memory ownerOnly = [
      ISpokeConfigurator.updateReservePriceSource.selector,
      ISpokeConfigurator.updatePositionManager.selector,
      ISpokeConfigurator.addReserve.selector,
      ISpokeConfigurator.updateLiquidationConfig.selector,
      IHubConfigurator.addAsset.selector,
      IHubConfigurator.updateSpokeActive.selector,
      IHubConfigurator.updateFeeReceiver.selector,
      IHubConfigurator.updateInterestRateStrategy.selector
    ];

    for (uint256 i; i < fnUpdates.length; i++) {
      for (uint256 j; j < fnUpdates[i].selectors.length; j++) {
        for (uint256 k; k < ownerOnly.length; k++) {
          assertNotEq(fnUpdates[i].selectors[j], ownerOnly[k]);
        }
      }
    }
  }

  /// @dev No selector may appear under two roles on the same target: the AccessManager maps
  /// each (target, selector) to exactly one role, so a duplicate would mean the later update
  /// silently overwrites the earlier one.
  function test_actions_selectorPartition_noDuplicates() public view {
    IAaveV4ConfigEngine.TargetFunctionRoleUpdate[] memory fnUpdates = payload
      .accessManagerTargetFunctionRoleUpdates();

    for (uint256 a; a < fnUpdates.length; a++) {
      for (uint256 b = a + 1; b < fnUpdates.length; b++) {
        if (fnUpdates[a].target != fnUpdates[b].target) continue;
        for (uint256 i; i < fnUpdates[a].selectors.length; i++) {
          for (uint256 j; j < fnUpdates[b].selectors.length; j++) {
            assertNotEq(fnUpdates[a].selectors[i], fnUpdates[b].selectors[j]);
          }
        }
      }
    }
  }
}
