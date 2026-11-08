// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import { IAccessManaged } from "contracts/utils/AccessManagedUpgradeable.sol";
import { Savings } from "contracts/savings/Savings.sol";

import { SavingsNameable } from "contracts/savings/nameable/SavingsNameable.sol";
import { Vm } from "@forge-std/Vm.sol";
import "contracts/utils/Errors.sol" as Errors;
import "../Fixture.sol";
import { SavingsLegacyMock } from "../mock/SavingsLegacyMock.sol";

contract SavingsUpgradeTest is Fixture {
  uint256 internal constant _initDeposit = 1e18;

  function setUp() public override {
    super.setUp();

    saving = SavingsNameable(deploySavings(governor, address(tokenP), address(accessManager)));
    vm.label(address(saving), "saving");

    vm.startPrank(governor);
    accessManager.setTargetFunctionRole(address(saving), getGovernorSavingsSelectorAccess(), GOVERNOR_ROLE);
    vm.stopPrank();
  }

  function test_deploySavings() public {
    assertEq(IERC20Metadata(saving).name(), name);
    assertEq(IERC20Metadata(saving).symbol(), symbol);
    assertEq(saving.previewRedeem(Constants.BASE_18), Constants.BASE_18);
    assertEq(saving.previewWithdraw(Constants.BASE_18), Constants.BASE_18);
    assertEq(saving.previewMint(Constants.BASE_18), Constants.BASE_18);
    assertEq(saving.previewDeposit(Constants.BASE_18), Constants.BASE_18);
    assertEq(saving.totalAssets(), Constants.BASE_18);
    assertEq(saving.totalSupply(), Constants.BASE_18);
    assertEq(saving.maxRate(), 0);
    assertEq(saving.paused(), 0);
    assertEq(saving.lastUpdate(), block.timestamp);
    assertEq(saving.rate(), 0);
  }

  function test_upgradeSavings() public {
    string memory newName = "new Staked USDp";
    string memory newSymbol = "new sUSDp";
    vm.startPrank(governor);

    address newSavingsImpl = address(new SavingsNameable());
    saving.upgradeToAndCall(newSavingsImpl, "");

    saving.setNameAndSymbol(newName, newSymbol);

    assertEq(IERC20Metadata(saving).name(), newName);
    assertEq(IERC20Metadata(saving).symbol(), newSymbol);
    assertEq(saving.previewRedeem(Constants.BASE_18), Constants.BASE_18);
    assertEq(saving.previewWithdraw(Constants.BASE_18), Constants.BASE_18);
    assertEq(saving.previewMint(Constants.BASE_18), Constants.BASE_18);
    assertEq(saving.previewDeposit(Constants.BASE_18), Constants.BASE_18);
    assertEq(saving.totalAssets(), Constants.BASE_18);
    assertEq(saving.totalSupply(), Constants.BASE_18);
    assertEq(saving.maxRate(), 0);
    assertEq(saving.paused(), 0);
    assertEq(saving.lastUpdate(), block.timestamp);
    assertEq(saving.rate(), 0);
  }

  function test_upgradeSavings_RevertWhen_CallerIsNotGovernor() public {
    vm.startPrank(alice);
    address newSavingsImpl = address(new SavingsNameable());
    vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
    saving.upgradeToAndCall(newSavingsImpl, "");
  }

  function test_upgradeFromLegacy_neutralizesDonationAttack() public {
    SavingsNameable savingProxy = _deployLegacySavings();
    _depositInSavings(savingProxy, 100e18, alice);

    uint256 priceBeforeDonation = savingProxy.previewRedeem(1e18);

    uint256 donation = 10_000_000e18;
    deal(address(tokenP), address(this), donation);
    IERC20(address(tokenP)).transfer(address(savingProxy), donation);

    assertGt(
      savingProxy.previewRedeem(1e18),
      priceBeforeDonation * 1000,
      "legacy: donation must inflate share price"
    );

    _upgradeSavings(savingProxy);

    assertGe(
      savingProxy.storedAssets(),
      _initDeposit + 100e18 + donation,
      "post-upgrade storedAssets includes pre-upgrade donation as backing"
    );

    uint256 priceAfterUpgrade = savingProxy.previewRedeem(1e18);

    uint256 newDonation = 50_000_000e18;
    deal(address(tokenP), address(this), newDonation);
    IERC20(address(tokenP)).transfer(address(savingProxy), newDonation);

    assertEq(savingProxy.previewRedeem(1e18), priceAfterUpgrade, "new donation must not move price");
    assertEq(savingProxy.totalAssets(), savingProxy.storedAssets(), "totalAssets tracks storedAssets");

    vm.prank(governor);
    assertEq(savingProxy.recoverSurplus(treasury), newDonation, "new donation recoverable");
  }

  function test_upgradeFromLegacy_existingDepositorsCanStillRedeem() public {
    SavingsNameable savingProxy = _deployLegacySavings();
    _depositInSavings(savingProxy, 100e18, alice);

    _upgradeSavings(savingProxy);

    uint256 aliceShares = savingProxy.balanceOf(alice);
    vm.prank(alice);
    uint256 received = savingProxy.redeem(aliceShares, alice, alice);
    assertGt(received, 0, "alice can redeem after upgrade");
    assertEq(savingProxy.balanceOf(alice), 0, "shares burned");
  }

  function test_upgradeFromLegacy_initializeStoredAssetsRevertsWhenCalledTwice() public {
    SavingsNameable savingProxy = _deployLegacySavings();
    _upgradeSavings(savingProxy);

    vm.prank(governor);
    vm.expectRevert(bytes4(keccak256("InvalidInitialization()")));
    savingProxy.initializeStoredAssets();
  }

  function test_initializeStoredAssets_RevertWhen_CallerUnauthorized() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
    saving.initializeStoredAssets();
  }

  function test_initializeStoredAssets_RevertWhen_AccrualStale() public {
    skip(30 minutes + 1);
    vm.prank(governor);
    vm.expectRevert(Errors.StaleAccrual.selector);
    saving.initializeStoredAssets();
  }

  function test_initializeStoredAssets_SucceedsWithinFreshnessWindow() public {
    skip(30 minutes);
    vm.prank(governor);
    saving.initializeStoredAssets();
    assertEq(saving.storedAssets(), IERC20(address(tokenP)).balanceOf(address(saving)));
  }

  function test_initializeStoredAssets_reAnchorsLastUpdate() public {
    skip(20 minutes);
    vm.prank(governor);
    saving.initializeStoredAssets();
    assertEq(saving.lastUpdate(), block.timestamp);
  }

  function test_nonAtomicUpgrade_revertsEntryPointsUntilInitialized() public {
    SavingsNameable savingProxy = _deployLegacySavings();
    _depositInSavings(savingProxy, 100e18, alice);

    SavingsNameable newImpl = new SavingsNameable();
    vm.prank(governor);
    UUPSUpgradeable(address(savingProxy)).upgradeToAndCall(address(newImpl), "");

    assertEq(savingProxy.storedAssets(), 0, "storedAssets left unseeded by non-atomic upgrade");
    assertGt(savingProxy.totalSupply(), 0);

    deal(address(tokenP), alice, 1e18);
    vm.startPrank(alice);
    IERC20(address(tokenP)).approve(address(savingProxy), 1e18);
    vm.expectRevert(Errors.NotInitialized.selector);
    savingProxy.deposit(1e18, alice);
    vm.stopPrank();

    uint256 aliceShares = savingProxy.balanceOf(alice);
    vm.prank(alice);
    vm.expectRevert(Errors.NotInitialized.selector);
    savingProxy.redeem(aliceShares, alice, alice);
  }

  function test_upgradeFromLegacy_postUpgradePauseUnpauseWorks() public {
    SavingsNameable savingProxy = _deployLegacySavings();
    _upgradeSavings(savingProxy);

    vm.prank(governor);
    accessManager.setTargetFunctionRole(address(savingProxy), getGuardianSavingsSelectorAccess(), GUARDIAN_ROLE);

    vm.prank(guardian);
    savingProxy.pause();
    deal(address(tokenP), alice, 1e18);
    vm.startPrank(alice);
    IERC20(address(tokenP)).approve(address(savingProxy), 1e18);
    vm.expectRevert(Errors.Paused.selector);
    savingProxy.deposit(1e18, alice);
    vm.stopPrank();

    vm.prank(guardian);
    savingProxy.unpause();
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                       HELPERS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _deployLegacySavings() internal returns (SavingsNameable savingProxy) {
    vm.startPrank(governor);

    deal(address(tokenP), governor, _initDeposit);

    SavingsLegacyMock legacyImpl = new SavingsLegacyMock();
    address futureProxy = vm.computeCreateAddress(governor, vm.getNonce(governor));
    IERC20(address(tokenP)).approve(futureProxy, _initDeposit);

    savingProxy = SavingsNameable(
      address(
        new ERC1967Proxy(
          address(legacyImpl),
          abi.encodeWithSelector(
            legacyImpl.initialize.selector, accessManager, IERC20Metadata(address(tokenP)), name, symbol, 1
          )
        )
      )
    );

    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = UUPSUpgradeable.upgradeToAndCall.selector;
    accessManager.setTargetFunctionRole(address(savingProxy), selectors, GOVERNOR_ROLE);

    vm.stopPrank();

    vm.label(address(savingProxy), "savingProxy");
  }

  function _depositInSavings(SavingsNameable savingProxy, uint256 amount, address depositor) internal {
    deal(address(tokenP), depositor, amount);
    vm.startPrank(depositor);
    IERC20(address(tokenP)).approve(address(savingProxy), amount);
    savingProxy.deposit(amount, depositor);
    vm.stopPrank();
  }

  function _upgradeSavings(SavingsNameable savingProxy) internal {
    SavingsNameable newImpl = new SavingsNameable();
    vm.prank(governor);
    UUPSUpgradeable(address(savingProxy)).upgradeToAndCall(
      address(newImpl),
      abi.encodeWithSelector(Savings.initializeStoredAssets.selector)
    );

    assertEq(
      savingProxy.storedAssets(),
      IERC20(address(tokenP)).balanceOf(address(savingProxy)),
      "post-upgrade storedAssets == balance"
    );
  }
}

