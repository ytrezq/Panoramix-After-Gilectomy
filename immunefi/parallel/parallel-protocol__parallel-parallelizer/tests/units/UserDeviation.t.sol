// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console } from "@forge-std/console.sol";

import { MockChainlinkOracle } from "../mock/MockChainlinkOracle.sol";
import { Fixture } from "../Fixture.sol";
import { OracleReadType } from "contracts/parallelizer/Storage.sol";
import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol" as Errors;

/// @notice Bailsec Core Issue_22. `userDeviation` snaps a spot inside its band up to the target for
/// both mint and burn, so a collateral bought at a discount mints at face value. The band is also
/// what keeps ordinary oracle noise from tripping the burn firewall, which is why zeroing it is not
/// the answer.
contract Test_UserDeviation is Fixture {
  function _oracleConfig(
    address collateral,
    uint128 userDeviation,
    uint128 burnRatioDeviation
  )
    internal
    view
    returns (bytes memory)
  {
    (OracleReadType oracleType, OracleReadType targetType, bytes memory oracleData, bytes memory targetData,) =
      parallelizer.getOracle(collateral);
    return abi.encode(oracleType, targetType, oracleData, targetData, abi.encode(userDeviation, burnRatioDeviation));
  }

  function _setDeviations(address collateral, uint128 userDeviation, uint128 burnRatioDeviation) internal {
    bytes memory config = _oracleConfig(collateral, userDeviation, burnRatioDeviation);
    hoax(governor);
    parallelizer.setOracle(collateral, config);
  }

  /// @dev eurA quoted `bps` basis points under its target
  function _discountEurA(uint256 bps) internal {
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256((BASE_8 * (10_000 - bps)) / 10_000));
  }

  function _mintValue(uint256 amountIn) internal returns (uint256 tokenPOut) {
    deal(address(eurA), alice, amountIn);
    vm.startPrank(alice);
    IERC20(address(eurA)).approve(address(parallelizer), amountIn);
    uint256 before = tokenP.balanceOf(alice);
    parallelizer.swapExactInput(amountIn, 0, address(eurA), address(tokenP), alice, block.timestamp + 1 days);
    tokenPOut = tokenP.balanceOf(alice) - before;
    vm.stopPrank();
  }

  /// @dev `setOracle` refuses a snap band wider than the firewall band, which is exactly the
  /// pairing two mainnet collaterals carry today. They predate the check, and `DiamondInitializer`
  /// routes through the same `setOracle`, so the current config would not deploy.
  function test_SetOracle_RejectsTheLiveMainnetPairing() public {
    bytes memory config = _oracleConfig(address(eurA), 5e14, 0);
    hoax(governor);
    vm.expectRevert(Errors.InvalidParams.selector);
    parallelizer.setOracle(address(eurA), config);
  }

  /// @dev Moving the same tolerance to the burn side prices the mint at the true spot, so the
  /// discount is no longer captured
  function test_ToleranceOnTheBurnSide_PricesTheMintCorrectly() public {
    _setDeviations(address(eurA), 0, 5e14);

    uint256 snap = vm.snapshotState();
    uint256 atPeg = _mintValue(10_000 * BASE_6);
    vm.revertToState(snap);

    _discountEurA(4);
    uint256 discounted = _mintValue(10_000 * BASE_6);

    console.log("userDeviation 0, burnRatioDeviation 5bps");
    console.log("  tokenP minted at peg            ", atPeg);
    console.log("  tokenP minted 4 bps under peg   ", discounted);
    console.log("  shortfall carried by the minter ", atPeg - discounted);
    assertLt(discounted, atPeg, "the discount must reach the minter, not the protocol");
    // the shortfall tracks the 4 bps discount rather than being absorbed by the reserve
    assertApproxEqRel(atPeg - discounted, (atPeg * 4) / 10_000, 0.02e18, "shortfall should track the spot");
  }

  /// @dev And the burn firewall still tolerates the same noise, so nothing is lost by the move
  function test_ToleranceOnTheBurnSide_StillAbsorbsOracleNoise() public {
    _setDeviations(address(eurA), 0, 5e14);
    _discountEurA(4);

    (,, uint256 ratio,,) = parallelizer.getOracleValues(address(eurA));
    console.log("burn ratio with a 4 bps depeg, tolerance on the burn side", ratio);
    assertEq(ratio, BASE_18, "a 4 bps wobble must not haircut every burn");

    // past the band the firewall engages as intended
    _discountEurA(20);
    (,, ratio,,) = parallelizer.getOracleValues(address(eurA));
    console.log("burn ratio with a 20 bps depeg", ratio);
    assertLt(ratio, BASE_18, "a real depeg must still haircut burns");
  }
}
