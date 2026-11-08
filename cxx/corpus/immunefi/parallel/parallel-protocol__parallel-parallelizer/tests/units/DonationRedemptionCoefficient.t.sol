// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { console } from "@forge-std/console.sol";

import { MockChainlinkOracle } from "../mock/MockChainlinkOracle.sol";
import { Fixture } from "../Fixture.sol";
import "contracts/utils/Constants.sol";

/// @notice Bailsec Core Issue_10. A donation lifts the reported collateral ratio without lifting
/// tracked issuance, so it can buy a better redemption coefficient. Measured against the redemption
/// curve live on all five chains, with a second holder present so the transfer of value is visible.
contract Test_DonationRedemptionCoefficient is Fixture {
  /// @dev The curve deployed on mainnet, sonic, base, avalanche and hyperevm
  function _setLiveRedemptionCurve() internal {
    uint64[] memory x = new uint64[](4);
    x[0] = 750_000_000;
    x[1] = 850_000_000;
    x[2] = 950_000_000;
    x[3] = 970_000_000;
    int64[] memory y = new int64[](4);
    y[0] = 995_000_000;
    y[1] = 950_000_000;
    y[2] = 950_000_000;
    y[3] = 995_000_000;
    hoax(guardian);
    parallelizer.setRedemptionCurveParams(x, y);
  }

  function setUp() public override {
    super.setUp();
    _setLiveRedemptionCurve();
    // alice attacks, bob is the holder she would be extracting from. Splitting the position by
    // transfer rather than a second mint keeps the exposure fee curve out of the measurement
    _mintExactInput(alice, address(eurA), 100_000 * BASE_6, 0);
    _setRatioTo(950_000_000);
  }

  /// @dev Calibrates the eurA oracle so the reported ratio lands on `target`, rather than assuming
  /// what the fixture's mints issued
  function _setRatioTo(uint64 target) internal {
    uint256 issued = parallelizer.getTotalIssued();
    uint256 balance = IERC20(address(eurA)).balanceOf(address(parallelizer));
    uint8 dec = IERC20Metadata(address(eurA)).decimals();
    // answer is 8 decimals, balance carries `dec`, issued and target are 18 and 9 decimals
    uint256 answer = (uint256(target) * issued * (10 ** dec) * BASE_8) / (BASE_9 * balance * BASE_18);
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(answer));
  }

  function _valueOf(address token, uint256 amount) internal view returns (uint256) {
    (,,,, uint256 oracleValue) = parallelizer.getOracleValues(token);
    return (oracleValue * amount) / (10 ** IERC20Metadata(token).decimals());
  }

  /// @dev Oracle value of the collateral `who` holds outside the Parallelizer
  function _walletValue(address who) internal view returns (uint256 total) {
    address[] memory list = parallelizer.getCollateralList();
    for (uint256 i; i < list.length; ++i) {
      total += _valueOf(list[i], IERC20(list[i]).balanceOf(who));
    }
  }

  /// @dev Oracle value `who` would get by redeeming everything they still hold
  function _claimValue(address who) internal view returns (uint256 total) {
    uint256 bal = tokenP.balanceOf(who);
    if (bal == 0) return 0;
    // the quote refuses to price the entire remaining issuance
    if (bal >= parallelizer.getTotalIssued()) bal = parallelizer.getTotalIssued() - 1;
    (address[] memory tokens, uint256[] memory amounts) = parallelizer.quoteRedemptionCurve(bal);
    for (uint256 i; i < tokens.length; ++i) {
      total += _valueOf(tokens[i], amounts[i]);
    }
  }

  function _redeem(address who, uint256 amount) internal {
    (address[] memory tokens,) = parallelizer.quoteRedemptionCurve(amount);
    uint256[] memory minOuts = new uint256[](tokens.length);
    vm.prank(who);
    parallelizer.redeem(amount, who, block.timestamp + 1 days, minOuts, keccak256(abi.encodePacked(tokens)));
  }

  /// @dev Alice's total position after the run, and what bob is left holding
  function _run(uint256 redeemAmount, uint256 donation) internal returns (uint256 aliceNet, uint256 bobClaim) {
    uint256 cost;
    if (donation > 0) {
      deal(address(eurB), alice, donation);
      cost = _valueOf(address(eurB), donation);
      vm.prank(alice);
      IERC20(address(eurB)).transfer(address(parallelizer), donation);
    }
    _redeem(alice, redeemAmount);
    aliceNet = _walletValue(alice) + _claimValue(alice) - cost;
    bobClaim = _claimValue(bob);
  }

  /// @dev A curve with no upward segment: the reported ratio no longer prices the redemption, so a
  /// donation has nothing to buy. `level` sets how much of a run deterrent is kept.
  function _setFlatRedemptionCurve(int64 level) internal {
    uint64[] memory x = new uint64[](2);
    x[0] = 0;
    x[1] = 1_000_000_000;
    int64[] memory y = new int64[](2);
    y[0] = level;
    y[1] = level;
    hoax(guardian);
    parallelizer.setRedemptionCurveParams(x, y);
  }

  function _attackerNet(uint256 donation) internal returns (int256) {
    _splitSupply(50);
    uint256 amount = tokenP.balanceOf(alice);
    uint256 inner = vm.snapshotState();
    (uint256 baseAlice,) = _run(amount, 0);
    vm.revertToState(inner);
    (uint256 a,) = _run(amount, donation);
    vm.revertToState(inner);
    return int256(a) - int256(baseAlice);
  }

  /// @dev Flattening removes the profit at any level, so the level is free to serve the run
  /// deterrent rather than the donation defence
  function test_FlatCurve_RemovesTheDonationProfit() public {
    uint256 donation = 2000e12;

    int256 live = _attackerNet(donation);
    console.log("live curve  (99.5 / 95 / 95 / 99.5)");
    _log(live);

    _setFlatRedemptionCurve(995_000_000);
    int256 flatHigh = _attackerNet(donation);
    console.log("flat at 99.5%, no deterrent kept");
    _log(flatHigh);

    _setFlatRedemptionCurve(950_000_000);
    int256 flatLow = _attackerNet(donation);
    console.log("flat at 95%, 5 point deterrent kept");
    _log(flatLow);

    assertGt(live, int256(0), "the deployed curve is exploitable at this share");
    assertLt(flatHigh, int256(0), "flattening high must remove the profit");
    assertLt(flatLow, int256(0), "flattening low must remove the profit");
  }

  /// @dev `y[last]` also prices every redemption above a 100% ratio, so flattening the curve at a
  /// lower level would raise the fee paid in normal conditions
  function test_FlatLevel_AlsoPricesHealthyRedemptions() public {
    _setRatioTo(1_100_000_000);
    _splitSupply(50);
    uint256 amount = tokenP.balanceOf(alice);

    uint256 snap = vm.snapshotState();
    _setFlatRedemptionCurve(995_000_000);
    _redeem(alice, amount);
    uint256 at995 = _walletValue(alice);
    vm.revertToState(snap);

    _setFlatRedemptionCurve(950_000_000);
    _redeem(alice, amount);
    uint256 at950 = _walletValue(alice);
    vm.revertToState(snap);

    console.log("healthy redemption at a 110% ratio");
    console.log("  proceeds with y[last] = 99.5%", at995);
    console.log("  proceeds with y[last] = 95%  ", at950);
    console.log("  cost of flattening low       ", at995 - at950);
    assertGt(at995, at950, "a lower flat level taxes healthy redemptions");
  }

  /// @dev Same 4.5 point deterrent, ramping back to `y[last]` from `rampStart` up to a 100% ratio.
  /// The attacker pays in ratio points and is paid in payout points, so the slope of that ramp is
  /// what decides profitability, not whether a deterrent exists.
  function _setRampedCurve(uint64 rampStart) internal {
    uint64[] memory x = new uint64[](3);
    x[0] = 0;
    x[1] = rampStart;
    x[2] = 1_000_000_000;
    int64[] memory y = new int64[](3);
    y[0] = 950_000_000;
    y[1] = 950_000_000;
    y[2] = 995_000_000;
    hoax(guardian);
    parallelizer.setRedemptionCurveParams(x, y);
  }

  function _attackerNetAtShare(uint256 sharePct, uint256 donation) internal returns (int256) {
    _splitSupply(100 - sharePct);
    uint256 amount = tokenP.balanceOf(alice);
    uint256 inner = vm.snapshotState();
    (uint256 baseAlice,) = _run(amount, 0);
    vm.revertToState(inner);
    (uint256 a,) = _run(amount, donation);
    vm.revertToState(inner);
    return int256(a) - int256(baseAlice);
  }

  /// @dev A gentle enough ramp keeps the deterrent and still starves the attack, including against
  /// a holder large enough to recover most of their own donation
  function test_RampSlope_DecidesProfitability() public {
    uint256 donation = 2000e12;
    uint64[4] memory rampStarts = [uint64(950_000_000), 900_000_000, 800_000_000, 600_000_000];
    uint256[2] memory shares = [uint256(50), 90];

    console.log("4.5 payout points ramping up to a 100% ratio, over a widening band");
    for (uint256 i; i < rampStarts.length; ++i) {
      uint256 width = 1_000_000_000 - rampStarts[i];
      console.log("  ramp starts at (1e9)", rampStarts[i]);
      console.log("    slope x1000", (uint256(45_000_000) * 1000) / width);
      for (uint256 j; j < shares.length; ++j) {
        uint256 snap = vm.snapshotState();
        _setRampedCurve(rampStarts[i]);
        int256 net = _attackerNetAtShare(shares[j], donation);
        vm.revertToState(snap);
        console.log("      attacker share pct", shares[j]);
        _log(net);

        // The attacker pays `d` in ratio points and is repaid `slope * d` in payout points on their
        // own redemption, while recovering the share `f` of the donation they still have a claim
        // on. So a ramp starves the attack when slope < (1 - f) / (f * H/S). At half the supply
        // that threshold is about 1.05, at ninety percent about 0.12.
        uint256 threshold = shares[j] == 50 ? 1053 : 117;
        if ((uint256(45_000_000) * 1000) / width < threshold) {
          assertLt(net, int256(0), "a ramp below the threshold must not pay");
        } else {
          assertGt(net, int256(0), "a ramp above the threshold still pays");
        }
      }
    }
  }

  /// @dev At or above 100% the curve sits at its cap, so the donation buys no coefficient lift and the
  /// attacker is left paying the spread. The cap is what closes this, not the slope of the ramp
  function test_Overcollateralized_RemovesTheDonationProfit() public {
    uint256 donation = 2000e12;

    uint256 snap = vm.snapshotState();
    _setRampedCurve(600_000_000);
    int256 under = _attackerNetAtShare(90, donation);
    vm.revertToState(snap);

    snap = vm.snapshotState();
    _setRampedCurve(600_000_000);
    _setRatioTo(1_050_000_000);
    int256 over = _attackerNetAtShare(90, donation);
    vm.revertToState(snap);

    console.log("undercollateralised:");
    _log(under);
    console.log("overcollateralised:");
    _log(over);
    assertLt(over, int256(0), "an overcollateralised system must not pay the donation attack");
  }

  /// @dev `processSurplus` drives the ratio down to `surplusBufferRatio`, so the margin over the
  /// profitable region is under a point rather than whatever a spot reading suggests
  function test_SurplusBufferSteadyState_LeavesAThinMargin() public {
    uint256 donation = 2000e12;

    uint256 snap = vm.snapshotState();
    _setRampedCurve(600_000_000);
    _setRatioTo(1_005_000_000);
    int256 atBuffer = _attackerNetAtShare(90, donation);
    vm.revertToState(snap);

    snap = vm.snapshotState();
    _setRampedCurve(600_000_000);
    _setRatioTo(995_000_000);
    int256 belowBuffer = _attackerNetAtShare(90, donation);
    vm.revertToState(snap);

    console.log("at the 100.5% surplus buffer:");
    _log(atBuffer);
    console.log("one point below it:");
    _log(belowBuffer);

    assertLt(atBuffer, int256(0), "the attack must not pay at the surplus buffer");
  }

  /// @dev The ratio sawtooths between the buffer and whatever yield adds before the next run, so the
  /// trough is the block the run lands in
  function test_MonthlySawtooth_TroughIsTheExposedPoint() public {
    uint256 donation = 2000e12;

    uint256 snap = vm.snapshotState();
    _setRampedCurve(600_000_000);
    _setRatioTo(1_005_000_000);
    int256 trough = _attackerNetAtShare(90, donation);
    vm.revertToState(snap);

    snap = vm.snapshotState();
    _setRampedCurve(600_000_000);
    _setRatioTo(1_011_000_000);
    int256 lateCycle = _attackerNetAtShare(90, donation);
    vm.revertToState(snap);

    console.log("trough, just after processSurplus:");
    _log(trough);
    console.log("late in the cycle, after a month of yield:");
    _log(lateCycle);

    assertLt(trough, int256(0), "the trough must still not pay the attack");
    assertLt(lateCycle, int256(0), "later in the cycle must not pay either");
  }

  function _log(int256 net) internal pure {
    if (net > 0) console.log("    attacker GAINS", uint256(net));
    else console.log("    attacker LOSES", uint256(-net));
  }

  /// @dev Moves `pct` of the supply to bob, leaving alice with the rest
  function _splitSupply(uint256 pctToBob) internal {
    uint256 send = (tokenP.balanceOf(alice) * pctToBob) / 100;
    vm.prank(alice);
    IERC20(address(tokenP)).transfer(bob, send);
  }

  /// @dev Donation sized to walk the ratio from 95% up onto the 97% shoulder of the curve
  function test_Measure_ProfitabilityByAttackerShare() public {
    uint256[5] memory attackerPct = [uint256(25), 30, 35, 40, 50];
    uint256 donation = 2000e12;

    console.log("attacker share -> net result, donating 2000 of correctly priced collateral");
    for (uint256 i; i < attackerPct.length; ++i) {
      uint256 snap = vm.snapshotState();
      _splitSupply(100 - attackerPct[i]);
      uint256 amount = tokenP.balanceOf(alice);

      uint256 inner = vm.snapshotState();
      (uint256 baseAlice,) = _run(amount, 0);
      vm.revertToState(inner);
      (uint256 a, uint256 b) = _run(amount, donation);
      uint256 baseBob;
      {
        vm.revertToState(inner);
        (, baseBob) = _run(amount, 0);
      }
      vm.revertToState(snap);

      console.log("  attacker holds pct", attackerPct[i]);
      if (a > baseAlice) console.log("    attacker GAINS", a - baseAlice);
      else console.log("    attacker LOSES", baseAlice - a);
      if (b < baseBob) console.log("    others   LOSE ", baseBob - b);
      else console.log("    others   gain ", b - baseBob);

      // Break-even sits between 30% and 35% of the supply on the deployed curve. These bounds are
      // the documented exposure: widening the curve's upward segment would move them, and this
      // test is meant to fail so the trade-off gets re-measured.
      if (attackerPct[i] <= 30) assertLt(a, baseAlice, "attack should not pay at this share");
      if (attackerPct[i] >= 35) assertGt(a, baseAlice, "attack should still pay at this share");
    }
  }

  function test_Measure_DonationTransfersValueFromOtherHolders() public {
    _splitSupply(50);
    uint256 startingAlice = tokenP.balanceOf(alice);
    uint256[3] memory donations = [uint256(500e12), 2000e12, 5000e12];

    uint256 snap = vm.snapshotState();
    (uint256 baseAlice, uint256 baseBob) = _run(startingAlice, 0);
    vm.revertToState(snap);
    require(tokenP.balanceOf(alice) == startingAlice, "snapshot did not restore");

    (uint64 crStart,) = parallelizer.getCollateralRatio();
    console.log("starting collateral ratio (1e9)", crStart);
    console.log("baseline, no donation");
    console.log("  alice net position", baseAlice);
    console.log("  bob   claim value", baseBob);

    for (uint256 i; i < donations.length; ++i) {
      snap = vm.snapshotState();
      deal(address(eurB), alice, donations[i]);
      vm.prank(alice);
      IERC20(address(eurB)).transfer(address(parallelizer), donations[i]);
      (uint64 crAfter,) = parallelizer.getCollateralRatio();
      vm.revertToState(snap);

      snap = vm.snapshotState();
      (uint256 a, uint256 b) = _run(startingAlice, donations[i]);
      uint256 eurBBack = IERC20(address(eurB)).balanceOf(alice);
      vm.revertToState(snap);
      require(tokenP.balanceOf(alice) == startingAlice, "snapshot did not restore");

      console.log("donation oracle value", _valueOfStatic(donations[i]));
      console.log("  ratio moves to (1e9)", crAfter);
      console.log("  eurB returned to alice (oracle value)", _valueOfStatic(eurBBack));
      if (a > baseAlice) console.log("  alice GAINS", a - baseAlice);
      else console.log("  alice LOSES", baseAlice - a);
      if (b < baseBob) console.log("  bob   LOSES", baseBob - b);
      else console.log("  bob   gains", b - baseBob);
    }
  }

  function _valueOfStatic(uint256 amount) internal view returns (uint256) {
    return _valueOf(address(eurB), amount);
  }
}
