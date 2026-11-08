// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Errors } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IAccessManaged } from "contracts/utils/AccessManagedUpgradeable.sol";
import { EIP3009 } from "contracts/savings/EIP3009.sol";
import { Savings } from "contracts/savings/Savings.sol";

import { UD60x18, ud, pow, powu, unwrap } from "@prb/math/UD60x18.sol";

import "contracts/utils/Errors.sol" as Errors;

import "../Fixture.sol";
import "../utils/FunctionUtils.sol";

contract SavingsTest is Fixture, FunctionUtils {
  using SafeERC20 for IERC20;

  event MaxRateUpdated(uint256 newMaxRate);
  event RateUpdated(uint256 newRate);
  event ToggledTrusted(address indexed trustedAddress, uint256 trustedStatus);

  uint256 internal constant _initDeposit = 1e18;
  uint256 internal constant _minAmount = 10 ** 10;
  uint256 internal constant _maxAmount = 10 ** (18 + 15);
  // Annually this represent a 2250% APY
  uint256 internal constant _maxRate = 10 ** (27 - 7);
  // Annually this represent a 0.0003% APY
  uint256 internal constant _minRate = 10 ** (27 - 13);
  uint256 internal constant _maxElapseTime = 20 days;
  uint256 internal constant _nbrActor = 10;
  address[] public actors;

  function setUp() public override {
    super.setUp();

    for (uint256 i; i < _nbrActor; ++i) {
      address actor = address(uint160(uint256(keccak256(abi.encodePacked("actor", i)))));
      actors.push(actor);
    }

    saving = SavingsNameable(deploySavings(governor, address(tokenP), address(accessManager)));
    vm.label(address(saving), "saving");

    // grant access to all functions for governor role
    vm.startPrank(governor);
    accessManager.setTargetFunctionRole(address(saving), getGovernorSavingsSelectorAccess(), GOVERNOR_ROLE);
    accessManager.setTargetFunctionRole(address(saving), getGuardianSavingsSelectorAccess(), GUARDIAN_ROLE);
    saving.setMaxRate(type(uint256).max);
    vm.stopPrank();
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         PAUSE                                                      
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function test_Pause() public {
    _deposit(BASE_18, alice, alice, 0);

    vm.startPrank(guardian);
    saving.pause();

    vm.startPrank(alice);
    vm.expectRevert(Errors.Paused.selector);
    saving.deposit(BASE_18, alice);

    vm.expectRevert(Errors.Paused.selector);
    saving.mint(BASE_18, alice);

    vm.expectRevert(Errors.Paused.selector);
    saving.redeem(BASE_18, alice, alice);

    vm.expectRevert(Errors.Paused.selector);
    saving.withdraw(BASE_18, alice, alice);

    vm.stopPrank();
  }

  function test_ToggleTrusted() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
    saving.toggleTrusted(alice);

    vm.startPrank(guardian);
    vm.expectEmit(address(saving));
    emit ToggledTrusted(alice, 1);
    saving.toggleTrusted(alice);
    assertEq(saving.isTrustedUpdater(alice), 1);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  DONATION ATTACK
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Locks in the invariant the storedAssets fix protects: an honest depositor's
  ///         redemption is strictly equal to the preview computed before the donation,
  ///         regardless of how large the donation is.
  function testFuzz_DonationAttackInflationLockedDown(uint256 donation) public {
    donation = bound(donation, 1, 1_000_000_000e18);

    (uint256 honestShares,) = _deposit(BASE_18, alice, alice, 0);
    uint256 baselinePreview = saving.previewRedeem(honestShares);

    deal(address(tokenP), address(this), donation);
    tokenP.transfer(address(saving), donation);

    assertEq(saving.previewRedeem(honestShares), baselinePreview, "preview unchanged");

    vm.prank(alice);
    uint256 received = saving.redeem(honestShares, alice, alice);
    assertEq(received, baselinePreview, "received == baseline (no donation captured)");
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         APRS                                                       
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_SetRate(uint256 rate) public {
    // we need to decrease to a smaller maxRate = 37% otherwise the approximation is way off
    // even currently we can not achieve a 0.1% precision
    rate = bound(rate, _minRate, _maxRate / 10);
    vm.startPrank(guardian);
    vm.expectEmit(address(saving));
    emit RateUpdated(rate);
    saving.setRate(uint208(rate));

    assertEq(saving.rate(), rate);
    uint256 estimatedAPR =
      (BASE_18 * unwrap(powu(ud(BASE_18 + rate / BASE_9), 365 days))) / unwrap(powu(ud(BASE_18), 365 days)) - BASE_18;

    _assertApproxEqRelDecimalWithTolerance(
      saving.estimatedAPY(), estimatedAPR, estimatedAPR, _MAX_PERCENTAGE_DEVIATION * 5000, 18
    );
  }

  function testFuzz_SetRateWithTrusted(uint256 rate) public {
    // we need to decrease to a smaller maxRate = 37% otherwise the approximation is way off
    // even currently we can not achieve a 0.1% precision
    rate = bound(rate, _minRate, _maxRate / 10);
    vm.startPrank(guardian);
    vm.expectEmit(address(saving));
    emit ToggledTrusted(alice, 1);
    saving.toggleTrusted(alice);
    vm.stopPrank();

    vm.startPrank(alice);
    vm.expectEmit(address(saving));
    emit RateUpdated(rate);
    saving.setRate(uint208(rate));

    assertEq(saving.rate(), rate);
    uint256 estimatedAPR =
      (BASE_18 * unwrap(powu(ud(BASE_18 + rate / BASE_9), 365 days))) / unwrap(powu(ud(BASE_18), 365 days)) - BASE_18;

    _assertApproxEqRelDecimalWithTolerance(
      saving.estimatedAPY(), estimatedAPR, estimatedAPR, _MAX_PERCENTAGE_DEVIATION * 5000, 18
    );

    vm.startPrank(guardian);
    vm.expectEmit(address(saving));
    emit ToggledTrusted(alice, 0);
    saving.toggleTrusted(alice);
    vm.stopPrank();

    vm.startPrank(alice);
    vm.expectRevert(Errors.NotTrusted.selector);
    saving.setRate(uint208(rate));
    vm.stopPrank();
  }

  function testFuzz_SetMaxRate(uint256 rate) public {
    rate = bound(rate, _minRate, _maxRate);
    vm.startPrank(governor);
    vm.expectEmit(address(saving));
    emit MaxRateUpdated(rate);
    saving.setMaxRate(rate);

    assertEq(saving.maxRate(), rate);
  }

  function test_RevertWhen_SetMaxRateNotGovernor(uint256 rate) public {
    rate = bound(rate, _minRate, _maxRate);
    vm.startPrank(governor);
    saving.setMaxRate(uint208(rate));
    assertEq(saving.maxRate(), rate);

    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
    saving.setMaxRate(uint208(rate + 1));

    vm.startPrank(guardian);
    vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, guardian));
    saving.setMaxRate(uint208(rate - 1));
  }

  function test_RevertWhen_SetRateNotTrusted(uint256 rate) public {
    rate = bound(rate, _minRate, _maxRate / 10 - 1);
    vm.startPrank(guardian);
    saving.setRate(uint208(rate));

    assertEq(saving.rate(), rate);

    vm.startPrank(alice);
    vm.expectRevert(Errors.NotTrusted.selector);
    saving.setRate(uint208(rate + 1));

    vm.startPrank(guardian);
    saving.setRate(uint208(rate - 1));
    assertEq(saving.rate(), rate - 1);

    vm.startPrank(alice);
    vm.expectRevert(Errors.NotTrusted.selector);
    saving.setRate(uint208(0));

    vm.startPrank(guardian);
    saving.setRate(uint208(0));
    assertEq(saving.rate(), 0);
  }

  function test_RevertWhen_SetRateInvalidRate(uint256 rate, uint256 maxRate) public {
    rate = bound(rate, _minRate, _maxRate / 10 - 1);
    maxRate = bound(maxRate, _minRate, _maxRate);

    vm.startPrank(governor);
    saving.setMaxRate(maxRate);
    assertEq(saving.maxRate(), maxRate);

    if (maxRate >= rate) {
      vm.startPrank(guardian);
      saving.setRate(uint208(rate));
      assertEq(saving.rate(), rate);
    } else {
      vm.startPrank(guardian);
      vm.expectRevert(Errors.InvalidRate.selector);
      saving.setRate(uint208(rate));
    }

    vm.startPrank(guardian);
    vm.expectRevert(Errors.InvalidRate.selector);
    saving.setRate(uint208(maxRate + 1));
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        DEPOSIT                                                     
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_DepositSimple(uint256 amount, uint256 indexReceiver) public {
    amount = bound(amount, 0, _maxAmount);

    address receiver;
    uint256 shares;

    {
      uint256 supposedShares = saving.previewDeposit(amount);
      (shares, receiver) = _deposit(amount, alice, address(0), indexReceiver);
      assertEq(shares, supposedShares);
    }

    assertEq(shares, amount);
    assertEq(saving.totalAssets(), _initDeposit + amount);
    assertEq(saving.totalSupply(), _initDeposit + shares);
    assertEq(tokenP.balanceOf(address(saving)), _initDeposit + amount);
    assertEq(saving.balanceOf(address(alice)), 0);
    assertEq(saving.balanceOf(receiver), shares);
  }

  function testFuzz_DepositSingleRate(
    uint256[2] memory amounts,
    uint256 rate,
    uint256 indexReceiver,
    uint256[2] memory elapseTimestamps
  )
    public
  {
    for (uint256 i; i < amounts.length; i++) {
      amounts[i] = bound(amounts[i], 0, _maxAmount);
    }
    rate = bound(rate, _minRate, _maxRate);
    // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
    elapseTimestamps[0] = bound(elapseTimestamps[0], 0, _maxElapseTime);
    elapseTimestamps[1] = bound(elapseTimestamps[1], 0, _maxElapseTime);

    _deposit(amounts[0], sweeper, sweeper, 0);

    vm.startPrank(guardian);
    saving.setRate(uint208(rate));

    // first time elapse
    skip(elapseTimestamps[0]);
    uint256 compoundAssets = (
      (amounts[0] + _initDeposit) * unwrap(powu(ud(BASE_18 + rate / BASE_9), elapseTimestamps[0]))
    ) / unwrap(powu(ud(BASE_18), elapseTimestamps[0]));
    {
      uint256 shares = saving.balanceOf(sweeper);
      _assertApproxEqRelDecimalWithTolerance(
        saving.totalAssets(), compoundAssets, compoundAssets, _MAX_PERCENTAGE_DEVIATION * 100, 18
      );
      assertEq(shares, amounts[0]);
      assertApproxEqAbs(
        saving.convertToAssets(shares), (saving.totalAssets() * shares) / ((shares + _initDeposit)), 1 wei
      );
      assertApproxEqAbs(
        saving.previewRedeem(shares), (saving.totalAssets() * shares) / ((shares + _initDeposit)), 1 wei
      );
    }

    address receiver;
    uint256 returnShares;
    {
      uint256 prevShares = saving.totalSupply();
      uint256 balanceAsset = saving.totalAssets();
      uint256 supposedShares = saving.previewDeposit(amounts[1]);
      (returnShares, receiver) = _deposit(amounts[1], alice, address(0), indexReceiver);
      uint256 expectedShares = (amounts[1] * prevShares) / balanceAsset;
      assertEq(returnShares, expectedShares);
      assertEq(supposedShares, returnShares);
    }

    // second time elapse
    skip(elapseTimestamps[1]);

    {
      uint256 newCompoundAssets = (
        (compoundAssets + amounts[1]) * unwrap(powu(ud(BASE_18 + rate / BASE_9), elapseTimestamps[1]))
      ) / unwrap(powu(ud(BASE_18), elapseTimestamps[1]));
      uint256 shares = saving.balanceOf(receiver);
      assertEq(shares, returnShares);

      _assertApproxEqRelDecimalWithTolerance(
        saving.totalAssets(), newCompoundAssets, newCompoundAssets, _MAX_PERCENTAGE_DEVIATION * 100, 18
      );
      _assertApproxEqRelDecimalWithTolerance(
        saving.computeUpdatedAssets(compoundAssets + amounts[1], elapseTimestamps[1]),
        newCompoundAssets,
        newCompoundAssets,
        _MAX_PERCENTAGE_DEVIATION * 100,
        18
      );
      assertApproxEqAbs(saving.convertToAssets(shares), (saving.totalAssets() * shares) / saving.totalSupply(), 1 wei);
      assertApproxEqAbs(saving.previewRedeem(shares), (saving.totalAssets() * shares) / saving.totalSupply(), 1 wei);
    }
  }

  function testFuzz_DepositMultiRate(
    uint256[3] memory amounts,
    uint256[2] memory rates,
    uint256 indexReceiver,
    uint256[3] memory elapseTimestamps
  )
    public
  {
    for (uint256 i; i < amounts.length; i++) {
      amounts[i] = bound(amounts[i], 0, _maxAmount);
    }
    // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
    for (uint256 i; i < elapseTimestamps.length; i++) {
      elapseTimestamps[i] = bound(elapseTimestamps[i], 0, _maxElapseTime);
    }
    for (uint256 i; i < rates.length; i++) {
      rates[i] = bound(rates[i], _minRate, _maxRate);
    }

    _deposit(amounts[0], sweeper, sweeper, 0);

    vm.startPrank(guardian);
    saving.setRate(uint208(rates[0]));

    // first time elapse
    skip(elapseTimestamps[0]);
    _deposit(amounts[1], sweeper, sweeper, 0);

    vm.startPrank(guardian);
    saving.setRate(uint208(rates[1]));

    uint256 prevTotalAssets = saving.totalAssets();

    // second time elapse
    skip(elapseTimestamps[1]);

    address receiver;
    uint256 returnShares;
    {
      uint256 prevShares = saving.totalSupply();
      uint256 newCompoundAssets = (
        prevTotalAssets * unwrap(powu(ud(BASE_18 + rates[1] / BASE_9), elapseTimestamps[1]))
      ) / unwrap(powu(ud(BASE_18), elapseTimestamps[1]));
      uint256 balanceAsset = saving.totalAssets();
      _assertApproxEqRelDecimalWithTolerance(
        balanceAsset, newCompoundAssets, newCompoundAssets, _MAX_PERCENTAGE_DEVIATION * 100, 18
      );
      uint256 supposedShares = saving.previewDeposit(amounts[2]);
      (returnShares, receiver) = _deposit(amounts[2], alice, address(0), indexReceiver);
      uint256 shares = saving.balanceOf(receiver);
      uint256 expectedShares = (amounts[2] * prevShares) / balanceAsset;
      assertEq(shares, returnShares);
      assertEq(returnShares, expectedShares);
      assertEq(supposedShares, returnShares);
    }
    // third time elapse
    skip(elapseTimestamps[2]);

    {
      uint256 newCompoundAssets = (
        prevTotalAssets * unwrap(powu(ud(BASE_18 + rates[1] / BASE_9), elapseTimestamps[1]))
      ) / unwrap(powu(ud(BASE_18), elapseTimestamps[1]));
      newCompoundAssets = (
        (newCompoundAssets + amounts[2]) * unwrap(powu(ud(BASE_18 + rates[1] / BASE_9), elapseTimestamps[2]))
      ) / unwrap(powu(ud(BASE_18), elapseTimestamps[2]));

      _assertApproxEqRelDecimalWithTolerance(
        saving.totalAssets(), newCompoundAssets, newCompoundAssets, _MAX_PERCENTAGE_DEVIATION * 100, 18
      );
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         MINT                                                       
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_MintSimple(uint256 shares, uint256 indexReceiver) public {
    shares = bound(shares, 0, _maxAmount);

    uint256 amount;
    address receiver;
    (amount, shares, receiver) = _mint(shares, shares, alice, address(0), indexReceiver);

    assertEq(amount, shares);
    assertEq(saving.totalAssets(), _initDeposit + amount);
    assertEq(saving.totalSupply(), _initDeposit + shares);
    assertEq(tokenP.balanceOf(address(saving)), _initDeposit + amount);
    assertEq(saving.balanceOf(address(alice)), 0);
    assertEq(saving.balanceOf(receiver), shares);
  }

  function testFuzz_MintNonNullRate(uint256[4] memory shares, uint256[2] memory elapseTimestamps) public {
    // shares[2] rate
    // shares[3] indexReceiver
    for (uint256 i; i < 2; i++) {
      shares[i] = bound(shares[i], 0, _maxAmount);
    }
    shares[2] = bound(shares[2], _minRate, _maxRate);
    // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
    elapseTimestamps[0] = bound(elapseTimestamps[0], 0, _maxElapseTime);
    elapseTimestamps[1] = bound(elapseTimestamps[1], 0, _maxElapseTime);

    _deposit(shares[0], sweeper, sweeper, 0);

    vm.startPrank(guardian);
    saving.setRate(uint208(shares[2]));

    // first time elapse
    skip(elapseTimestamps[0]);
    uint256 compoundAssets = (
      (shares[0] + _initDeposit) * unwrap(powu(ud(BASE_18 + shares[2] / BASE_9), elapseTimestamps[0]))
    ) / unwrap(powu(ud(BASE_18), elapseTimestamps[0]));
    address receiver;
    uint256 returnAmount;
    {
      uint256 prevShares = saving.totalSupply();
      uint256 balanceAsset = saving.totalAssets();
      uint256 supposedAmount = saving.previewMint(shares[1]);
      (returnAmount,, receiver) = _mint(shares[1], supposedAmount, alice, address(0), shares[3]);
      uint256 expectedAmount = (shares[1] * balanceAsset) / prevShares;
      assertEq(shares[1], saving.balanceOf(receiver));
      assertApproxEqAbs(returnAmount, expectedAmount, 1 wei);
      assertEq(returnAmount, supposedAmount);
    }

    // second time elapse
    skip(elapseTimestamps[1]);

    {
      uint256 increasedRate = (BASE_18 * unwrap(powu(ud(BASE_18 + shares[2] / BASE_9), elapseTimestamps[1])))
        / unwrap(powu(ud(BASE_18), elapseTimestamps[1]));
      uint256 newCompoundAssets = (((compoundAssets + returnAmount) * increasedRate) / BASE_18);

      _assertApproxEqRelDecimalWithTolerance(
        saving.totalAssets(), newCompoundAssets, newCompoundAssets, _MAX_PERCENTAGE_DEVIATION * 100, 18
      );
      _assertApproxEqRelDecimalWithTolerance(
        saving.computeUpdatedAssets(compoundAssets + returnAmount, elapseTimestamps[1]),
        newCompoundAssets,
        newCompoundAssets,
        _MAX_PERCENTAGE_DEVIATION * 100,
        18
      );
      if (_minAmount < (shares[1] * BASE_18) / increasedRate) {
        _assertApproxEqRelDecimalWithTolerance(
          saving.convertToShares(returnAmount),
          (shares[1] * BASE_18) / increasedRate,
          (shares[1] * BASE_18) / increasedRate,
          _MAX_PERCENTAGE_DEVIATION * 100,
          18
        );
        _assertApproxEqRelDecimalWithTolerance(
          saving.previewWithdraw(returnAmount),
          (shares[1] * BASE_18) / increasedRate,
          (shares[1] * BASE_18) / increasedRate,
          _MAX_PERCENTAGE_DEVIATION * 100,
          18
        );
      }
    }
  }

  function testFuzz_MintMultiRate(
    uint256[3] memory shares,
    uint256[2] memory rates,
    uint256 indexReceiver,
    uint256[3] memory elapseTimestamps
  )
    public
  {
    for (uint256 i; i < shares.length; i++) {
      shares[i] = bound(shares[i], 0, _maxAmount);
    }
    // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
    for (uint256 i; i < elapseTimestamps.length; i++) {
      elapseTimestamps[i] = bound(elapseTimestamps[i], 0, _maxElapseTime);
    }
    for (uint256 i; i < rates.length; i++) {
      rates[i] = bound(rates[i], _minRate, _maxRate);
    }

    _deposit(shares[0], sweeper, sweeper, 0);

    vm.startPrank(guardian);
    saving.setRate(uint208(rates[0]));

    // first time elapse
    skip(elapseTimestamps[0]);
    _deposit(shares[1], sweeper, sweeper, 0);

    vm.startPrank(guardian);
    saving.setRate(uint208(rates[1]));

    uint256 prevTotalAssets = saving.totalAssets();

    // second time elapse
    skip(elapseTimestamps[1]);

    address receiver;
    uint256 returnAmount;
    {
      uint256 prevShares = saving.totalSupply();
      uint256 balanceAsset = saving.totalAssets();
      uint256 supposedAmount = saving.previewMint(shares[2]);
      (returnAmount,, receiver) = _mint(shares[2], supposedAmount, alice, address(0), indexReceiver);
      assertEq(tokenP.balanceOf(alice), 0);
      uint256 expectedAmount = (shares[2] * balanceAsset) / prevShares;
      assertEq(shares[2], saving.balanceOf(receiver));
      assertApproxEqAbs(returnAmount, expectedAmount, 1 wei);
      assertEq(returnAmount, supposedAmount);
    }
    // third time elapse
    skip(elapseTimestamps[2]);

    uint256 newCompoundAssets = (prevTotalAssets * unwrap(powu(ud(BASE_18 + rates[1] / BASE_9), elapseTimestamps[1])))
      / unwrap(powu(ud(BASE_18), elapseTimestamps[1]));
    newCompoundAssets = (
      (newCompoundAssets + returnAmount) * unwrap(powu(ud(BASE_18 + rates[1] / BASE_9), elapseTimestamps[2]))
    ) / unwrap(powu(ud(BASE_18), elapseTimestamps[2]));

    uint256 withdrawableAmount = (returnAmount * unwrap(powu(ud(BASE_18 + rates[1] / BASE_9), elapseTimestamps[2])))
      / unwrap(powu(ud(BASE_18), elapseTimestamps[2]));

    if (withdrawableAmount > _minAmount) {
      _assertApproxEqRelDecimalWithTolerance(
        saving.previewRedeem(saving.balanceOf(receiver)),
        withdrawableAmount,
        withdrawableAmount,
        _MAX_PERCENTAGE_DEVIATION * 100,
        18
      );

      _assertApproxEqRelDecimalWithTolerance(
        saving.totalAssets(), newCompoundAssets, newCompoundAssets, _MAX_PERCENTAGE_DEVIATION * 100, 18
      );
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         REDEEM
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_RedeemSuccess(
    uint256[2] memory amounts,
    uint256 propWithdraw,
    uint256 rate,
    uint256 indexReceiver,
    uint256[2] memory elapseTimestamps
  )
    public
  {
    for (uint256 i; i < amounts.length; i++) {
      amounts[i] = bound(amounts[i], 1e15, _maxAmount);
    }
    // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
    for (uint256 i; i < elapseTimestamps.length; i++) {
      elapseTimestamps[i] = bound(elapseTimestamps[i], 0, _maxElapseTime);
    }
    rate = bound(rate, _minRate, _maxRate);
    propWithdraw = bound(propWithdraw, 0, BASE_9);
    address receiver = actors[bound(indexReceiver, 0, _nbrActor - 1)];

    _deposit(amounts[0], sweeper, sweeper, 0);

    vm.startPrank(guardian);
    saving.setRate(uint208(rate));

    // first time elapse
    skip(elapseTimestamps[0]);
    _deposit(amounts[1], alice, alice, 0);

    // second time elapse
    skip(elapseTimestamps[1]);

    uint256 withdrawableAmount = (amounts[1] * unwrap(powu(ud(BASE_18 + rate / BASE_9), elapseTimestamps[1])))
      / unwrap(powu(ud(BASE_18), elapseTimestamps[1]));

    if (withdrawableAmount > _minAmount) {
      _assertApproxEqRelDecimalWithTolerance(
        saving.previewRedeem(saving.balanceOf(alice)),
        withdrawableAmount,
        withdrawableAmount,
        _MAX_PERCENTAGE_DEVIATION * 100,
        18
      );

      {
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenP);
        _sweepBalances(alice, tokens);
        _sweepBalances(receiver, tokens);
      }

      uint256 shares = saving.balanceOf(alice);
      uint256 sharesToRedeem = (shares * propWithdraw) / BASE_9;
      uint256 amount;
      {
        uint256 previewAmount = saving.previewRedeem(sharesToRedeem);
        vm.startPrank(alice);
        amount = saving.redeem(sharesToRedeem, receiver, alice);
        assertEq(previewAmount, amount);
      }
      _assertApproxEqRelDecimalWithTolerance(
        amount, (withdrawableAmount * propWithdraw) / BASE_9, amount, _MAX_PERCENTAGE_DEVIATION * 100, 18
      );
      assertEq(tokenP.balanceOf(receiver), amount);
      assertEq(tokenP.balanceOf(alice), 0);
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       WITHDRAW
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_MaxWithdrawSuccess(uint256[4] memory amounts, uint256[2] memory elapseTimestamps) public {
    // amounts[2] rate
    // amounts[3] indexReceiver
    for (uint256 i; i < 2; i++) {
      amounts[i] = bound(amounts[i], 0, _maxAmount);
    }
    // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
    for (uint256 i; i < elapseTimestamps.length; i++) {
      elapseTimestamps[i] = bound(elapseTimestamps[i], 0, _maxElapseTime);
    }
    amounts[2] = bound(amounts[2], _minRate, _maxRate);
    address receiver = actors[bound(amounts[3], 0, _nbrActor - 1)];

    _deposit(amounts[0], sweeper, sweeper, 0);

    vm.startPrank(guardian);
    saving.setRate(uint208(amounts[2]));

    // first time elapse
    skip(elapseTimestamps[0]);
    _deposit(amounts[1], alice, alice, 0);

    // second time elapse
    skip(elapseTimestamps[1]);

    uint256 shares = saving.balanceOf(alice);
    uint256 withdrawableAmount = saving.maxWithdraw(alice);

    _assertApproxEqRelDecimalWithTolerance(
      saving.previewWithdraw(withdrawableAmount), shares, shares, _MAX_PERCENTAGE_DEVIATION * 100, 18
    );

    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(
        ERC4626Upgradeable.ERC4626ExceededMaxWithdraw.selector, alice, withdrawableAmount + 1, withdrawableAmount
      )
    );
    saving.withdraw(withdrawableAmount + 1, receiver, alice);
    uint256 sharesBurnt = saving.withdraw(withdrawableAmount, receiver, alice);
    vm.stopPrank();

    assertEq(sharesBurnt, shares);
    assertEq(tokenP.balanceOf(receiver), withdrawableAmount);
    assertEq(tokenP.balanceOf(alice), 0);
    assertEq(saving.balanceOf(alice), 0);
  }

  function testFuzz_WithdrawSuccess(
    uint256[2] memory amounts,
    uint256 propWithdraw,
    uint256 rate,
    uint256 indexReceiver,
    uint256[2] memory elapseTimestamps
  )
    public
  {
    for (uint256 i; i < amounts.length; i++) {
      amounts[i] = bound(amounts[i], 0, _maxAmount);
    }
    // shorten the time otherwise the DL diverge too much from the actual formula (1+rate)**seconds
    for (uint256 i; i < elapseTimestamps.length; i++) {
      elapseTimestamps[i] = bound(elapseTimestamps[i], 0, _maxElapseTime);
    }
    rate = bound(rate, _minRate, _maxRate);
    propWithdraw = bound(propWithdraw, 0, BASE_9);
    address receiver = actors[bound(indexReceiver, 0, _nbrActor - 1)];

    _deposit(amounts[0], sweeper, sweeper, 0);

    vm.startPrank(guardian);
    saving.setRate(uint208(rate));

    // first time elapse
    skip(elapseTimestamps[0]);
    _deposit(amounts[1], alice, alice, 0);

    // second time elapse
    skip(elapseTimestamps[1]);

    uint256 withdrawableAmount = (amounts[1] * unwrap(powu(ud(BASE_18 + rate / BASE_9), elapseTimestamps[1])))
      / unwrap(powu(ud(BASE_18), elapseTimestamps[1]));

    if (withdrawableAmount > _minAmount) {
      uint256 shares = saving.balanceOf(alice);

      _assertApproxEqRelDecimalWithTolerance(
        saving.maxWithdraw(alice), withdrawableAmount, withdrawableAmount, _MAX_PERCENTAGE_DEVIATION * 100, 18
      );

      withdrawableAmount = saving.maxWithdraw(alice);

      _assertApproxEqRelDecimalWithTolerance(
        saving.previewWithdraw(withdrawableAmount), shares, shares, _MAX_PERCENTAGE_DEVIATION * 100, 18
      );

      {
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenP);
        _sweepBalances(alice, tokens);
        _sweepBalances(receiver, tokens);
      }

      uint256 amountToRedeem = (withdrawableAmount * propWithdraw) / BASE_9;
      vm.startPrank(alice);
      uint256 sharesBurnt = saving.withdraw(amountToRedeem, receiver, alice);
      vm.stopPrank();

      _assertApproxEqRelDecimalWithTolerance(
        sharesBurnt, (shares * propWithdraw) / BASE_9, sharesBurnt, _MAX_PERCENTAGE_DEVIATION * 100, 18
      );
      assertEq(tokenP.balanceOf(receiver), amountToRedeem);
      assertEq(tokenP.balanceOf(alice), 0);
      assertEq(saving.balanceOf(alice), shares - sharesBurnt);
      if (withdrawableAmount - amountToRedeem > _minAmount) {
        _assertApproxEqRelDecimalWithTolerance(
          saving.convertToAssets(saving.balanceOf(alice)),
          withdrawableAmount - amountToRedeem,
          withdrawableAmount - amountToRedeem,
          _MAX_PERCENTAGE_DEVIATION * 100,
          18
        );
      }
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS                                                      
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _deposit(
    uint256 amount,
    address owner,
    address receiver,
    uint256 indexReceiver
  )
    internal
    returns (uint256, address)
  {
    if (receiver == address(0)) receiver = actors[bound(indexReceiver, 0, _nbrActor - 1)];

    deal(address(tokenP), owner, amount);
    vm.startPrank(owner);
    tokenP.approve(address(saving), amount);
    uint256 shares = saving.deposit(amount, receiver);
    vm.stopPrank();

    return (shares, receiver);
  }

  function _mint(
    uint256 shares,
    uint256 estimatedAmount,
    address owner,
    address receiver,
    uint256 indexReceiver
  )
    internal
    returns (uint256, uint256, address)
  {
    if (receiver == address(0)) receiver = actors[bound(indexReceiver, 0, _nbrActor - 1)];

    deal(address(tokenP), owner, estimatedAmount);
    vm.startPrank(owner);
    tokenP.approve(address(saving), estimatedAmount);
    uint256 amount = saving.mint(shares, receiver);
    vm.stopPrank();
    return (amount, shares, receiver);
  }

  /// @notice Signs both the outer Savings-domain intent and the inner underlying-token EIP-3009
  /// authorization required by `Savings.depositWithAuthorization`.
  function _signDepositAuth(
    uint256 privateKey,
    address owner,
    address receiver,
    uint256 assets,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce
  )
    internal
    view
    returns (bytes memory savingsSig, bytes memory tokenSig)
  {
    savingsSig = _signSavingsDepositAuth(privateKey, owner, receiver, assets, validAfter, validBefore, nonce);
    tokenSig = _signTokenReceiveAuth(privateKey, owner, assets, validAfter, validBefore, nonce);
  }

  /// @dev Split to keep each frame under the stack-too-deep threshold without via-ir.
  function _signSavingsDepositAuth(
    uint256 privateKey,
    address owner,
    address receiver,
    uint256 assets,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce
  )
    private
    view
    returns (bytes memory sig)
  {
    bytes32 digest = MessageHashUtils.toTypedDataHash(
      saving.DOMAIN_SEPARATOR(),
      keccak256(
        abi.encode(
          saving.DEPOSIT_WITH_AUTHORIZATION_TYPEHASH(),
          address(saving),
          owner,
          receiver,
          assets,
          validAfter,
          validBefore,
          nonce
        )
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    sig = abi.encodePacked(r, s, v);
  }

  function _signTokenReceiveAuth(
    uint256 privateKey,
    address owner,
    uint256 assets,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce
  )
    private
    view
    returns (bytes memory sig)
  {
    bytes32 digest = MessageHashUtils.toTypedDataHash(
      MockTokenPermit(address(tokenP)).DOMAIN_SEPARATOR(),
      keccak256(
        abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, owner, address(saving), assets, validAfter, validBefore, nonce)
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    sig = abi.encodePacked(r, s, v);
  }

  /// @notice Signs a `Savings.redeemWithAuthorization` intent against the Savings EIP-712 domain.
  function _signRedeemAuth(
    uint256 privateKey,
    address owner,
    address receiver,
    uint256 shares,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce
  )
    internal
    view
    returns (uint8 v, bytes32 r, bytes32 s)
  {
    bytes32 digest = MessageHashUtils.toTypedDataHash(
      saving.DOMAIN_SEPARATOR(),
      keccak256(
        abi.encode(
          saving.REDEEM_WITH_AUTHORIZATION_TYPEHASH(),
          address(saving),
          owner,
          receiver,
          shares,
          validAfter,
          validBefore,
          nonce
        )
      )
    );
    (v, r, s) = vm.sign(privateKey, digest);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    EIP-3009
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function test_DepositWithAuthorization() public {
    uint256 amount = 100 * BASE_18;
    deal(address(tokenP), alice, amount);

    bytes32 nonce = bytes32("dep1");
    uint256 deadline = block.timestamp + 1 hours;
    (bytes memory savingsSig, bytes memory tokenSig) = _signDepositAuth(1, alice, alice, amount, 0, deadline, nonce);

    // bob relays alice's signed authorization
    vm.prank(bob);
    uint256 shares =
      saving.depositWithAuthorization(amount, alice, alice, 0, deadline, nonce, savingsSig, tokenSig);

    assertGt(shares, 0);
    assertGt(saving.balanceOf(alice), 0);
    assertEq(IERC20(address(tokenP)).balanceOf(alice), 0);
  }

  function test_DepositWithAuthorization_RevertWhen_Paused() public {
    uint256 amount = 100 * BASE_18;
    deal(address(tokenP), alice, amount);

    bytes32 nonce = bytes32("dep2");
    uint256 deadline = block.timestamp + 1 hours;
    (bytes memory savingsSig, bytes memory tokenSig) = _signDepositAuth(1, alice, alice, amount, 0, deadline, nonce);

    vm.prank(guardian);
    saving.pause();

    vm.prank(bob);
    vm.expectRevert(Errors.Paused.selector);
    saving.depositWithAuthorization(amount, alice, alice, 0, deadline, nonce, savingsSig, tokenSig);
  }

  /// @notice Alice signs a deposit to herself. A relayer tries to front-run by swapping `receiver`
  /// to an attacker-controlled address. The outer Savings signature binds `receiver`, so the
  /// signature recovery yields a different address and the call reverts.
  function test_DepositWithAuthorization_RevertWhen_ReceiverFrontRun() public {
    uint256 amount = 100 * BASE_18;
    deal(address(tokenP), alice, amount);

    bytes32 nonce = bytes32("dep_frontrun");
    uint256 deadline = block.timestamp + 1 hours;
    // Alice signs with receiver = alice
    (bytes memory savingsSig, bytes memory tokenSig) = _signDepositAuth(1, alice, alice, amount, 0, deadline, nonce);

    // Relayer submits with receiver = bob
    vm.prank(bob);
    vm.expectRevert(EIP3009.InvalidSignature.selector);
    saving.depositWithAuthorization(amount, bob, alice, 0, deadline, nonce, savingsSig, tokenSig);
  }

  function test_RedeemWithAuthorization_Savings() public {
    // First deposit
    _deposit(100 * BASE_18, alice, alice, 0);
    uint256 shares = saving.balanceOf(alice);
    uint256 redeemShares = shares / 2;

    bytes32 nonce = bytes32("redeem_sav1");
    uint256 deadline = block.timestamp + 1 hours;
    (uint8 v, bytes32 r, bytes32 s) = _signRedeemAuth(1, alice, alice, redeemShares, 0, deadline, nonce);

    vm.prank(bob);
    uint256 assets = saving.redeemWithAuthorization(redeemShares, alice, alice, 0, deadline, nonce, v, r, s);

    assertGt(assets, 0);
    assertEq(saving.balanceOf(alice), shares - redeemShares);
  }

  /// @notice Alice signs a redeem to herself. A relayer tries to front-run by swapping `receiver`
  /// to bob. The signature binds `receiver`, so the outer call reverts.
  function test_RedeemWithAuthorization_Savings_RevertWhen_ReceiverFrontRun() public {
    _deposit(100 * BASE_18, alice, alice, 0);
    uint256 shares = saving.balanceOf(alice);
    uint256 redeemShares = shares / 2;

    bytes32 nonce = bytes32("redeem_frontrun");
    uint256 deadline = block.timestamp + 1 hours;
    // Alice signs with receiver = alice
    (uint8 v, bytes32 r, bytes32 s) = _signRedeemAuth(1, alice, alice, redeemShares, 0, deadline, nonce);

    // Relayer submits with receiver = bob
    vm.prank(bob);
    vm.expectRevert(EIP3009.InvalidSignature.selector);
    saving.redeemWithAuthorization(redeemShares, bob, alice, 0, deadline, nonce, v, r, s);
  }

  function test_RedeemWithAuthorization_RevertWhen_ExceedsMaxRedeem() public {
    _deposit(100 * BASE_18, alice, alice, 0);
    uint256 shares = saving.balanceOf(alice);
    uint256 tooMany = shares + 1;

    bytes32 nonce = bytes32("redeem_max");
    uint256 deadline = block.timestamp + 1 hours;
    (uint8 v, bytes32 r, bytes32 s) = _signRedeemAuth(1, alice, alice, tooMany, 0, deadline, nonce);

    vm.prank(bob);
    vm.expectRevert(
      abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxRedeem.selector, alice, tooMany, shares)
    );
    saving.redeemWithAuthorization(tooMany, alice, alice, 0, deadline, nonce, v, r, s);
  }

  function test_TransferWithAuthorization_Savings() public {
    _deposit(100 * BASE_18, alice, alice, 0);
    uint256 shares = saving.balanceOf(alice);
    uint256 transferAmount = shares / 2;

    bytes32 domainSeparator = saving.DOMAIN_SEPARATOR();
    bytes32 structHash = keccak256(
      abi.encode(
        TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
        alice,
        bob,
        transferAmount,
        0,
        block.timestamp + 1 hours,
        bytes32("xfer1")
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      1, MessageHashUtils.toTypedDataHash(domainSeparator, structHash)
    );

    vm.prank(dylan);
    saving.transferWithAuthorization(
      alice, bob, transferAmount, 0, block.timestamp + 1 hours, bytes32("xfer1"), v, r, s
    );

    assertEq(saving.balanceOf(alice), shares - transferAmount);
    assertEq(saving.balanceOf(bob), transferAmount);
  }

  function test_ReceiveWithAuthorization_Savings() public {
    _deposit(100 * BASE_18, alice, alice, 0);
    uint256 shares = saving.balanceOf(alice);
    uint256 transferAmount = shares / 2;

    bytes32 domainSeparator = saving.DOMAIN_SEPARATOR();
    bytes32 structHash = keccak256(
      abi.encode(
        RECEIVE_WITH_AUTHORIZATION_TYPEHASH, alice, bob, transferAmount,
        0, block.timestamp + 1 hours, bytes32("recv1")
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      1, MessageHashUtils.toTypedDataHash(domainSeparator, structHash)
    );

    // bob calls receiveWithAuthorization (to == msg.sender)
    vm.prank(bob);
    saving.receiveWithAuthorization(
      alice, bob, transferAmount, 0, block.timestamp + 1 hours, bytes32("recv1"), v, r, s
    );

    assertEq(saving.balanceOf(alice), shares - transferAmount);
    assertEq(saving.balanceOf(bob), transferAmount);
  }

  function test_CancelAuthorization_Savings() public {
    _deposit(100 * BASE_18, alice, alice, 0);
    bytes32 nonce = bytes32("cancel1");

    bytes32 domainSeparator = saving.DOMAIN_SEPARATOR();
    bytes32 cancelTypehash = 0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;
    bytes32 structHash = keccak256(abi.encode(cancelTypehash, alice, nonce));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, MessageHashUtils.toTypedDataHash(domainSeparator, structHash));

    saving.cancelAuthorization(alice, nonce, v, r, s);
    assertTrue(saving.authorizationState(alice, nonce));
  }

  function _sweepBalances(address owner, address[] memory tokens) internal {
    vm.startPrank(owner);
    for (uint256 i; i < tokens.length; ++i) {
      IERC20(tokens[i]).transfer(sweeper, IERC20(tokens[i]).balanceOf(owner));
    }
    vm.stopPrank();
  }
}
