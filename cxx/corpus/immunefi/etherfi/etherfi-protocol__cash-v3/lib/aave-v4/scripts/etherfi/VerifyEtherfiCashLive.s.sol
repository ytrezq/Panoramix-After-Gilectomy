// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console2} from 'forge-std/console2.sol';

import {EtherfiCashLaunchPayload} from 'src/etherfi/EtherfiCashLaunchPayload.sol';
import {EtherFiSpokeInstance} from 'src/etherfi/EtherFiSpokeInstance.sol';
import {
  AaveV4EtherfiCash,
  AaveV4EtherfiCashHubs,
  AaveV4EtherfiCashSpokes
} from 'src/etherfi/AaveV4EtherfiCash.sol';
import {EtherfiCashScriptBase} from 'scripts/etherfi/EtherfiCashScriptBase.s.sol';
import {IHub} from 'src/hub/interfaces/IHub.sol';
import {ISpoke} from 'src/spoke/interfaces/ISpoke.sol';
import {IAssetInterestRateStrategy} from 'src/hub/interfaces/IAssetInterestRateStrategy.sol';
import {IAccessManager} from 'src/dependencies/openzeppelin/IAccessManager.sol';
import {IAaveV4ConfigEngine} from 'src/config-engine/interfaces/IAaveV4ConfigEngine.sol';