contract SavingsDonationAttackTest is Fixture {
  function setUp() public override {
    super.setUp();

    saving = SavingsNameable(deploySavings(governor, address(tokenP), address(accessManager)));
    vm.label(address(saving), "saving");

    vm.startPrank(governor);
    accessManager.setTargetFunctionRole(address(saving), getGovernorSavingsSelectorAccess(), GOVERNOR_ROLE);
    accessManager.setTargetFunctionRole(address(saving), getGuardianSavingsSelectorAccess(), GUARDIAN_ROLE);
    saving.setMaxRate(type(uint256).max);
    vm.stopPrank();
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                       DONATION ATTACK
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function test_DonationAttackIsNeutralized() public {
    uint256 attackerDeposit = 1e18;
    uint256 attackerShares = _depositInSavings(attackerDeposit, alice);

    uint256 priceBefore = saving.previewRedeem(1e18);
    uint256 totalAssetsBefore = saving.totalAssets();
    uint256 storedBefore = saving.storedAssets();

    uint256 donation = 225_000_000e18;
    deal(address(tokenP), address(this), donation);
    IERC20(address(tokenP)).transfer(address(saving), donation);

    assertEq(saving.totalAssets(), totalAssetsBefore, "totalAssets unchanged by donation");
    assertEq(saving.previewRedeem(1e18), priceBefore, "share price unchanged");
    assertEq(saving.storedAssets(), storedBefore, "storedAssets unchanged");

    uint256 expectedOut = saving.previewRedeem(attackerShares);
    vm.prank(alice);
    uint256 received = saving.redeem(attackerShares, alice, alice);
    assertEq(received, expectedOut, "redeem returns preview");
    assertLe(received, attackerDeposit + 1, "attacker did not capture donation");

    uint256 surplus = IERC20(address(tokenP)).balanceOf(address(saving)) - saving.storedAssets();
    assertEq(surplus, donation, "donation persists as recoverable surplus");
  }

  function test_DonationAttackDormantAccrualIsAccountedNotSurplus() public {
    _depositInSavings(1e18, alice);

    vm.startPrank(guardian);
    uint208 ratePerSecond = uint208(uint256(BASE_27) / SECONDS_PER_YEAR / 100); // ~1% APY
    saving.setRate(ratePerSecond);
    vm.stopPrank();

    skip(39 days);

    uint256 storedBefore = saving.storedAssets();
    _depositInSavings(1, alice); // any interaction triggers _accrue

    assertGt(saving.storedAssets(), storedBefore, "accrual increases storedAssets");
    assertEq(
      IERC20(address(tokenP)).balanceOf(address(saving)) - saving.storedAssets(),
      0,
      "minted accrual is backing, not surplus"
    );
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                       RECOVER SURPLUS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function test_RecoverSurplusReturnsZeroWhenNoDonation() public {
    _depositInSavings(1e18, alice);

    vm.prank(governor);
    uint256 recovered = saving.recoverSurplus(treasury);
    assertEq(recovered, 0, "no surplus expected");
    assertEq(IERC20(address(tokenP)).balanceOf(treasury), 0, "treasury untouched");
  }

  function test_RecoverSurplusDrainsDonationWithoutAffectingDepositors() public {
    uint256 honestShares = _depositInSavings(1e18, alice);
    uint256 storedBeforeDonation = saving.storedAssets();

    uint256 donation = 5_000_000e18;
    deal(address(tokenP), address(this), donation);
    IERC20(address(tokenP)).transfer(address(saving), donation);

    vm.expectEmit(true, false, false, true, address(saving));
    emit Savings.SurplusRecovered(treasury, donation);
    vm.prank(governor);
    uint256 recovered = saving.recoverSurplus(treasury);

    assertEq(recovered, donation, "recovered amount");
    assertEq(IERC20(address(tokenP)).balanceOf(treasury), donation, "treasury credited");
    assertEq(saving.storedAssets(), storedBeforeDonation, "storedAssets stable");
    assertEq(
      IERC20(address(tokenP)).balanceOf(address(saving)),
      saving.storedAssets(),
      "vault balance == storedAssets after recover"
    );

    vm.prank(alice);
    uint256 received = saving.redeem(honestShares, alice, alice);
    assertGt(received, 0, "alice can still redeem");
  }

  function test_RecoverSurplusRevertsOnZeroAddress() public {
    deal(address(tokenP), address(saving), 100e18);

    vm.prank(governor);
    vm.expectRevert(Errors.ZeroAddress.selector);
    saving.recoverSurplus(address(0));
  }

  function test_RecoverSurplusRevertsWhenCallerNotGovernor() public {
    deal(address(tokenP), address(saving), 100e18);

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
    saving.recoverSurplus(treasury);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                       PAUSE / UNPAUSE
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function test_PauseRevertsWhenAlreadyPaused() public {
    vm.startPrank(guardian);
    saving.pause();
    vm.expectRevert(Errors.AlreadyPaused.selector);
    saving.pause();
    vm.stopPrank();
  }

  function test_UnpauseRevertsWhenNotPaused() public {
    vm.prank(guardian);
    vm.expectRevert(Errors.NotPaused.selector);
    saving.unpause();
  }

  function test_PauseThenUnpauseRestoresInteractions() public {
    _depositInSavings(1e18, alice);

    vm.startPrank(guardian);
    saving.pause();
    saving.unpause();
    vm.stopPrank();

    _depositInSavings(1e18, alice);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                       HELPERS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _depositInSavings(uint256 amount, address depositor) internal returns (uint256 shares) {
    deal(address(tokenP), depositor, amount);
    vm.startPrank(depositor);
    IERC20(address(tokenP)).approve(address(saving), amount);
    shares = saving.deposit(amount, depositor);
    vm.stopPrank();
  }
}

contract SavingsInitializeValidationTest is Fixture {
  SavingsNameable internal savingsImpl;

  function setUp() public override {
    super.setUp();
    savingsImpl = new SavingsNameable();
    deal({ token: address(tokenP), to: governor, give: 1e18 });
  }

  function _initData(string memory n, string memory s, uint256 divizer) internal view returns (bytes memory) {
    return abi.encodeWithSelector(
      savingsImpl.initialize.selector, address(accessManager), IERC20Metadata(address(tokenP)), n, s, divizer
    );
  }

  function test_initialize_RevertWhen_DivizerIsZero() public {
    vm.prank(governor);
    vm.expectRevert(InvalidParam.selector);
    new ERC1967Proxy(address(savingsImpl), _initData(name, symbol, 0));
  }

  function test_initialize_RevertWhen_DivizerExceedsBase18() public {
    vm.prank(governor);
    vm.expectRevert(InvalidParam.selector);
    new ERC1967Proxy(address(savingsImpl), _initData(name, symbol, Constants.BASE_18 + 1));
  }

  function test_initialize_RevertWhen_DivizerExceedsAssetDecimalsScale() public {
    uint256 divizer = 10 ** uint256(IERC20Metadata(address(tokenP)).decimals()) + 1;
    vm.prank(governor);
    vm.expectRevert(InvalidParam.selector);
    new ERC1967Proxy(address(savingsImpl), _initData(name, symbol, divizer));
  }

  function test_initialize_RevertWhen_NameIsEmpty() public {
    vm.prank(governor);
    vm.expectRevert(InvalidParam.selector);
    new ERC1967Proxy(address(savingsImpl), _initData("", symbol, 1));
  }

  function test_initialize_RevertWhen_SymbolIsEmpty() public {
    vm.prank(governor);
    vm.expectRevert(InvalidParam.selector);
    new ERC1967Proxy(address(savingsImpl), _initData(name, "", 1));
  }

  function test_initialize_SucceedsWithValidDivizer() public {
    vm.startPrank(governor);
    address futureProxy = vm.computeCreateAddress(governor, vm.getNonce(governor));
    IERC20(address(tokenP)).approve(futureProxy, 1e18);
    address proxy = address(new ERC1967Proxy(address(savingsImpl), _initData(name, symbol, 1)));
    vm.stopPrank();
    SavingsNameable s = SavingsNameable(proxy);
    assertGt(s.totalSupply(), 0, "dead-share moat must be planted");
    assertGt(s.totalAssets(), 0, "seed assets must be deposited");
    assertEq(IERC20Metadata(s).name(), name);
    assertEq(IERC20Metadata(s).symbol(), symbol);
  }
}

contract SavingsMaxViewsPauseTest is Fixture {
  function setUp() public override {
    super.setUp();
    saving = SavingsNameable(deploySavings(governor, address(tokenP), address(accessManager)));
    vm.label(address(saving), "saving");

    vm.startPrank(governor);
    accessManager.setTargetFunctionRole(address(saving), getGuardianSavingsSelectorAccess(), GUARDIAN_ROLE);
    vm.stopPrank();
  }

  function _pause() internal {
    vm.prank(guardian);
    saving.pause();
    assertEq(saving.paused(), 1, "savings must be paused");
  }

  function test_maxViews_returnZeroWhenPaused() public {
    assertEq(saving.maxDeposit(alice), type(uint256).max);
    assertEq(saving.maxMint(alice), type(uint256).max);

    _pause();

    assertEq(saving.maxDeposit(alice), 0, "maxDeposit must be 0 when paused");
    assertEq(saving.maxMint(alice), 0, "maxMint must be 0 when paused");
    assertEq(saving.maxWithdraw(alice), 0, "maxWithdraw must be 0 when paused");
    assertEq(saving.maxRedeem(alice), 0, "maxRedeem must be 0 when paused");
  }

  function test_maxViews_restoredAfterUnpause() public {
    _pause();

    vm.prank(guardian);
    saving.unpause();
    assertEq(saving.paused(), 0, "savings must be unpaused");

    assertEq(saving.maxDeposit(alice), type(uint256).max);
    assertEq(saving.maxMint(alice), type(uint256).max);
  }

  function test_maxWithdraw_reflectsOwnerBalanceWhenPaused() public {
    deal({ token: address(tokenP), to: alice, give: Constants.BASE_18 });
    vm.startPrank(alice);
    IERC20(address(tokenP)).approve(address(saving), Constants.BASE_18);
    uint256 shares = saving.deposit(Constants.BASE_18, alice);
    vm.stopPrank();
    assertGt(shares, 0);

    uint256 withdrawableBefore = saving.maxWithdraw(alice);
    uint256 redeemableBefore = saving.maxRedeem(alice);
    assertGt(withdrawableBefore, 0);
    assertEq(redeemableBefore, shares);

    _pause();

    assertEq(saving.maxWithdraw(alice), 0, "maxWithdraw must be 0 when paused even with balance");
    assertEq(saving.maxRedeem(alice), 0, "maxRedeem must be 0 when paused even with balance");
  }
}

contract SavingsSetMaxRateTest is Fixture {
  event MaxRateUpdated(uint256 newMaxRate);
  event RateUpdated(uint256 newRate);

  uint208 internal constant _initialRate = 10 ** (27 - 8);
  uint256 internal constant _initialMaxRate = 10 ** (27 - 6);

  function setUp() public override {
    super.setUp();
    saving = SavingsNameable(deploySavings(governor, address(tokenP), address(accessManager)));
    vm.label(address(saving), "saving");

    vm.startPrank(governor);
    accessManager.setTargetFunctionRole(address(saving), getGovernorSavingsSelectorAccess(), GOVERNOR_ROLE);
    accessManager.setTargetFunctionRole(address(saving), getGuardianSavingsSelectorAccess(), GUARDIAN_ROLE);
    saving.setMaxRate(_initialMaxRate);
    vm.stopPrank();

    vm.prank(guardian);
    saving.setRate(_initialRate);
  }

  function test_setMaxRate_clampsRateWhenBelowCurrent() public {
    uint256 newMaxRate = uint256(_initialRate) / 2;

    vm.expectEmit(address(saving));
    emit RateUpdated(newMaxRate);
    vm.expectEmit(address(saving));
    emit MaxRateUpdated(newMaxRate);
    vm.prank(governor);
    saving.setMaxRate(newMaxRate);

    assertEq(saving.maxRate(), newMaxRate);
    assertEq(saving.rate(), uint208(newMaxRate), "rate must be clamped to new cap");
    assertLe(saving.rate(), saving.maxRate(), "rate <= maxRate invariant must hold");
  }

  function test_setMaxRate_leavesRateUntouchedWhenAboveCurrent() public {
    uint256 newMaxRate = uint256(_initialRate) * 10;

    vm.recordLogs();
    vm.prank(governor);
    saving.setMaxRate(newMaxRate);
    Vm.Log[] memory logs = vm.getRecordedLogs();

    assertEq(saving.maxRate(), newMaxRate);
    assertEq(saving.rate(), _initialRate, "rate must be untouched");

    bytes32 rateUpdatedSig = keccak256("RateUpdated(uint256)");
    for (uint256 i; i < logs.length; ++i) {
      assertTrue(logs[i].topics[0] != rateUpdatedSig, "RateUpdated must not be emitted when cap is raised");
    }
  }

  function test_setMaxRate_accruesYieldAtOldRateBeforeClamping() public {
    deal({ token: address(tokenP), to: alice, give: Constants.BASE_18 });
    vm.startPrank(alice);
    IERC20(address(tokenP)).approve(address(saving), Constants.BASE_18);
    saving.deposit(Constants.BASE_18, alice);
    vm.stopPrank();

    uint256 assetsBefore = saving.totalAssets();
    uint40 t0 = uint40(block.timestamp);

    skip(1 days);

    uint256 expectedAccrued = saving.computeUpdatedAssets(assetsBefore, 1 days);
    assertGt(expectedAccrued, assetsBefore, "old rate must produce accrual over the elapsed window");

    uint256 newMaxRate = uint256(_initialRate) / 2;
    vm.prank(governor);
    saving.setMaxRate(newMaxRate);

    assertEq(saving.totalAssets(), expectedAccrued, "yield must be settled at old rate before clamp");
    assertEq(saving.lastUpdate(), block.timestamp, "lastUpdate must advance to current block");
    assertGt(saving.lastUpdate(), t0);
    assertEq(saving.rate(), uint208(newMaxRate));
  }
}

contract SavingsTogglePauseAccrueTest is Fixture {
  uint208 internal constant _rate = 10 ** (27 - 8);
  uint256 internal constant _maxRate = 10 ** (27 - 6);

  function setUp() public override {
    super.setUp();
    saving = SavingsNameable(deploySavings(governor, address(tokenP), address(accessManager)));
    vm.label(address(saving), "saving");

    vm.startPrank(governor);
    accessManager.setTargetFunctionRole(address(saving), getGovernorSavingsSelectorAccess(), GOVERNOR_ROLE);
    accessManager.setTargetFunctionRole(address(saving), getGuardianSavingsSelectorAccess(), GUARDIAN_ROLE);
    saving.setMaxRate(_maxRate);
    vm.stopPrank();

    vm.prank(guardian);
    saving.setRate(_rate);

    deal({ token: address(tokenP), to: alice, give: Constants.BASE_18 });
    vm.startPrank(alice);
    IERC20(address(tokenP)).approve(address(saving), Constants.BASE_18);
    saving.deposit(Constants.BASE_18, alice);
    vm.stopPrank();
  }

  function test_pause_accruesYieldOnPause() public {
    uint256 assetsBefore = saving.totalAssets();
    skip(1 days);
    uint256 expectedAtPause = saving.computeUpdatedAssets(assetsBefore, 1 days);
    assertGt(expectedAtPause, assetsBefore, "yield must have accrued during the pre-pause window");

    vm.prank(guardian);
    saving.pause();

    assertEq(saving.paused(), 1);
    assertEq(saving.lastUpdate(), block.timestamp, "lastUpdate must snapshot the pause timestamp");
    assertEq(saving.totalAssets(), expectedAtPause, "yield must be settled at pause time");
  }

  function test_totalAssets_doesNotProjectYieldWhilePaused() public {
    vm.prank(guardian);
    saving.pause();
    uint256 storedAtPause = saving.storedAssets();

    skip(30 days);

    assertEq(saving.totalAssets(), storedAtPause, "totalAssets must not project yield while paused");
    assertEq(saving.totalAssets(), saving.storedAssets());
  }

  function test_setRate_whilePaused_doesNotMintPausedYield() public {
    vm.prank(guardian);
    saving.pause();
    uint256 storedAtPause = saving.storedAssets();
    uint256 balAtPause = IERC20(address(tokenP)).balanceOf(address(saving));

    skip(30 days);

    vm.prank(guardian);
    saving.setRate(_rate);

    assertEq(saving.storedAssets(), storedAtPause, "no paused yield minted into storedAssets");
    assertEq(IERC20(address(tokenP)).balanceOf(address(saving)), balAtPause, "no tokenP minted while paused");
    assertEq(saving.lastUpdate(), block.timestamp, "lastUpdate advanced to now");
  }

  function test_setMaxRate_whilePaused_doesNotMintPausedYield() public {
    vm.prank(guardian);
    saving.pause();
    uint256 storedAtPause = saving.storedAssets();
    uint256 balAtPause = IERC20(address(tokenP)).balanceOf(address(saving));

    skip(30 days);

    vm.prank(governor);
    saving.setMaxRate(_maxRate);

    assertEq(saving.storedAssets(), storedAtPause, "no paused yield minted into storedAssets");
    assertEq(IERC20(address(tokenP)).balanceOf(address(saving)), balAtPause, "no tokenP minted while paused");
  }

  function test_unpause_dropsPausedWindowYield() public {
    vm.prank(guardian);
    saving.pause();
    uint40 lastUpdateAtPause = saving.lastUpdate();
    uint256 assetsAtPause = saving.totalAssets();

    skip(7 days);

    vm.prank(guardian);
    saving.unpause();

    assertEq(saving.paused(), 0);
    assertEq(saving.lastUpdate(), block.timestamp, "lastUpdate must advance to the unpause timestamp");
    assertGt(saving.lastUpdate(), lastUpdateAtPause);
    assertEq(saving.totalAssets(), assetsAtPause, "pausing halts emission: the paused window is not minted");
  }

  function test_unpause_firstInteractionAfterUnpauseEarnsNoStaleYield() public {
    vm.prank(guardian);
    saving.pause();

    skip(30 days);

    vm.prank(guardian);
    saving.unpause();

    uint256 assetsAtUnpause = saving.totalAssets();

    skip(1 days);

    uint256 expectedAfterOneDay = saving.computeUpdatedAssets(assetsAtUnpause, 1 days);

    vm.prank(guardian);
    saving.setRate(_rate);

    assertApproxEqAbs(
      saving.totalAssets(),
      expectedAfterOneDay,
      1,
      "post-unpause accrual must be priced from the unpause timestamp, not the pause start"
    );
  }
}
