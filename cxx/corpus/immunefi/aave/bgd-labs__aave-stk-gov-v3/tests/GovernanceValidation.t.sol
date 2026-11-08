// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {AaveGovernanceV2, IAaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {GovHelpers} from 'aave-helpers/GovHelpers.sol';
import {StakedTokenV3} from '../src/contracts/StakedTokenV3.sol';
import {IInitializableAdminUpgradeabilityProxy} from '../src/interfaces/IInitializableAdminUpgradeabilityProxy.sol';
import {BaseTest} from './BaseTest.sol';
import {IGovernancePowerDelegationToken} from 'aave-token-v3/interfaces/IGovernancePowerDelegationToken.sol';

contract GovernanceValidation is BaseTest {
  function setUp() public {
    _setUp(true);
  }

  // FUZZ
  /**
   * @dev User votes on proposal after 10% being slashed
   */
  function test_voteAfterSlash(uint256 amount) public {
    uint256 slashingPercent = 10;
    vm.assume(amount < type(uint104).max);
    vm.assume(amount > 1 ether);
    _stake(amount);

    address receiver = address(42);
    uint256 amountToSlash = (STAKE_CONTRACT.totalSupply() * slashingPercent) /
      100;
    vm.startPrank(STAKE_CONTRACT.getAdmin(SLASHING_ADMIN));
    STAKE_CONTRACT.slash(receiver, amountToSlash);
    vm.stopPrank();

    uint256 power = STAKE_CONTRACT.getPowerCurrent(
      address(this),
      IGovernancePowerDelegationToken.GovernancePowerType.VOTING
    );

    assertLe(power, (amount * (100 - slashingPercent)) / 100);
    assertApproxEqRel(
      power,
      (amount * (100 - slashingPercent)) / 100,
      0.001e18
    ); // allow for 0.1% derivation
  }

  function test_delegateAfterSlash(uint256 amount) public {
    uint256 slashingPercent = 10;
    vm.assume(amount < type(uint104).max);
    vm.assume(amount > 1 ether);
    _stake(amount);
    address delegatee = address(100);
    STAKE_CONTRACT.delegate(delegatee);

    address receiver = address(42);
    uint256 amountToSlash = (STAKE_CONTRACT.totalSupply() * slashingPercent) /
      100;
    vm.startPrank(STAKE_CONTRACT.getAdmin(SLASHING_ADMIN));
    STAKE_CONTRACT.slash(receiver, amountToSlash);
    vm.stopPrank();

    uint256 power = STAKE_CONTRACT.getPowerCurrent(
      delegatee,
      IGovernancePowerDelegationToken.GovernancePowerType.VOTING
    );

    assertLe(power, (amount * (100 - slashingPercent)) / 100);
    assertApproxEqRel(
      power,
      (amount * (100 - slashingPercent)) / 100,
      0.001e18
    ); // allow for 0.1% derivation
  }

  function test_delegatePowerIncreaseAfteStake() public {
    deal(address(STAKE_CONTRACT.STAKED_TOKEN()), address(this), 100e18);
    STAKE_CONTRACT.STAKED_TOKEN().approve(
      address(STAKE_CONTRACT),
      type(uint256).max
    );
    uint256 amount = 1e18;
    STAKE_CONTRACT.stake(address(this), amount);
    address delegatee = address(100);
    STAKE_CONTRACT.delegate(delegatee);
    uint256 powerBefore = STAKE_CONTRACT.getPowerCurrent(
      delegatee,
      IGovernancePowerDelegationToken.GovernancePowerType.VOTING
    );
    STAKE_CONTRACT.stake(address(this), amount);
    uint256 powerAfter = STAKE_CONTRACT.getPowerCurrent(
      delegatee,
      IGovernancePowerDelegationToken.GovernancePowerType.VOTING
    );
    assertEq(powerAfter, powerBefore + amount);
  }

  function test_delegatePowerDecreaseAfteWithdraw() public {
    deal(address(STAKE_CONTRACT.STAKED_TOKEN()), address(this), 100e18);
    STAKE_CONTRACT.STAKED_TOKEN().approve(
      address(STAKE_CONTRACT),
      type(uint256).max
    );
    STAKE_CONTRACT.stake(address(this), 10e18);
    address delegatee = address(100);
    STAKE_CONTRACT.delegate(delegatee);
    uint256 powerBefore = STAKE_CONTRACT.getPowerCurrent(
      delegatee,
      IGovernancePowerDelegationToken.GovernancePowerType.VOTING
    );
    STAKE_CONTRACT.cooldown();
    vm.warp(block.timestamp + STAKE_CONTRACT.getCooldownSeconds() + 1);
    STAKE_CONTRACT.redeem(address(this), 1e18);
    uint256 powerAfter = STAKE_CONTRACT.getPowerCurrent(
      delegatee,
      IGovernancePowerDelegationToken.GovernancePowerType.VOTING
    );
    assertEq(powerAfter, powerBefore - 1e18);
  }

  function test_delegatePowerDecreaseAfteTransferOut() public {
    deal(address(STAKE_CONTRACT.STAKED_TOKEN()), address(this), 100e18);
    STAKE_CONTRACT.STAKED_TOKEN().approve(
      address(STAKE_CONTRACT),
      type(uint256).max
    );
    STAKE_CONTRACT.stake(address(this), 10e18);
    address delegatee = address(100);
    STAKE_CONTRACT.delegate(delegatee);
    uint256 powerBefore = STAKE_CONTRACT.getPowerCurrent(
      delegatee,
      IGovernancePowerDelegationToken.GovernancePowerType.VOTING
    );

    // transfer to delegatee
    STAKE_CONTRACT.transfer(delegatee, 1e18);
    uint256 powerAfter = STAKE_CONTRACT.getPowerCurrent(
      delegatee,
      IGovernancePowerDelegationToken.GovernancePowerType.VOTING
    );
    assertEq(powerAfter, powerBefore);

    // transfer somewhere else
    uint256 lostPower = 1e18;
    STAKE_CONTRACT.transfer(address(42), lostPower);
    uint256 powerAfterTransferOut = STAKE_CONTRACT.getPowerCurrent(
      delegatee,
      IGovernancePowerDelegationToken.GovernancePowerType.VOTING
    );
    assertEq(powerAfterTransferOut, powerBefore - lostPower);
  }
}