/// @title VerifyEtherfiCashLive
/// @notice Read-only check that the LIVE hub/spoke state matches the launch payload spec —
/// every listing, cap, collateral factor, bonus, curve and the liquidation config.
/// Run after the payload executes (fork rehearsal or the real post-AIP state):
///   forge script scripts/etherfi/VerifyEtherfiCashLive.s.sol --rpc-url <optimism|fork>
/// Reverts with a mismatch count if anything differs. Never broadcasts.
contract VerifyEtherfiCashLiveScript is EtherfiCashScriptBase {
  /// @dev EIP-1967 implementation slot (same constant as tests/utils/ProxyHelper.sol).
  bytes32 internal constant IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  /// @dev Must equal EtherFiSpokeInstance.ETHERFI_DATA_PROVIDER (solc disallows type-level
  /// access to that constant from here).
  address internal constant EXPECTED_ETHERFI_DATA_PROVIDER =
    0xDC515Cb479a64552c5A11a57109C314E40A1A778;

  uint256 internal mismatches;

  function verify() external returns (uint256) {
    _requireOpMainnet();

    // two-phase launch: EXPECT_ACTIVE=false verifies the dormant state between phase 1
    // (config payload) and phase 2 (activation payload); default checks the final live state
    bool expectActive = vm.envOr('EXPECT_ACTIVE', true);

    // in-memory reference: fully hardcoded from the address-book libraries
    EtherfiCashLaunchPayload expectedPayload = new EtherfiCashLaunchPayload();

    IHub hub = IHub(AaveV4EtherfiCashHubs.CASH_HUB);
    ISpoke spoke = ISpoke(AaveV4EtherfiCashSpokes.CASH_SPOKE);
    IAssetInterestRateStrategy irStrategy = IAssetInterestRateStrategy(
      AaveV4EtherfiCashHubs.CASH_HUB_IR_STRATEGY
    );

    // the Cash Spoke must run the gated EtherFiSpokeInstance implementation: check the proxy's
    // EIP-1967 implementation slot against the registry, and that the implementation behind the
    // proxy reports the expected ether.fi data provider (a stock SpokeInstance would revert here)
    address spokeImplementation = address(
      uint160(uint256(vm.load(address(spoke), IMPLEMENTATION_SLOT)))
    );
    _check(
      'spoke',
      'implementation (EtherFiSpokeInstance)',
      uint160(spokeImplementation),
      uint160(AaveV4EtherfiCashSpokes.CASH_SPOKE_IMPLEMENTATION)
    );
    _check(
      'spoke',
      'ETHERFI_DATA_PROVIDER',
      uint160(EtherFiSpokeInstance(address(spoke)).ETHERFI_DATA_PROVIDER()),
      uint160(EXPECTED_ETHERFI_DATA_PROVIDER)
    );

    EtherfiCashLaunchPayload.AssetSpec[] memory specs = expectedPayload.getAssetSpecs();
    console2.log('verifying', specs.length, 'assets against live state');

    for (uint256 i; i < specs.length; i++) {
      EtherfiCashLaunchPayload.AssetSpec memory spec = specs[i];

      uint256 assetId = hub.getAssetId(spec.underlying);
      IHub.Asset memory asset = hub.getAsset(assetId);
      _check(spec.symbol, 'liquidityFee', asset.liquidityFee, spec.liquidityFee);

      IAssetInterestRateStrategy.InterestRateData memory ir = irStrategy.getInterestRateData(
        assetId
      );
      _check(spec.symbol, 'kink', ir.optimalUsageRatio, spec.irData.optimalUsageRatio);
      _check(spec.symbol, 'baseRate', ir.baseDrawnRate, spec.irData.baseDrawnRate);
      _check(
        spec.symbol,
        'slope1',
        ir.rateGrowthBeforeOptimal,
        spec.irData.rateGrowthBeforeOptimal
      );
      _check(spec.symbol, 'slope2', ir.rateGrowthAfterOptimal, spec.irData.rateGrowthAfterOptimal);

      IHub.SpokeConfig memory spokeConfig = hub.getSpokeConfig(assetId, address(spoke));
      _check(spec.symbol, 'active', spokeConfig.active ? 1 : 0, expectActive ? 1 : 0);
      _check(spec.symbol, 'halted', spokeConfig.halted ? 1 : 0, 0);
      _check(spec.symbol, 'addCap', spokeConfig.addCap, spec.addCap);
      _check(spec.symbol, 'drawCap', spokeConfig.drawCap, spec.drawCap);
      _check(spec.symbol, 'riskPremiumThreshold', spokeConfig.riskPremiumThreshold, 0);

      uint256 reserveId = spoke.getReserveId(address(hub), assetId);
      ISpoke.ReserveConfig memory reserveConfig = spoke.getReserveConfig(reserveId);
      _check(spec.symbol, 'collateralRisk', reserveConfig.collateralRisk, 0);
      _check(spec.symbol, 'paused', reserveConfig.paused ? 1 : 0, 0);
      _check(spec.symbol, 'frozen', reserveConfig.frozen ? 1 : 0, 0);
      _check(spec.symbol, 'borrowable', reserveConfig.borrowable ? 1 : 0, spec.borrowable ? 1 : 0);

      ISpoke.DynamicReserveConfig memory dyn = spoke.getDynamicReserveConfig(reserveId, 0);
      _check(spec.symbol, 'collateralFactor', dyn.collateralFactor, spec.collateralFactor);
      _check(spec.symbol, 'maxLiquidationBonus', dyn.maxLiquidationBonus, spec.maxLiquidationBonus);
      _check(spec.symbol, 'liquidationFee', dyn.liquidationFee, spec.liquidationFee);

      console2.log(string.concat('  [checked] ', spec.symbol));
    }

    ISpoke.LiquidationConfig memory liq = spoke.getLiquidationConfig();
    _check(
      'spoke',
      'targetHealthFactor',
      liq.targetHealthFactor,
      expectedPayload.TARGET_HEALTH_FACTOR()
    );
    _check(
      'spoke',
      'healthFactorForMaxBonus',
      liq.healthFactorForMaxBonus,
      expectedPayload.HEALTH_FACTOR_FOR_MAX_BONUS()
    );

    // curator + guardian role wiring (memberships and selector reassignments; every selector
    // moved by the payload is checked, so a selector accidentally left on the domain-admin
    // roles (200/400) — or moved to the wrong role — fails verification)
    IAccessManager accessManager = IAccessManager(AaveV4EtherfiCash.ACCESS_MANAGER);
    uint64 hubCurator = expectedPayload.HUB_RISK_CURATOR_ROLE();
    uint64 hubGuardian = expectedPayload.HUB_GUARDIAN_ROLE();
    uint64 spokeCurator = expectedPayload.SPOKE_RISK_CURATOR_ROLE();
    uint64 spokeGuardian = expectedPayload.SPOKE_GUARDIAN_ROLE();

    address[2] memory safes = [AaveV4EtherfiCash.OPERATOR_SAFE, AaveV4EtherfiCash.OWNER_SAFE];
    for (uint256 i; i < safes.length; i++) {
      (bool isMember, ) = accessManager.hasRole(hubCurator, safes[i]);
      _check('accessManager', 'hasRole(hubCurator)', isMember ? 1 : 0, 1);
      (isMember, ) = accessManager.hasRole(spokeCurator, safes[i]);
      _check('accessManager', 'hasRole(spokeCurator)', isMember ? 1 : 0, 1);
      (isMember, ) = accessManager.hasRole(hubGuardian, safes[i]);
      _check('accessManager', 'hasRole(hubGuardian)', isMember ? 1 : 0, 1);
      (isMember, ) = accessManager.hasRole(spokeGuardian, safes[i]);
      _check('accessManager', 'hasRole(spokeGuardian)', isMember ? 1 : 0, 1);
    }
    address[2] memory stagedGuardians = [
      AaveV4EtherfiCash.GUARDIAN_HYPERNATIVE,
      AaveV4EtherfiCash.GUARDIAN_CURATOR
    ];
    for (uint256 i; i < stagedGuardians.length; i++) {
      if (stagedGuardians[i] == address(0)) continue;
      (bool isMember, ) = accessManager.hasRole(hubGuardian, stagedGuardians[i]);
      _check('accessManager', 'hasRole(hubGuardian,executor)', isMember ? 1 : 0, 1);
      (isMember, ) = accessManager.hasRole(spokeGuardian, stagedGuardians[i]);
      _check('accessManager', 'hasRole(spokeGuardian,executor)', isMember ? 1 : 0, 1);
    }

    IAaveV4ConfigEngine.TargetFunctionRoleUpdate[] memory fnUpdates = expectedPayload
      .accessManagerTargetFunctionRoleUpdates();
    for (uint256 i; i < fnUpdates.length; i++) {
      for (uint256 j; j < fnUpdates[i].selectors.length; j++) {
        _check(
          'accessManager',
          string.concat('selector role (', vm.toString(fnUpdates[i].roleId), ')'),
          accessManager.getTargetFunctionRole(fnUpdates[i].target, fnUpdates[i].selectors[j]),
          fnUpdates[i].roleId
        );
      }
    }

    require(mismatches == 0, string.concat('MISMATCHES: ', vm.toString(mismatches)));
    console2.log(
      expectActive
        ? 'VERIFIED: live state matches the launch payload spec (ACTIVE)'
        : 'VERIFIED: live state matches the launch payload spec (DORMANT - ready for activation)'
    );
    return specs.length;
  }

  function _check(
    string memory symbol,
    string memory field,
    uint256 actual,
    uint256 expected
  ) internal {
    if (actual != expected) {
      console2.log(
        string.concat(
          '  [MISMATCH] ',
          symbol,
          '.',
          field,
          ': actual=',
          vm.toString(actual),
          ' expected=',
          vm.toString(expected)
        )
      );
      mismatches++;
    }
  }
}
