// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./Base.s.sol";

import { ISettersGuardian } from "contracts/interfaces/ISetters.sol";

/// @notice Replaces the redemption curve with a ramp gentle enough that a donation cannot pay for
/// the coefficient it buys. Bailsec Core Issue_10.
///
/// The previous curve returned to 99.5% over two ratio points, a slope of 2.25. An attacker pays in
/// ratio points and is repaid in payout points on their own redemption, while recovering the share
/// `f` they still hold a claim on, so the attack pays whenever the slope exceeds
/// (1 - f) / (f * H/S): about 1.05 against half the supply, about 0.12 against ninety percent.
///
/// The same 4.5 point deterrent now spans a 60% to 100% ratio band, a slope of 0.112, which stays
/// under the threshold even for a holder of ninety percent of the supply. Ramping monotonically also
/// drops the old shape's oddity of paying its best rate at the deepest undercollateralization.
///
/// Run once per chain, against that chain's Parallelizer.
contract SetRedemptionCurve is BaseScript {
  address internal constant PARALLELIZER = 0x6efeDDF9269c3683Ba516cb0e2124FE335F262a2;

  function run() public broadcast {
    uint64[] memory xFee = new uint64[](3);
    xFee[0] = 0;
    xFee[1] = 600_000_000; // 60% collateral ratio
    xFee[2] = 1_000_000_000; // 100% collateral ratio

    int64[] memory yFee = new int64[](3);
    yFee[0] = 950_000_000; // 95% payout, the deterrent floor
    yFee[1] = 950_000_000;
    yFee[2] = 995_000_000; // 99.5%, also the fee every healthy redemption pays

    ISettersGuardian(PARALLELIZER).setRedemptionCurveParams(xFee, yFee);
  }
}
