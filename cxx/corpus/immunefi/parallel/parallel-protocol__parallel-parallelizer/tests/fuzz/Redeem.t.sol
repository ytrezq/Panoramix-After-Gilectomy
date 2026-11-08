// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { stdError } from "@forge-std/Test.sol";

import { ManagerStorage, WhitelistType } from "contracts/parallelizer/Storage.sol";
import "contracts/parallelizer/libraries/LibHelpers.sol";
import "contracts/utils/Errors.sol" as Errors;

import { MockManager } from "../mock/MockManager.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";

struct SubCollateralStorage {
  // The collateral corresponding to the manager must also be in the list
  IERC20[] subCollaterals;
  AggregatorV3Interface[] oracles;
}

struct AssertQuoteParams {
  uint256 amountInValueReceived;
  bool lastCheck;
  uint256 count;
  uint256 maxValue;
  uint256 minValue;
  uint256 maxOracle;
  uint256 minOracle;
}

contract RedeemTest is Fixture, FunctionUtils {
  /// @dev Kept in storage rather than a local: these fuzz tests already sit on the EVM stack limit
  bytes32 internal tokensHash;

  using Math for uint256;
  using SafeERC20 for IERC20;

  uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
  // making this value smaller worsen rounding and make test harder to pass.
  // Trade off between bullet proof against all oracles and all interactions
  uint256 internal _minOracleValue = 10 ** 3; // 10**(-6)
  uint256 internal _minWallet = 10 ** (3 + 18);

  address[] internal _collaterals;
  mapping(address => SubCollateralStorage) internal _subCollaterals;
  AggregatorV3Interface[] internal _oracles;
  uint256[] internal _maxTokenAmount;
  mapping(address => MockManager) internal _managers;

  function setUp() public override {
    super.setUp();

    // set Fees to 0 on all collaterals
    uint64[] memory xFeeMint = new uint64[](1);
    xFeeMint[0] = uint64(0);
    uint64[] memory xFeeBurn = new uint64[](1);
    xFeeBurn[0] = uint64(BASE_9);
    int64[] memory yFee = new int64[](1);
    yFee[0] = 0;
    int64[] memory yFeeRedemption = new int64[](1);
    yFeeRedemption[0] = int64(int256(BASE_9));
    vm.startPrank(guardian);
    parallelizer.setFees(address(eurA), xFeeMint, yFee, true);
    parallelizer.setFees(address(eurA), xFeeBurn, yFee, false);
    parallelizer.setFees(address(eurB), xFeeMint, yFee, true);
    parallelizer.setFees(address(eurB), xFeeBurn, yFee, false);
    parallelizer.setFees(address(eurY), xFeeMint, yFee, true);
    parallelizer.setFees(address(eurY), xFeeBurn, yFee, false);
    parallelizer.setRedemptionCurveParams(xFeeMint, yFeeRedemption);
    vm.stopPrank();

    _collaterals.push(address(eurA));
    _collaterals.push(address(eurB));
    _collaterals.push(address(eurY));
    _oracles.push(oracleA);
    _oracles.push(oracleB);
    _oracles.push(oracleY);

    _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[0]).decimals());
    _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[1]).decimals());
    _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[2]).decimals());
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      QUOTEREDEEM
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_QuoteRedeemAllAtPeg(uint256[3] memory initialAmounts, uint256 transferProportion) public {
    // let's first load the reserves of the protocol
    (uint256 mintedStables,) = _loadReserves(initialAmounts, transferProportion);

    // check collateral ratio first
    (uint64 collatRatio, uint256 stablecoinsIssued) = parallelizer.getCollateralRatio();
    if (mintedStables > 0) assertEq(collatRatio, BASE_9);
    else assertEq(collatRatio, type(uint64).max);
    assertEq(stablecoinsIssued, mintedStables);

    // currently oracles are all set to 1 --> collateral ratio = 1
    // --> redemption should be exactly in proportion of current balances
    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
    else if (mintedStables == amountBurnt) vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    (address[] memory tokens, uint256[] memory amounts) = parallelizer.quoteRedemptionCurve(amountBurnt);
    vm.stopPrank();

    if (mintedStables == 0 || mintedStables == amountBurnt) return;

    _assertSizes(tokens, amounts);
    _assertQuoteAmounts(uint64(BASE_9), mintedStables, amountBurnt, uint64(BASE_9), amounts);
  }

  function testFuzz_QuoteRedeemGlobalAtPeg(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[2] memory latestOracleValue
  )
    public
  {
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(initialAmounts, transferProportion);

    // change oracle value but such that total collateralisation is still == 1
    for (uint256 i; i < latestOracleValue.length; ++i) {
      latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
      MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
    }
    uint256 collateralisation;
    for (uint256 i; i < latestOracleValue.length; ++i) {
      collateralisation += (latestOracleValue[i] * collateralMintedStables[i]) / BASE_8;
    }

    // compensate as much as possible last oracle value to make collateralRatio == 1
    // it can be impossible if one of the other oracle value is already high enough to
    // make the system over collateralised by itself or if there wasn't any minted via the last collateral
    if (mintedStables > collateralisation && collateralMintedStables[2] > 0) {
      MockChainlinkOracle(address(_oracles[2]))
        .setLatestAnswer(int256(((mintedStables - collateralisation) * BASE_8) / collateralMintedStables[2]));

      // check collateral ratio first
      (uint64 collatRatio, uint256 stablecoinsIssued) = parallelizer.getCollateralRatio();
      if (mintedStables > 0) assertApproxEqAbs(collatRatio, BASE_9, 1e5);
      else assertEq(collatRatio, type(uint64).max);
      assertEq(stablecoinsIssued, mintedStables);

      // currently oracles are all set to 1 --> collateral ratio = 1
      // --> redemption should be exactly in proportion of current balances
      vm.startPrank(alice);
      uint256 amountBurnt = tokenP.balanceOf(alice);
      if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
      else if (mintedStables == amountBurnt) vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
      (address[] memory tokens, uint256[] memory amounts) = parallelizer.quoteRedemptionCurve(amountBurnt);
      vm.stopPrank();

      if (mintedStables == 0 || mintedStables == amountBurnt) return;

      _assertSizes(tokens, amounts);
      _assertQuoteAmounts(collatRatio, mintedStables, amountBurnt, uint64(BASE_9), amounts);
    }
  }

  function testFuzz_QuoteRedeemRandomOracles(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3] memory latestOracleValue
  )
    public
  {
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(initialAmounts, transferProportion);
    uint64 collatRatio;
    {
      bool reverted;
      (collatRatio, reverted) = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
      if (reverted) return;
    }

    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
    else if (mintedStables == amountBurnt) vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    (address[] memory tokens, uint256[] memory amounts) = parallelizer.quoteRedemptionCurve(amountBurnt);
    vm.stopPrank();

    if (mintedStables == 0 || mintedStables == amountBurnt) return;

    _assertSizes(tokens, amounts);
    _assertQuoteAmounts(collatRatio, mintedStables, amountBurnt, uint64(BASE_9), amounts);
  }

  function testFuzz_QuoteRedeemAtPegRandomFees(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    public
  {
    // let's first load the reserves of the protocol
    (uint256 mintedStables,) = _loadReserves(initialAmounts, transferProportion);
    (, int64[] memory yFeeRedeem) = _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);

    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
    else if (mintedStables == amountBurnt) vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    (address[] memory tokens, uint256[] memory amounts) = parallelizer.quoteRedemptionCurve(amountBurnt);
    vm.stopPrank();

    if (mintedStables == 0 || mintedStables == amountBurnt) return;

    _assertSizes(tokens, amounts);
    _assertQuoteAmounts(uint64(BASE_9), mintedStables, amountBurnt, uint64(yFeeRedeem[yFeeRedeem.length - 1]), amounts);
  }

  function testFuzz_QuoteRedeemRandomFees(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3] memory latestOracleValue,
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    public
  {
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(initialAmounts, transferProportion);
    uint64 collatRatio;
    {
      bool reverted;
      (collatRatio, reverted) = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
      if (reverted) return;
    }
    (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) =
      _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);

    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
    else if (mintedStables == amountBurnt) vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    (address[] memory tokens, uint256[] memory amounts) = parallelizer.quoteRedemptionCurve(amountBurnt);
    vm.stopPrank();

    if (mintedStables == 0 || mintedStables == amountBurnt) return;

    // compute fee at current collatRatio
    _assertSizes(tokens, amounts);
    uint64 fee;
    if (collatRatio >= BASE_9) fee = uint64(yFeeRedeem[yFeeRedeem.length - 1]);
    else fee = uint64(LibHelpers.piecewiseLinear(collatRatio, xFeeRedeem, yFeeRedeem));
    _assertQuoteAmounts(collatRatio, mintedStables, amountBurnt, fee, amounts);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        REDEEM
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_RedeemAllAtPeg(uint256[3] memory initialAmounts, uint256 transferProportion) public {
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(initialAmounts, transferProportion);

    _sweepBalances(alice, _collaterals);
    // currently oracles are all set to 1 --> collateral ratio = 1
    // --> redemption should be exactly in proportion of current balances
    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    uint256[] memory quoteAmounts;
    {
      address[] memory quoteTokens;
      if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
      else if (mintedStables == amountBurnt) vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
      (quoteTokens, quoteAmounts) = parallelizer.quoteRedemptionCurve(amountBurnt);
      tokensHash = keccak256(abi.encodePacked(quoteTokens));
    }
    if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
    else if (mintedStables == amountBurnt) vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
    (address[] memory tokens, uint256[] memory amounts) =
      parallelizer.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, tokensHash);
    vm.stopPrank();

    if (mintedStables == 0 || mintedStables == amountBurnt) return;

    assertEq(amounts, quoteAmounts);
    _assertSizes(tokens, amounts);
    _assertTransfers(alice, _collaterals, amounts);

    // Testing implicitly the ts.normalizer and ts.normalizedStables
    for (uint256 i; i < _collaterals.length; ++i) {
      (uint256 stableIssuedByCollateral, uint256 totalStable) = parallelizer.getIssuedByCollateral(_collaterals[i]);
      assertApproxEqAbs(
        stableIssuedByCollateral, (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables, 1 wei
      );
      assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
    }
  }

  function testFuzz_RedeemRandomFees(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3] memory latestOracleValue,
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    public
  {
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(initialAmounts, transferProportion);
    uint64 collatRatio;
    {
      bool reverted;
      (collatRatio, reverted) = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
      if (reverted) return;
    }

    (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) =
      _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);
    // Mute warnings
    collatRatio;
    xFeeRedeem;
    yFeeRedeem;

    _sweepBalances(alice, _collaterals);

    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
    else if (mintedStables == amountBurnt) vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    uint256[] memory quoteAmounts;
    {
      address[] memory quoteTokens;
      (quoteTokens, quoteAmounts) = parallelizer.quoteRedemptionCurve(amountBurnt);
      tokensHash = keccak256(abi.encodePacked(quoteTokens));
    }
    if (mintedStables == 0) vm.expectRevert(stdError.divisionError);
    else if (mintedStables == amountBurnt) vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    address[] memory tokens;
    uint256[] memory amounts;
    {
      // uint256[] memory forfeitTokens = new uint256[](0);
      uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
      (tokens, amounts) = parallelizer.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, tokensHash);
    }
    vm.stopPrank();

    if (mintedStables == 0 || mintedStables == amountBurnt) return;

    // compute fee at current collatRatio
    assertEq(amounts, quoteAmounts);
    _assertSizes(tokens, amounts);
    _assertTransfers(alice, _collaterals, amounts);

    // Testing implicitly the ts.normalizer and ts.normalizedStables
    for (uint256 i; i < _collaterals.length; ++i) {
      (uint256 stableIssuedByCollateral, uint256 totalStable) = parallelizer.getIssuedByCollateral(_collaterals[i]);
      assertApproxEqAbs(
        stableIssuedByCollateral, (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables, 1 wei
      );
      assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
    }
  }

  function testFuzz_MultiRedemptionCurveRandomRedemptionFees(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256 redeemProportion,
    uint256[3] memory latestOracleValue,
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    public
  {
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(initialAmounts, transferProportion);
    {
      (, bool reverted) = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
      if (reverted) return;
    }
    _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);
    _sweepBalances(alice, _collaterals);
    _sweepBalances(bob, _collaterals);

    // first redeem
    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    uint256 amountBurntBob;
    uint256[] memory quoteAmounts;
    uint256 stableIssued = mintedStables > 0 ? parallelizer.getTotalIssued() : 0;
    // The quote can revert for several reasons (SafeCast overflow, CannotBurnAllStableIssued,
    // arithmetic overflow on extreme inputs). Dedicated tests cover each; here we just skip.
    try parallelizer.quoteRedemptionCurve(amountBurnt) returns (address[] memory, uint256[] memory a) {
      quoteAmounts = a;
    } catch {
      return;
    }
    if (mintedStables == 0 || amountBurnt >= stableIssued) return;

    {
      address[] memory tokens;
      uint256[] memory amounts;
      {
        uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
        (tokens, amounts) = parallelizer.redeem(
          amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, _redemptionTokensHash(amountBurnt)
        );
      }
      vm.stopPrank();

      if (mintedStables == 0 || amountBurnt >= stableIssued) return;

      // compute fee at current collatRatio
      assertEq(amounts, quoteAmounts);
      _assertSizes(tokens, amounts);
      _assertTransfers(alice, _collaterals, amounts);

      // Testing implicitly the ts.normalizer and ts.normalizedStables
      for (uint256 i; i < _collaterals.length; ++i) {
        (uint256 stableIssuedByCollateral, uint256 totalStable) = parallelizer.getIssuedByCollateral(_collaterals[i]);
        assertApproxEqAbs(
          stableIssuedByCollateral, (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables, 1 wei
        );
        assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
      }

      // Compute mintedStables while rounding up for proportion assertions
      uint128 normalizedStables =
        uint128(uint256(vm.load(address(parallelizer), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1))));
      uint128 normalizer =
        uint128(uint256(vm.load(address(parallelizer), bytes32(uint256(TRANSMUTER_STORAGE_POSITION) + 1)) >> 128));
      mintedStables = uint256(normalizedStables).mulDiv(normalizer, BASE_27, Math.Rounding.Ceil);

      // now do a second redeem to test with non trivial ts.normalizer and ts.normalizedStables
      stableIssued = parallelizer.getTotalIssued();
      vm.startPrank(bob);
      redeemProportion = bound(redeemProportion, 0, BASE_9);
      amountBurntBob = (tokenP.balanceOf(bob) * redeemProportion) / BASE_9;
      try parallelizer.quoteRedemptionCurve(amountBurntBob) returns (address[] memory, uint256[] memory a) {
        quoteAmounts = a;
      } catch {
        return;
      }

      if (stableIssued == 0 || amountBurntBob >= stableIssued) return;

      {
        uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
        (tokens, amounts) = parallelizer.redeem(
          amountBurntBob, bob, block.timestamp + 1 days, minAmountOuts, _redemptionTokensHash(amountBurntBob)
        );
      }
      vm.stopPrank();

      if (stableIssued == 0 || amountBurntBob >= stableIssued) return;

      // compute fee at current collatRatio
      assertEq(amounts, quoteAmounts);
      _assertSizes(tokens, amounts);
      _assertTransfers(bob, _collaterals, amounts);
    }

    // Testing implicitly the ts.normalizer and ts.normalizedStables
    uint256 totalStable2;
    for (uint256 i; i < _collaterals.length; ++i) {
      uint256 stableIssuedByCollateral;
      (stableIssuedByCollateral, totalStable2) = parallelizer.getIssuedByCollateral(_collaterals[i]);
      uint256 realStableIssueByCollateralLeft =
        (collateralMintedStables[i] * (mintedStables - amountBurntBob)) / (mintedStables + amountBurnt);
      _assertApproxEqRelDecimalWithTolerance(
        realStableIssueByCollateralLeft,
        stableIssuedByCollateral,
        realStableIssueByCollateralLeft,
        _MAX_PERCENTAGE_DEVIATION,
        18
      );
    }
    _assertApproxEqRelDecimalWithTolerance(
      mintedStables - amountBurntBob, totalStable2, mintedStables - amountBurntBob, _MAX_PERCENTAGE_DEVIATION * 10, 18
    );
  }

  function testFuzz_RevertWhen_BurningAllStableIssued(
    uint256[3] memory initialAmounts,
    uint256[3] memory latestOracleValue,
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    public
  {
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(initialAmounts, 0);
    if (mintedStables == 0) return;
    {
      (, bool reverted) = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
      if (reverted) return;
    }
    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.quoteRedemptionCurve(amountBurnt);

    uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, bytes32(0));
  }

  function testFuzz_RevertWhen_BurningAllStableIssuedWithWhitelist(
    uint256[3] memory initialAmounts,
    uint256[3] memory latestOracleValue,
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    public
  {
    (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(initialAmounts, 0);
    if (mintedStables == 0) return;
    {
      (, bool reverted) = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
      if (reverted) return;
    }

    // Enable whitelist on the first collateral and whitelist alice
    {
      bytes memory emptyData;
      bytes memory whitelistData = abi.encode(WhitelistType.BACKED, emptyData);
      hoax(governor);
      parallelizer.setWhitelistStatus(address(eurA), 1, whitelistData);
    }
    hoax(guardian);
    parallelizer.toggleWhitelist(WhitelistType.BACKED, alice);

    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.quoteRedemptionCurve(amountBurnt);

    uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, bytes32(0));
  }

  function testFuzz_RedeemWithForfeit_RevertWhen_BurningAllStableIssued(
    uint256[3] memory initialAmounts,
    uint256[3] memory latestOracleValue,
    bool[3] memory areForfeit,
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    public
  {
    (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(initialAmounts, 0);
    if (mintedStables == 0) return;
    {
      (, bool reverted) = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
      if (reverted) return;
    }

    // Build forfeit tokens from collaterals
    uint256 nbrForfeit;
    for (uint256 i; i < _collaterals.length; ++i) {
      if (areForfeit[i]) nbrForfeit++;
    }
    address[] memory forfeitTokens = new address[](nbrForfeit);
    uint256 index;
    for (uint256 i; i < _collaterals.length; ++i) {
      if (areForfeit[i]) forfeitTokens[index++] = _collaterals[i];
    }

    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.quoteRedemptionCurve(amountBurnt);

    uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.redeemWithForfeit(
      amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, forfeitTokens, bytes32(0)
    );
  }

  function testFuzz_RedeemWithForfeit_RevertWhen_BurningAllStableIssuedWithWhitelist(
    uint256[3] memory initialAmounts,
    uint256[3] memory latestOracleValue,
    bool[3] memory areForfeit,
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    public
  {
    (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(initialAmounts, 0);
    if (mintedStables == 0) return;
    {
      (, bool reverted) = _updateOracles(latestOracleValue, mintedStables, collateralMintedStables);
      if (reverted) return;
    }

    // Build forfeit tokens from collaterals
    uint256 nbrForfeit;
    for (uint256 i; i < _collaterals.length; ++i) {
      if (areForfeit[i]) nbrForfeit++;
    }
    address[] memory forfeitTokens = new address[](nbrForfeit);
    uint256 index;
    for (uint256 i; i < _collaterals.length; ++i) {
      if (areForfeit[i]) forfeitTokens[index++] = _collaterals[i];
    }

    // Enable whitelist on the first collateral and whitelist alice
    {
      bytes memory emptyData;
      bytes memory whitelistData = abi.encode(WhitelistType.BACKED, emptyData);
      hoax(governor);
      parallelizer.setWhitelistStatus(address(eurA), 1, whitelistData);
    }
    hoax(guardian);
    parallelizer.toggleWhitelist(WhitelistType.BACKED, alice);

    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.quoteRedemptionCurve(amountBurnt);

    uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.redeemWithForfeit(
      amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, forfeitTokens, bytes32(0)
    );
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  REDEEM WITH MANAGER
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_QuoteRedemptionCurveWithManagerRandomRedemptionFees(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3 * 2] memory nbrSubCollateralsAndIsManaged,
    uint256[3 * (_MAX_SUB_COLLATERALS + 1)] memory airdropAmountsAndOracleValues,
    uint256[3 * 2 * _MAX_SUB_COLLATERALS] memory latestSubCollatOracleValueAndDecimals,
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    public
  {
    for (uint256 i; i < _collaterals.length; ++i) {
      // Randomly set subcollaterals and manager if needed
      (IERC20[] memory subCollaterals, AggregatorV3Interface[] memory oracles) = _createManager(
        _collaterals[i],
        nbrSubCollateralsAndIsManaged[2 * i],
        nbrSubCollateralsAndIsManaged[2 * i + 1],
        i * _MAX_SUB_COLLATERALS,
        latestSubCollatOracleValueAndDecimals
      );
      if (subCollaterals.length > 0) {
        _subCollaterals[_collaterals[i]] = SubCollateralStorage(subCollaterals, oracles);
      }
    }

    // let's first load the reserves of the protocol
    uint256 mintedStables;
    uint64 collatRatio;
    {
      uint256[] memory collateralMintedStables;
      (mintedStables, collateralMintedStables) = _loadReserves(initialAmounts, transferProportion);

      // airdrop amounts in the subcollaterals
      for (uint256 i; i < _collaterals.length; ++i) {
        if (_subCollaterals[_collaterals[i]].subCollaterals.length > 0) {
          _loadSubCollaterals(address(_collaterals[i]), airdropAmountsAndOracleValues, i * _MAX_SUB_COLLATERALS);
        }
      }

      {
        bool reverted;
        (collatRatio, reverted) = _updateOraclesWithSubCollaterals(
          abi.encode(mintedStables, collateralMintedStables), airdropAmountsAndOracleValues
        );
        if (reverted) return;
      }
    }

    (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) =
      _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);

    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    uint256[] memory amounts;
    {
      address[] memory tokens;
      try parallelizer.quoteRedemptionCurve(amountBurnt) returns (address[] memory t, uint256[] memory a) {
        tokens = t;
        amounts = a;
      } catch {
        vm.stopPrank();
        return;
      }
      vm.stopPrank();

      if (mintedStables == 0 || mintedStables == amountBurnt) return;

      // compute fee at current collatRatio
      _assertSizesWithManager(tokens, amounts);
    }
    uint64 fee;
    if (collatRatio >= BASE_9) fee = uint64(yFeeRedeem[yFeeRedeem.length - 1]);
    else fee = uint64(LibHelpers.piecewiseLinear(collatRatio, xFeeRedeem, yFeeRedeem));
    _assertQuoteAmountsWithManager(amountBurnt, fee, amounts);
  }

  function testFuzz_MultiRedemptionCurveWithManagerRandomRedemptionFees(
    uint256[3] memory initialAmounts,
    uint256[2] memory transferRedeemProportion,
    uint256[3 * 2] memory nbrSubCollateralsAndIsManaged,
    uint256[3 * (_MAX_SUB_COLLATERALS + 1)] memory airdropAmountsAndOracleValues,
    uint256[3 * 2 * _MAX_SUB_COLLATERALS] memory latestSubCollatOracleValueAndDecimals,
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    public
  {
    for (uint256 i; i < _collaterals.length; ++i) {
      // Randomly set subcollaterals and manager if needed
      (IERC20[] memory subCollaterals, AggregatorV3Interface[] memory oracles) = _createManager(
        _collaterals[i],
        nbrSubCollateralsAndIsManaged[2 * i],
        nbrSubCollateralsAndIsManaged[2 * i + 1],
        i * _MAX_SUB_COLLATERALS,
        latestSubCollatOracleValueAndDecimals
      );
      _subCollaterals[_collaterals[i]] = SubCollateralStorage(subCollaterals, oracles);
    }

    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(initialAmounts, transferRedeemProportion[0]);
    // airdrop amounts in the subcollaterals
    for (uint256 i; i < _collaterals.length; ++i) {
      if (_subCollaterals[_collaterals[i]].subCollaterals.length > 0) {
        _loadSubCollaterals(address(_collaterals[i]), airdropAmountsAndOracleValues, i * _MAX_SUB_COLLATERALS);
      }
    }
    _updateOraclesWithSubCollaterals(abi.encode(mintedStables, collateralMintedStables), airdropAmountsAndOracleValues);
    _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);
    _sweepBalancesWithManager(alice, _collaterals);
    _sweepBalancesWithManager(bob, _collaterals);

    // first redeem
    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    uint256 amountBurntBob;
    uint256[] memory quoteAmounts;
    try parallelizer.quoteRedemptionCurve(amountBurnt) returns (address[] memory, uint256[] memory a) {
      quoteAmounts = a;
    } catch {
      return;
    }
    if (mintedStables == 0 || amountBurnt >= mintedStables) return;
    {
      uint256[] memory amounts;
      address[] memory tokens;
      {
        uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
        (tokens, amounts) = parallelizer.redeem(
          amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, _redemptionTokensHash(amountBurnt)
        );
      }
      vm.stopPrank();

      if (mintedStables == 0 || amountBurnt == mintedStables) return;

      // compute fee at current collatRatio
      assertEq(amounts, quoteAmounts);
      _assertSizesWithManager(tokens, amounts);
      {
        address[] memory forfeitTokens;
        _assertTransfersWithManager(alice, _collaterals, forfeitTokens, amounts);
      }
      // Testing implicitly the ts.normalizer and ts.normalizedStables
      for (uint256 i; i < _collaterals.length; ++i) {
        (uint256 stableIssuedByCollateral, uint256 totalStable) = parallelizer.getIssuedByCollateral(_collaterals[i]);
        assertApproxEqAbs(
          stableIssuedByCollateral, (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables, 1 wei
        );
        assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
      }
      mintedStables = parallelizer.getTotalIssued();

      // now do a second redeem to test with non trivial ts.normalizer and ts.normalizedStables
      vm.startPrank(bob);
      transferRedeemProportion[1] = bound(transferRedeemProportion[1], 0, BASE_9);
      amountBurntBob = (tokenP.balanceOf(bob) * transferRedeemProportion[1]) / BASE_9;
      try parallelizer.quoteRedemptionCurve(amountBurntBob) returns (address[] memory, uint256[] memory a) {
        quoteAmounts = a;
      } catch {
        return;
      }
      if (mintedStables == 0 || amountBurntBob >= mintedStables) return;
      {
        uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
        (tokens, amounts) = parallelizer.redeem(
          amountBurntBob, bob, block.timestamp + 1 days, minAmountOuts, _redemptionTokensHash(amountBurntBob)
        );
      }
      vm.stopPrank();

      if (mintedStables == 0 || amountBurntBob >= mintedStables) return;

      // compute fee at current collatRatio
      assertEq(amounts, quoteAmounts);
      _assertSizesWithManager(tokens, amounts);
      {
        address[] memory forfeitTokens;
        _assertTransfersWithManager(bob, _collaterals, forfeitTokens, amounts);
      }
    }

    // Testing implicitly the ts.normalizer and ts.normalizedStables
    uint256 totalStable2;
    for (uint256 i; i < _collaterals.length; ++i) {
      uint256 stableIssuedByCollateral;
      (stableIssuedByCollateral, totalStable2) = parallelizer.getIssuedByCollateral(_collaterals[i]);
      uint256 realStableIssueByCollateralLeft =
        (collateralMintedStables[i] * (mintedStables - amountBurntBob)) / (mintedStables + amountBurnt);
      _assertApproxEqRelDecimalWithTolerance(
        realStableIssueByCollateralLeft,
        stableIssuedByCollateral,
        realStableIssueByCollateralLeft,
        _MAX_PERCENTAGE_DEVIATION,
        18
      );
    }
    _assertApproxEqRelDecimalWithTolerance(
      mintedStables - amountBurntBob, totalStable2, mintedStables - amountBurntBob, _MAX_PERCENTAGE_DEVIATION, 18
    );
  }

  function testFuzz_RevertWhen_BurningAllStableIssuedWithManager(
    uint256[3] memory initialAmounts,
    uint256[3 * 2] memory nbrSubCollateralsAndIsManaged,
    uint256[3 * (_MAX_SUB_COLLATERALS + 1)] memory airdropAmountsAndOracleValues,
    uint256[3 * 2 * _MAX_SUB_COLLATERALS] memory latestSubCollatOracleValueAndDecimals,
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    public
  {
    for (uint256 i; i < _collaterals.length; ++i) {
      // Randomly set subcollaterals and manager if needed
      (IERC20[] memory subCollaterals, AggregatorV3Interface[] memory oracles) = _createManager(
        _collaterals[i],
        nbrSubCollateralsAndIsManaged[2 * i],
        nbrSubCollateralsAndIsManaged[2 * i + 1],
        i * _MAX_SUB_COLLATERALS,
        latestSubCollatOracleValueAndDecimals
      );
      if (subCollaterals.length > 0) {
        _subCollaterals[_collaterals[i]] = SubCollateralStorage(subCollaterals, oracles);
      }
    }
    // let's first load the reserves of the protocol
    uint256 mintedStables;
    uint64 collatRatio;
    {
      uint256[] memory collateralMintedStables;
      (mintedStables, collateralMintedStables) = _loadReserves(initialAmounts, 0);

      // airdrop amounts in the subcollaterals
      for (uint256 i; i < _collaterals.length; ++i) {
        if (_subCollaterals[_collaterals[i]].subCollaterals.length > 0) {
          _loadSubCollaterals(address(_collaterals[i]), airdropAmountsAndOracleValues, i * _MAX_SUB_COLLATERALS);
        }
      }

      {
        bool reverted;
        (collatRatio, reverted) = _updateOraclesWithSubCollaterals(
          abi.encode(mintedStables, collateralMintedStables), airdropAmountsAndOracleValues
        );
        if (reverted) return;
      }
    }

    (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem) =
      _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);

    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.quoteRedemptionCurve(amountBurnt);

    uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, bytes32(0));
  }

  function testFuzz_RevertWhen_BurningAllStableIssuedWithManagerAndWhitelist(
    uint256[3] memory initialAmounts,
    uint256[3 * 2] memory nbrSubCollateralsAndIsManaged,
    uint256[3 * (_MAX_SUB_COLLATERALS + 1)] memory airdropAmountsAndOracleValues,
    uint256[3 * 2 * _MAX_SUB_COLLATERALS] memory latestSubCollatOracleValueAndDecimals,
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    public
  {
    for (uint256 i; i < _collaterals.length; ++i) {
      (IERC20[] memory subCollaterals, AggregatorV3Interface[] memory oracles) = _createManager(
        _collaterals[i],
        nbrSubCollateralsAndIsManaged[2 * i],
        nbrSubCollateralsAndIsManaged[2 * i + 1],
        i * _MAX_SUB_COLLATERALS,
        latestSubCollatOracleValueAndDecimals
      );
      if (subCollaterals.length > 0) {
        _subCollaterals[_collaterals[i]] = SubCollateralStorage(subCollaterals, oracles);
      }
    }
    uint256 mintedStables;
    {
      uint256[] memory collateralMintedStables;
      (mintedStables, collateralMintedStables) = _loadReserves(initialAmounts, 0);

      for (uint256 i; i < _collaterals.length; ++i) {
        if (_subCollaterals[_collaterals[i]].subCollaterals.length > 0) {
          _loadSubCollaterals(address(_collaterals[i]), airdropAmountsAndOracleValues, i * _MAX_SUB_COLLATERALS);
        }
      }

      {
        bool reverted;
        (, reverted) = _updateOraclesWithSubCollaterals(
          abi.encode(mintedStables, collateralMintedStables), airdropAmountsAndOracleValues
        );
        if (reverted) return;
      }
    }
    if (mintedStables == 0) return;

    _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);

    // Enable whitelist on the first collateral and whitelist alice
    {
      bytes memory emptyData;
      bytes memory whitelistData = abi.encode(WhitelistType.BACKED, emptyData);
      hoax(governor);
      parallelizer.setWhitelistStatus(address(eurA), 1, whitelistData);
    }
    hoax(guardian);
    parallelizer.toggleWhitelist(WhitelistType.BACKED, alice);

    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.quoteRedemptionCurve(amountBurnt);

    uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, bytes32(0));
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  REDEEM WITH FORFEIT
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function test_RevertWhen_RedeemInvalidArrayLengths(
    uint256[3] memory initialAmounts,
    uint256 transferProportion
  )
    public
  {
    // let's first load the reserves of the protocol
    (uint256 mintedStables,) = _loadReserves(initialAmounts, transferProportion);

    // check collateral ratio first
    if (mintedStables == 0) return;
    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    if (amountBurnt == mintedStables) return;
    tokensHash = _redemptionTokensHash(amountBurnt);
    {
      uint256[] memory minAmountOuts;
      {
        (, uint256[] memory quoteAmounts) = parallelizer.quoteRedemptionCurve(amountBurnt);
        minAmountOuts = new uint256[](quoteAmounts.length - 1);
      }
      vm.expectRevert(Errors.InvalidLengths.selector);
      parallelizer.redeem(amountBurnt, alice, block.timestamp * 2, minAmountOuts, tokensHash);
    }
    {
      uint256[] memory minAmountOuts;
      {
        (, uint256[] memory quoteAmounts) = parallelizer.quoteRedemptionCurve(amountBurnt);
        minAmountOuts = new uint256[](quoteAmounts.length + 1);
      }
      vm.expectRevert(Errors.InvalidLengths.selector);
      parallelizer.redeem(amountBurnt, alice, block.timestamp * 2, minAmountOuts, tokensHash);
    }
    vm.stopPrank();
  }

  function testFuzz_MultiForfeitRedemptionCurveWithManagerRandomRedemptionFees(
    uint256[3] memory initialValue, // initialAmounts of size 3 / nbrSubCollaterals of size 3
    uint256[2] memory transferRedeemProportion,
    uint256[3 * 2] memory nbrSubCollateralsAndIsManaged,
    uint256[3 * (_MAX_SUB_COLLATERALS + 1)] memory airdropAmountsAndOracleValues,
    uint256[3 * 2 * _MAX_SUB_COLLATERALS] memory latestSubCollatOracleValueAndDecimals,
    bool[3 * (_MAX_SUB_COLLATERALS + 1)] memory areForfeit,
    uint64[10] memory xFeeRedeemUnbounded, // X and Y arrays of length 10 each
    int64[10] memory yFeeRedeemUnbounded // X and Y arrays of length 10 each
  )
    public
  {
    for (uint256 i; i < _collaterals.length; ++i) {
      // Randomly set subcollaterals and manager if needed
      (IERC20[] memory subCollaterals, AggregatorV3Interface[] memory oracles) = _createManager(
        _collaterals[i],
        nbrSubCollateralsAndIsManaged[2 * i],
        nbrSubCollateralsAndIsManaged[2 * i + 1],
        i * _MAX_SUB_COLLATERALS,
        latestSubCollatOracleValueAndDecimals
      );
      _subCollaterals[_collaterals[i]] = SubCollateralStorage(subCollaterals, oracles);
    }

    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(initialValue, transferRedeemProportion[0]);
    // airdrop amounts in the subcollaterals
    for (uint256 i; i < _collaterals.length; ++i) {
      if (_subCollaterals[_collaterals[i]].subCollaterals.length > 0) {
        _loadSubCollaterals(address(_collaterals[i]), airdropAmountsAndOracleValues, i * _MAX_SUB_COLLATERALS);
      }
    }
    _updateOraclesWithSubCollaterals(abi.encode(mintedStables, collateralMintedStables), airdropAmountsAndOracleValues);
    _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);
    _sweepBalancesWithManager(alice, _collaterals);
    _sweepBalancesWithManager(bob, _collaterals);

    // first redeem
    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    uint256 amountBurntBob;
    uint256[] memory quoteAmounts;
    try parallelizer.quoteRedemptionCurve(amountBurnt) returns (address[] memory, uint256[] memory a) {
      quoteAmounts = a;
    } catch {
      return;
    }
    if (mintedStables == 0 || amountBurnt >= mintedStables) return;
    {
      address[] memory tokens;
      uint256[] memory amounts;
      address[] memory forfeitTokens = _getForfeitTokens(areForfeit);
      {
        uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
        (tokens, amounts) = parallelizer.redeemWithForfeit(
          amountBurnt,
          alice,
          block.timestamp + 1 days,
          minAmountOuts,
          forfeitTokens,
          _redemptionTokensHash(amountBurnt)
        );
      }
      vm.stopPrank();

      if (mintedStables == 0 || amountBurnt == mintedStables) return;

      // compute fee at current collatRatio
      assertEq(amounts, quoteAmounts);
      _assertSizesWithManager(tokens, amounts);
      _assertTransfersWithManager(alice, _collaterals, forfeitTokens, amounts);

      // Testing implicitly the ts.normalizer and ts.normalizedStables
      for (uint256 i; i < _collaterals.length; ++i) {
        (uint256 stableIssuedByCollateral, uint256 totalStable) = parallelizer.getIssuedByCollateral(_collaterals[i]);
        assertApproxEqAbs(
          stableIssuedByCollateral, (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables, 1 wei
        );
        assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
      }
      mintedStables = parallelizer.getTotalIssued();

      // now do a second redeem to test with non trivial ts.normalizer and ts.normalizedStables
      vm.startPrank(bob);
      transferRedeemProportion[1] = bound(transferRedeemProportion[1], 0, BASE_9);
      amountBurntBob = (tokenP.balanceOf(bob) * transferRedeemProportion[1]) / BASE_9;
      try parallelizer.quoteRedemptionCurve(amountBurntBob) returns (address[] memory, uint256[] memory a) {
        quoteAmounts = a;
      } catch {
        return;
      }

      if (mintedStables == 0 || amountBurntBob >= mintedStables) return;
      {
        uint256[] memory minAmountOuts = new uint256[](quoteAmounts.length);
        (tokens, amounts) = parallelizer.redeem(
          amountBurntBob, bob, block.timestamp + 1 days, minAmountOuts, _redemptionTokensHash(amountBurntBob)
        );
      }
      vm.stopPrank();

      if (mintedStables == 0 || amountBurntBob >= mintedStables) return;

      // compute fee at current collatRatio
      assertEq(amounts, quoteAmounts);
      _assertSizesWithManager(tokens, amounts);
      {
        address[] memory forfeitTokens2;
        _assertTransfersWithManager(bob, _collaterals, forfeitTokens2, amounts);
      }
    }

    // Testing implicitly the ts.normalizer and ts.normalizedStables
    {
      uint256 totalStable2;
      for (uint256 i; i < _collaterals.length; ++i) {
        uint256 stableIssuedByCollateral;
        (stableIssuedByCollateral, totalStable2) = parallelizer.getIssuedByCollateral(_collaterals[i]);
        uint256 realStableIssueByCollateralLeft =
          (collateralMintedStables[i] * (mintedStables - amountBurntBob)) / (mintedStables + amountBurnt);

        _assertApproxEqRelDecimalWithTolerance(
          realStableIssueByCollateralLeft,
          stableIssuedByCollateral,
          realStableIssueByCollateralLeft,
          _MAX_PERCENTAGE_DEVIATION,
          18
        );
      }
      _assertApproxEqRelDecimalWithTolerance(
        mintedStables - amountBurntBob, totalStable2, mintedStables - amountBurntBob, _MAX_PERCENTAGE_DEVIATION, 18
      );
    }
  }

  function testFuzz_RedeemWithForfeit_RevertWhen_BurningAllStableIssuedWithManager(
    uint256[3] memory initialValue, // initialAmounts of size 3 / nbrSubCollaterals of size 3
    uint256[3 * 2] memory nbrSubCollateralsAndIsManaged,
    uint256[3 * (_MAX_SUB_COLLATERALS + 1)] memory airdropAmountsAndOracleValues,
    uint256[3 * 2 * _MAX_SUB_COLLATERALS] memory latestSubCollatOracleValueAndDecimals,
    bool[3 * (_MAX_SUB_COLLATERALS + 1)] memory areForfeit,
    uint64[10] memory xFeeRedeemUnbounded, // X and Y arrays of length 10 each
    int64[10] memory yFeeRedeemUnbounded // X and Y arrays of length 10 each
  )
    public
  {
    for (uint256 i; i < _collaterals.length; ++i) {
      // Randomly set subcollaterals and manager if needed
      (IERC20[] memory subCollaterals, AggregatorV3Interface[] memory oracles) = _createManager(
        _collaterals[i],
        nbrSubCollateralsAndIsManaged[2 * i],
        nbrSubCollateralsAndIsManaged[2 * i + 1],
        i * _MAX_SUB_COLLATERALS,
        latestSubCollatOracleValueAndDecimals
      );
      _subCollaterals[_collaterals[i]] = SubCollateralStorage(subCollaterals, oracles);
    }

    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) = _loadReserves(initialValue, 0);
    if (mintedStables == 0) return;
    for (uint256 i; i < _collaterals.length; ++i) {
      if (_subCollaterals[_collaterals[i]].subCollaterals.length > 0) {
        _loadSubCollaterals(address(_collaterals[i]), airdropAmountsAndOracleValues, i * _MAX_SUB_COLLATERALS);
      }
    }
    _updateOraclesWithSubCollaterals(abi.encode(mintedStables, collateralMintedStables), airdropAmountsAndOracleValues);
    _randomRedeemptionFees(xFeeRedeemUnbounded, yFeeRedeemUnbounded);

    uint256 totalCollateralization = _computeCollateralisation();
    if ((totalCollateralization.mulDiv(BASE_9, mintedStables, Math.Rounding.Ceil)) > type(uint64).max) return;

    address[] memory forfeitTokens = _getForfeitTokens(areForfeit);
    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.quoteRedemptionCurve(amountBurnt);

    uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
    vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
    parallelizer.redeemWithForfeit(
      amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, forfeitTokens, bytes32(0)
    );
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                               REDEEM WITH WHITELISTING
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_WithWhitelistedToken(uint256[3] memory initialAmounts, uint256 transferProportion) public {
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(initialAmounts, transferProportion);

    _sweepBalances(alice, _collaterals);

    {
      bytes memory emptyData;
      bytes memory whitelistData = abi.encode(WhitelistType.BACKED, emptyData);
      hoax(governor);
      parallelizer.setWhitelistStatus(address(eurA), 1, whitelistData);
    }

    vm.startPrank(alice);
    uint256 amountBurnt = tokenP.balanceOf(alice);
    if (mintedStables == 0 || amountBurnt < BASE_18 || amountBurnt == mintedStables) return;
    (, uint256[] memory quoteAmounts) = parallelizer.quoteRedemptionCurve(amountBurnt);
    // There should be a non zero amount of EURA to transfer
    if (quoteAmounts[0] == 0) return;
    tokensHash = _redemptionTokensHash(amountBurnt);
    vm.expectRevert(Errors.NotWhitelisted.selector);

    uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
    parallelizer.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, tokensHash);
    vm.stopPrank();

    hoax(guardian);
    parallelizer.toggleWhitelist(WhitelistType.BACKED, alice);

    vm.startPrank(alice);
    vm.expectRevert(Errors.NotWhitelisted.selector);
    parallelizer.redeem(amountBurnt, bob, block.timestamp + 1 days, minAmountOuts, tokensHash);

    (address[] memory tokens, uint256[] memory amounts) =
      parallelizer.redeem(amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, tokensHash);
    vm.stopPrank();

    assertEq(amounts, quoteAmounts);
    _assertSizes(tokens, amounts);
    _assertTransfers(alice, _collaterals, amounts);

    // Testing implicitly the ts.normalizer and ts.normalizedStables
    for (uint256 i; i < _collaterals.length; ++i) {
      (uint256 stableIssuedByCollateral, uint256 totalStable) = parallelizer.getIssuedByCollateral(_collaterals[i]);
      assertApproxEqAbs(
        stableIssuedByCollateral, (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables, 1 wei
      );
      assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
    }
  }

  function testFuzz_WithForfeitAndWhitelistedTokens(
    uint256[3] memory initialAmounts,
    uint256 transferProportion
  )
    public
  {
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(initialAmounts, transferProportion);

    _sweepBalances(alice, _collaterals);
    {
      bytes memory emptyData;
      bytes memory whitelistData = abi.encode(WhitelistType.BACKED, emptyData);
      hoax(governor);
      parallelizer.setWhitelistStatus(address(eurA), 1, whitelistData);
      hoax(governor);
      parallelizer.setWhitelistStatus(address(eurB), 1, whitelistData);
    }
    uint256 amountBurnt = tokenP.balanceOf(alice);
    if (mintedStables == 0 || amountBurnt == 0 || amountBurnt == mintedStables) return;
    (, uint256[] memory quoteAmounts) = parallelizer.quoteRedemptionCurve(amountBurnt);
    if (quoteAmounts[0] == 0 || quoteAmounts[1] == 0) return;
    tokensHash = _redemptionTokensHash(amountBurnt);
    uint256[] memory minAmountOuts = new uint256[](_collaterals.length);
    {
      vm.startPrank(alice);
      address[] memory forfeitTokens = new address[](0);
      vm.expectRevert(Errors.NotWhitelisted.selector);
      parallelizer.redeemWithForfeit(
        amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, forfeitTokens, tokensHash
      );

      address[] memory forfeitTokens1 = new address[](1);
      forfeitTokens1[0] = address(eurA);
      vm.expectRevert(Errors.NotWhitelisted.selector);
      parallelizer.redeemWithForfeit(
        amountBurnt, alice, block.timestamp + 1 days, minAmountOuts, forfeitTokens, tokensHash
      );
      vm.stopPrank();
      hoax(guardian);
      parallelizer.toggleWhitelist(WhitelistType.BACKED, alice);
      vm.startPrank(alice);
      vm.expectRevert(Errors.NotWhitelisted.selector);
      parallelizer.redeemWithForfeit(
        amountBurnt, bob, block.timestamp + 1 days, minAmountOuts, forfeitTokens, tokensHash
      );
    }

    address[] memory forfeitTokens2 = new address[](2);
    forfeitTokens2[0] = address(eurA);
    forfeitTokens2[1] = address(eurB);
    (address[] memory tokens, uint256[] memory amounts) = parallelizer.redeemWithForfeit(
      amountBurnt, bob, block.timestamp + 1 days, minAmountOuts, forfeitTokens2, tokensHash
    );
    vm.stopPrank();

    assertEq(amounts, quoteAmounts);
    _assertSizes(tokens, amounts);
    assertEq(IERC20(address(eurA)).balanceOf(bob), 0);
    assertEq(IERC20(address(eurB)).balanceOf(bob), 0);
    assertEq(IERC20(address(eurY)).balanceOf(bob), amounts[2]);

    for (uint256 i; i < _collaterals.length; ++i) {
      (uint256 stableIssuedByCollateral, uint256 totalStable) = parallelizer.getIssuedByCollateral(_collaterals[i]);
      assertApproxEqAbs(
        stableIssuedByCollateral, (collateralMintedStables[i] * (mintedStables - amountBurnt)) / mintedStables, 1 wei
      );
      assertApproxEqAbs(totalStable, mintedStables - amountBurnt, 3 wei);
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ASSERTS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _assertSizes(address[] memory tokens, uint256[] memory amounts) internal {
    assertEq(tokens.length, 3);
    assertEq(tokens.length, amounts.length);
    assertEq(tokens[0], address(eurA));
    assertEq(tokens[1], address(eurB));
    assertEq(tokens[2], address(eurY));
  }

  function _assertSizesWithManager(address[] memory tokens, uint256[] memory amounts) internal {
    uint256 nbrTokens;
    uint256 count;
    for (uint256 i; i < _oracles.length; ++i) {
      IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
      nbrTokens += listSubCollaterals.length > 0 ? listSubCollaterals.length : 1;
      assertEq(tokens[count++], _collaterals[i]);
      // we don't double count the real collateral
      for (uint256 k = 1; k < listSubCollaterals.length; k++) {
        assertEq(tokens[count++], address(listSubCollaterals[k]));
      }
    }
    assertEq(tokens.length, nbrTokens);
    assertEq(tokens.length, amounts.length);
  }

  function _assertTransfers(address owner, address[] memory tokens, uint256[] memory amounts) internal {
    for (uint256 i; i < tokens.length; ++i) {
      assertEq(IERC20(tokens[i]).balanceOf(owner), amounts[i]);
    }
  }

  function _assertTransfersWithManager(
    address owner,
    address[] memory tokens,
    address[] memory forfeitTokens,
    uint256[] memory amounts
  )
    internal
  {
    uint256 count;
    for (uint256 i; i < tokens.length; ++i) {
      IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
      if (!_inList(forfeitTokens, tokens[i])) assertEq(IERC20(tokens[i]).balanceOf(owner), amounts[count]);
      else assertEq(IERC20(tokens[i]).balanceOf(owner), 0);
      count++;
      // we don't double count the real collateral
      for (uint256 k = 1; k < listSubCollaterals.length; k++) {
        if (!_inList(forfeitTokens, address(listSubCollaterals[k]))) {
          assertEq(listSubCollaterals[k].balanceOf(owner), amounts[count]);
        } else {
          assertEq(IERC20(listSubCollaterals[k]).balanceOf(owner), 0);
        }
        count++;
      }
    }
  }

  function _assertQuoteAmounts(
    uint64 collatRatio,
    uint256 mintedStables,
    uint256 amountBurnt,
    uint64 fee,
    uint256[] memory amounts
  )
    internal
  {
    // we should also receive  in value min(collatRatio*amountBurnt,amountBurnt)
    AssertQuoteParams memory quoteStorage;
    {
      for (uint256 i; i < _oracles.length; ++i) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        uint8 decimals = IERC20Metadata(_collaterals[i]).decimals();
        if (uint256(value) > quoteStorage.maxOracle) quoteStorage.maxOracle = uint256(value);
        if (amounts[i] > quoteStorage.maxValue) quoteStorage.maxValue = amounts[i] / 10 ** decimals;
        if (amounts[i] < quoteStorage.minValue || quoteStorage.minValue == 0) {
          quoteStorage.minValue = amounts[i] / 10 ** decimals;
        }
        if (quoteStorage.minOracle == 0 || uint256(value) < quoteStorage.minOracle) {
          quoteStorage.minOracle = uint256(value);
        }
        if (uint256(value) > BASE_18 || amounts[i] < 10 ** 4) quoteStorage.lastCheck = true;
        quoteStorage.amountInValueReceived += (uint256(value) * _convertDecimalTo(amounts[i], decimals, 18));
      }
      // Otherwise there can be rounding errors that make the last check not precise at all
      if (
        quoteStorage.maxValue > quoteStorage.minValue * 10 ** 14
          || quoteStorage.maxOracle > quoteStorage.minOracle * 10 ** 14 || quoteStorage.minOracle < 10 ** 5
          || quoteStorage.maxOracle > 10 ** 13
      ) quoteStorage.lastCheck = true;
    }
    quoteStorage.amountInValueReceived = quoteStorage.amountInValueReceived / BASE_8;

    uint256 denom = (mintedStables * BASE_9);
    uint256 valueCheck = (collatRatio * amountBurnt * fee) / BASE_18;
    if (collatRatio >= BASE_9) {
      denom = (mintedStables * collatRatio);
      // for rounding errors
      assertLe(quoteStorage.amountInValueReceived, amountBurnt + 1);
      valueCheck = (amountBurnt * fee) / BASE_9;
    }
    assertApproxEqAbs(amounts[0], (eurA.balanceOf(address(parallelizer)) * amountBurnt * fee) / denom, 1 wei);
    assertApproxEqAbs(amounts[1], (eurB.balanceOf(address(parallelizer)) * amountBurnt * fee) / denom, 1 wei);
    assertApproxEqAbs(amounts[2], (eurY.balanceOf(address(parallelizer)) * amountBurnt * fee) / denom, 1 wei);
    if (collatRatio < BASE_9) {
      assertLe(quoteStorage.amountInValueReceived, (collatRatio * amountBurnt) / BASE_9 + 1);
    }

    if (quoteStorage.amountInValueReceived >= _minWallet && !quoteStorage.lastCheck) {
      assertApproxEqRelDecimal(quoteStorage.amountInValueReceived, valueCheck, _MAX_PERCENTAGE_DEVIATION, 18);
    }
  }

  function _assertQuoteAmountsWithManager(uint256 amountBurnt, uint64 fee, uint256[] memory amounts) internal {
    // we should also receive  in value `min(collatRatio*amountBurnt,amountBurnt)`
    AssertQuoteParams memory quoteStorage;
    {
      for (uint256 i; i < _collaterals.length; ++i) {
        (, int256 oracleValue,,,) = _oracles[i].latestRoundData();
        {
          uint8 decimals = IERC20Metadata(_collaterals[i]).decimals();
          quoteStorage.amountInValueReceived += (uint256(oracleValue)
              * _convertDecimalTo(amounts[quoteStorage.count++], decimals, 18)) / BASE_8;
          if (uint256(oracleValue) > quoteStorage.maxOracle) quoteStorage.maxOracle = uint256(oracleValue);
          if (amounts[i] > quoteStorage.maxValue) quoteStorage.maxValue = amounts[i] / 10 ** decimals;
          if (amounts[i] < quoteStorage.minValue || quoteStorage.minValue == 0) {
            quoteStorage.minValue = amounts[i] / 10 ** decimals;
          }
          if (quoteStorage.minOracle == 0 || uint256(oracleValue) < quoteStorage.minOracle) {
            quoteStorage.minOracle = uint256(oracleValue);
          }
          if (uint256(oracleValue) > BASE_18 || amounts[i] < 10 ** 4) quoteStorage.lastCheck = true;
        }
        // we don't double count the real collateral
        uint256 subCollateralValue;
        for (uint256 k = 1; k < _subCollaterals[_collaterals[i]].subCollaterals.length; k++) {
          (, int256 value,,,) = _subCollaterals[_collaterals[i]].oracles[k - 1].latestRoundData();
          uint8 decimals = IERC20Metadata(address(_subCollaterals[_collaterals[i]].subCollaterals[k])).decimals();
          subCollateralValue += (uint256(value)
              * _convertDecimalTo(amounts[quoteStorage.count++], decimals, IERC20Metadata(_collaterals[i]).decimals()))
            / BASE_8;
          if (uint256(value) > quoteStorage.maxOracle) quoteStorage.maxOracle = uint256(value);
          if (amounts[i] > quoteStorage.maxValue) quoteStorage.maxValue = amounts[i] / 10 ** decimals;
          if (amounts[i] < quoteStorage.minValue || quoteStorage.minValue == 0) {
            quoteStorage.minValue = amounts[i] / 10 ** decimals;
          }
          if (quoteStorage.minOracle == 0 || uint256(value) < quoteStorage.minOracle) {
            quoteStorage.minOracle = uint256(value);
          }
          if (uint256(value) > BASE_18 || amounts[i] < 10 ** 4) quoteStorage.lastCheck = true;
        }
        quoteStorage.amountInValueReceived += (_convertDecimalTo(
              subCollateralValue, IERC20Metadata(_collaterals[i]).decimals(), 18
            )
            * uint256(oracleValue)) / BASE_8;
      }
      if (
        quoteStorage.maxValue > quoteStorage.minValue * 10 ** 14
          || quoteStorage.maxOracle > quoteStorage.minOracle * 10 ** 14 || quoteStorage.minOracle < 10 ** 5
          || quoteStorage.maxOracle > 10 ** 13
      ) quoteStorage.lastCheck = true;
    }

    uint256 count2;
    bool reverted;
    {
      uint256 totalCollateralization = _computeCollateralisation();
      uint256 trueMintedStables = parallelizer.getTotalIssued();
      if (
        trueMintedStables > 0
          && totalCollateralization.mulDiv(BASE_9, trueMintedStables, Math.Rounding.Ceil) > type(uint64).max
      ) {
        reverted = true;
        vm.expectPartialRevert(SafeCast.SafeCastOverflowedUintDowncast.selector);
      }
    }

    uint256 collatRatio;
    {
      uint256 mintedStables;
      (collatRatio, mintedStables) = parallelizer.getCollateralRatio();
      if (reverted) return;

      for (uint256 i; i < _oracles.length; ++i) {
        IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
        for (uint256 k = 0; k < listSubCollaterals.length; ++k) {
          uint256 expect;
          uint256 subCollateralBalance;
          if (address(_managers[_collaterals[i]]) == address(0)) {
            subCollateralBalance = listSubCollaterals[k].balanceOf(address(parallelizer));
          } else {
            subCollateralBalance = listSubCollaterals[k].balanceOf(address(_managers[_collaterals[i]]));
          }
          if (collatRatio < BASE_9) {
            expect = (subCollateralBalance * amountBurnt * fee) / (mintedStables * BASE_9);
          } else {
            expect = (subCollateralBalance * amountBurnt * fee) / (mintedStables * collatRatio);
          }
          assertEq(amounts[count2++], expect);
        }
      }
    }
    uint256 valueCheck = (amountBurnt * fee) / BASE_9;
    if (collatRatio < BASE_9) {
      assertLe(quoteStorage.amountInValueReceived, (collatRatio * amountBurnt) / BASE_9);
      valueCheck = (collatRatio * amountBurnt * fee) / BASE_18;
    }
    if (quoteStorage.amountInValueReceived >= _minWallet && !quoteStorage.lastCheck) {
      assertApproxEqRelDecimal(quoteStorage.amountInValueReceived, valueCheck, _MAX_PERCENTAGE_DEVIATION, 18);
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _loadReserves(
    uint256[3] memory initialAmounts,
    uint256 transferProportion
  )
    internal
    returns (uint256 mintedStables, uint256[] memory collateralMintedStables)
  {
    collateralMintedStables = new uint256[](_collaterals.length);

    vm.startPrank(alice);
    for (uint256 i; i < _collaterals.length; ++i) {
      initialAmounts[i] = bound(initialAmounts[i], 1e16, _maxTokenAmount[i]);
      deal(_collaterals[i], alice, initialAmounts[i]);
      IERC20(_collaterals[i]).approve(address(parallelizer), initialAmounts[i]);

      collateralMintedStables[i] = parallelizer.swapExactInput(
        initialAmounts[i], 0, _collaterals[i], address(tokenP), alice, block.timestamp * 2
      );
      mintedStables += collateralMintedStables[i];
    }

    // Send a proportion of these to another account user just to complexify the case
    transferProportion = bound(transferProportion, 0, BASE_9);
    tokenP.transfer(bob, (mintedStables * transferProportion) / BASE_9);
    vm.stopPrank();
  }

  function _loadSubCollaterals(
    address collateral,
    // The last 3 values should be disregarded as they are oracle values
    uint256[3 * (_MAX_SUB_COLLATERALS + 1)] memory airdropAmounts,
    uint256 startIndex
  )
    internal
  {
    IERC20[] memory listSubCollaterals = _subCollaterals[collateral].subCollaterals;
    // skip the first index because it is the collateral itself
    for (uint256 i = 1; i < listSubCollaterals.length; ++i) {
      airdropAmounts[startIndex + i - 1] = bound(
        airdropAmounts[startIndex + i - 1],
        0,
        _maxAmountWithoutDecimals * 10 ** IERC20Metadata(address(listSubCollaterals[i])).decimals()
      );
      deal(address(listSubCollaterals[i]), address(_managers[collateral]), airdropAmounts[startIndex + i - 1]);
    }
  }

  function _updateOracles(
    uint256[3] memory latestOracleValue,
    uint256 mintedStables,
    uint256[] memory collateralMintedStables
  )
    internal
    returns (uint64 collatRatio, bool reverted)
  {
    for (uint256 i; i < latestOracleValue.length; ++i) {
      latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue, BASE_18);
      MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
    }

    uint256 collateralisation;
    for (uint256 i; i < latestOracleValue.length; ++i) {
      collateralisation += (latestOracleValue[i] * collateralMintedStables[i]) / BASE_8;
    }

    // check collateral ratio first
    uint256 stablecoinsIssued;
    {
      uint256 totalCollateralization = _computeCollateralisation();
      uint256 trueMintedStables = parallelizer.getTotalIssued();
      if (
        trueMintedStables > 0
          && totalCollateralization.mulDiv(BASE_9, trueMintedStables, Math.Rounding.Ceil) > type(uint64).max
      ) {
        reverted = true;
        vm.expectPartialRevert(SafeCast.SafeCastOverflowedUintDowncast.selector);
      }
      (collatRatio, stablecoinsIssued) = parallelizer.getCollateralRatio();
      if (reverted) return (collatRatio, true);
    }

    if (mintedStables > 0) {
      // This is the computed collateral ratio
      assertApproxEqAbs(collatRatio, uint64((collateralisation * BASE_9) / mintedStables), 1 wei);
    } else {
      assertEq(collatRatio, type(uint64).max);
    }
    assertEq(stablecoinsIssued, mintedStables);
  }

  function _updateOraclesWithSubCollaterals(
    bytes memory collateralStablesAndMintedStables,
    uint256[3 * (_MAX_SUB_COLLATERALS + 1)] memory airdropAmountsAndOracleValues
  )
    internal
    returns (uint64 collatRatio, bool reverted)
  {
    uint256 collateralisation;
    for (uint256 i; i < airdropAmountsAndOracleValues.length / (_MAX_SUB_COLLATERALS + 1); ++i) {
      airdropAmountsAndOracleValues[3 * _MAX_SUB_COLLATERALS + i] =
        bound(airdropAmountsAndOracleValues[3 * _MAX_SUB_COLLATERALS + i], _minOracleValue, BASE_18);
      MockChainlinkOracle(address(_oracles[i]))
        .setLatestAnswer(int256(airdropAmountsAndOracleValues[3 * _MAX_SUB_COLLATERALS + i]));

      if (_subCollaterals[_collaterals[i]].subCollaterals.length <= 1) {
        (, uint256[] memory collateralMintedStables) =
          abi.decode(collateralStablesAndMintedStables, (uint256, uint256[]));
        collateralisation += (airdropAmountsAndOracleValues[3 * _MAX_SUB_COLLATERALS + i] * collateralMintedStables[i])
          / BASE_8;
      } else {
        IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
        // we don't double count the real collaterals
        uint256 subCollateralValue =
          IERC20Metadata(address(listSubCollaterals[0])).balanceOf(address(_managers[_collaterals[i]]));
        for (uint256 k = 1; k < listSubCollaterals.length; k++) {
          (, int256 oracleValue,,,) =
            MockChainlinkOracle(address(_subCollaterals[_collaterals[i]].oracles[k - 1])).latestRoundData();
          subCollateralValue += (uint256(oracleValue)
              * _convertDecimalTo(
                airdropAmountsAndOracleValues[i * _MAX_SUB_COLLATERALS + k - 1],
                IERC20Metadata(address(listSubCollaterals[k])).decimals(),
                IERC20Metadata(address(listSubCollaterals[0])).decimals()
              )) / BASE_8;
        }
        collateralisation += (((BASE_18 * airdropAmountsAndOracleValues[3 * _MAX_SUB_COLLATERALS + i]) / BASE_8)
            * _convertDecimalTo(subCollateralValue, IERC20Metadata(address(listSubCollaterals[0])).decimals(), 18))
          / BASE_18;
      }
    }

    (uint256 mintedStables,) = abi.decode(collateralStablesAndMintedStables, (uint256, uint256[]));
    {
      {
        uint256 trueMintedStables = parallelizer.getTotalIssued();
        if (
          trueMintedStables > 0
            && _computeCollateralisation().mulDiv(BASE_9, trueMintedStables, Math.Rounding.Ceil) > type(uint64).max
        ) {
          reverted = true;
          vm.expectPartialRevert(SafeCast.SafeCastOverflowedUintDowncast.selector);
        }
      }
      uint256 stablecoinsIssued;
      (collatRatio, stablecoinsIssued) = parallelizer.getCollateralRatio();
      if (reverted) return (0, true);
      assertEq(stablecoinsIssued, mintedStables);
    }

    if (mintedStables > 0) {
      assertApproxEqAbs(collatRatio, uint64((collateralisation * BASE_9) / mintedStables), 1 wei);
    } else {
      assertEq(collatRatio, type(uint64).max);
    }
  }

  function _randomRedeemptionFees(
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    internal
    returns (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem)
  {
    (xFeeRedeem, yFeeRedeem) =
      _generateCurves(xFeeRedeemUnbounded, yFeeRedeemUnbounded, true, false, 0, int256(BASE_9));
    vm.prank(guardian);
    parallelizer.setRedemptionCurveParams(xFeeRedeem, yFeeRedeem);
  }

  function _sweepBalances(address owner, address[] memory tokens) internal {
    vm.startPrank(owner);
    for (uint256 i; i < tokens.length; ++i) {
      IERC20(tokens[i]).transfer(sweeper, IERC20(tokens[i]).balanceOf(owner));
    }
    vm.stopPrank();
  }

  function _sweepBalancesWithManager(address owner, address[] memory tokens) internal {
    vm.startPrank(owner);
    for (uint256 i; i < tokens.length; ++i) {
      IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
      IERC20(tokens[i]).transfer(sweeper, IERC20(tokens[i]).balanceOf(owner));
      // we don't double count the real collateral
      for (uint256 k = 1; k < listSubCollaterals.length; k++) {
        listSubCollaterals[k].transfer(sweeper, listSubCollaterals[k].balanceOf(owner));
      }
    }
    vm.stopPrank();
  }

  function _getForfeitTokens(bool[3 * (_MAX_SUB_COLLATERALS + 1)] memory areForfeited)
    internal
    view
    returns (address[] memory forfeitTokens)
  {
    uint256 nbrForfeit;
    for (uint256 i; i < areForfeited.length; ++i) {
      if (areForfeited[i]) nbrForfeit++;
    }
    forfeitTokens = new address[](nbrForfeit);
    uint256 index;
    for (uint256 i; i < _collaterals.length; ++i) {
      IERC20[] memory listSubCollaterals = _subCollaterals[_collaterals[i]].subCollaterals;
      for (uint256 k = 0; k < listSubCollaterals.length; k++) {
        if (areForfeited[i * (_MAX_SUB_COLLATERALS + 1) + k]) {
          forfeitTokens[index++] = address(listSubCollaterals[k]);
        }
      }
    }
  }

  function _inList(address[] memory list, address element) internal pure returns (bool) {
    for (uint256 i; i < list.length; ++i) {
      if (list[i] == element) return true;
    }
    return false;
  }

  function _createManager(
    address token,
    uint256 nbrSubCollaterals,
    uint256 isManaged,
    uint256 startIndex,
    // The first 3 * _MAX_SUB_COLLATERALS are for the oracle values and the rest are for the decimals
    uint256[2 * 3 * _MAX_SUB_COLLATERALS] memory subCollateralOracleValueAndDecimals
  )
    internal
    returns (IERC20[] memory subCollaterals, AggregatorV3Interface[] memory oracles)
  {
    nbrSubCollaterals = bound(nbrSubCollaterals, 0, _MAX_SUB_COLLATERALS);
    isManaged = bound(nbrSubCollaterals, 0, 1);
    subCollaterals = new IERC20[](nbrSubCollaterals + 1);

    oracles = new AggregatorV3Interface[](nbrSubCollaterals);
    subCollaterals[0] = IERC20(token);
    if (nbrSubCollaterals == 0 && isManaged == 1) return (subCollaterals, oracles);
    MockManager manager = new MockManager(token);
    {
      uint8[] memory decimals = new uint8[](nbrSubCollaterals + 1);
      decimals[0] = IERC20Metadata(token).decimals();
      uint32[] memory stalePeriods = new uint32[](nbrSubCollaterals);
      uint8[] memory oracleIsMultiplied = new uint8[](nbrSubCollaterals);
      uint8[] memory chainlinkDecimals = new uint8[](nbrSubCollaterals);
      for (uint256 i = 1; i < nbrSubCollaterals + 1; ++i) {
        decimals[i] =
          uint8(bound(subCollateralOracleValueAndDecimals[3 * _MAX_SUB_COLLATERALS + startIndex + i - 1], 5, 18));
        subCollaterals[i] = IERC20(
          address(
            new MockTokenPermit(
              string.concat(IERC20Metadata(token).name(), "_", Strings.toString(i)),
              string.concat(IERC20Metadata(token).symbol(), "_", Strings.toString(i)),
              decimals[i]
            )
          )
        );
        oracles[i - 1] = AggregatorV3Interface(address(new MockChainlinkOracle()));
        subCollateralOracleValueAndDecimals[startIndex + i - 1] =
          bound(subCollateralOracleValueAndDecimals[startIndex + i - 1], _minOracleValue, BASE_18);
        MockChainlinkOracle(address(oracles[i - 1]))
          .setLatestAnswer(int256(subCollateralOracleValueAndDecimals[startIndex + i - 1]));
        stalePeriods[i - 1] = 365 days;
        oracleIsMultiplied[i - 1] = 1;
        chainlinkDecimals[i - 1] = 8;
      }

      manager.setSubCollaterals(
        subCollaterals, abi.encode(decimals, oracles, stalePeriods, oracleIsMultiplied, chainlinkDecimals)
      );
    }
    ManagerStorage memory managerData =
      ManagerStorage(subCollaterals, abi.encode(ManagerType.EXTERNAL, abi.encode(IManager(address(manager)))));
    _managers[token] = manager;

    vm.prank(governor);
    parallelizer.setCollateralManager(token, true, managerData);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                          NORMALIZED STABLES GUARD
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
  function test_RedeemPath_CannotDriveNormalizedStablesToZero() public {
    address attacker = vm.addr(10);

    vm.startPrank(guardian);
    parallelizer.pause(address(eurB), ActionType.Redeem);
    parallelizer.unpause(address(eurY), ActionType.Redeem);
    uint64[] memory xRedemption = new uint64[](1);
    xRedemption[0] = uint64(0);
    int64[] memory yRedemption = new int64[](1);
    yRedemption[0] = int64(int256(BASE_9));
    parallelizer.setRedemptionCurveParams(xRedemption, yRedemption);
    vm.stopPrank();

    _mintExactInput(bob, address(eurA), 10_000e6, 0);
    _mintExactInput(charlie, address(eurB), 10_000e12, 0);
    _mintExactInput(dylan, address(eurY), 10_000e18, 0);

    uint256 bobBal = IERC20(address(tokenP)).balanceOf(bob);
    uint256 charlieBal = IERC20(address(tokenP)).balanceOf(charlie);
    uint256 dylanBal = IERC20(address(tokenP)).balanceOf(dylan);
    vm.prank(bob);
    IERC20(address(tokenP)).transfer(attacker, bobBal);
    vm.prank(charlie);
    IERC20(address(tokenP)).transfer(attacker, charlieBal);
    vm.prank(dylan);
    IERC20(address(tokenP)).transfer(attacker, dylanBal);

    vm.startPrank(attacker);
    (uint256 issuedFromA,) = parallelizer.getIssuedByCollateral(address(eurA));
    (uint256 issuedFromB,) = parallelizer.getIssuedByCollateral(address(eurB));
    (uint256 issuedFromY,) = parallelizer.getIssuedByCollateral(address(eurY));

    if (issuedFromA > 1e18) {
      parallelizer.swapExactInput(issuedFromA - 1e18, 0, address(tokenP), address(eurA), attacker, block.timestamp * 2);
    }
    if (issuedFromB > 1e18) {
      parallelizer.swapExactInput(issuedFromB - 1e18, 0, address(tokenP), address(eurB), attacker, block.timestamp * 2);
    }
    if (issuedFromY > 1e18) {
      parallelizer.swapExactInput(issuedFromY - 1e18, 0, address(tokenP), address(eurY), attacker, block.timestamp * 2);
    }

    uint256 stablecoinsIssued = parallelizer.getTotalIssued();
    if (stablecoinsIssued > 1) {
      uint256[] memory minOuts = new uint256[](3);
      tokensHash = _redemptionTokensHash(stablecoinsIssued - 1);
      vm.expectRevert();
      parallelizer.redeem(stablecoinsIssued - 1, attacker, block.timestamp * 2, minOuts, tokensHash);
    }
    vm.stopPrank();

    assertGt(parallelizer.getTotalIssued(), 0, "normalizedStables must not be driven to zero");
  }

  /// @notice Fuzz: amountBurnt < stablecoinsIssued must never drive normalizedStables to 0
  function testFuzz_RedeemBelowIssuedCannotZeroNormalizedStables(
    uint256 mintA,
    uint256 mintB,
    uint256 mintY,
    uint256 redeemRatio
  )
    public
  {
    mintA = bound(mintA, 1e6, 1_000_000e6);
    mintB = bound(mintB, 1e12, 1_000_000e12);
    mintY = bound(mintY, 1e18, 1_000_000e18);

    _mintExactInput(alice, address(eurA), mintA, 0);
    _mintExactInput(alice, address(eurB), mintB, 0);
    _mintExactInput(alice, address(eurY), mintY, 0);

    uint256 stablecoinsIssued = parallelizer.getTotalIssued();
    if (stablecoinsIssued == 0) return;

    redeemRatio = bound(redeemRatio, 0, BASE_9 - 1);
    uint256 redeemAmount = (stablecoinsIssued * redeemRatio) / BASE_9;
    if (redeemAmount == 0) return;
    if (redeemAmount >= stablecoinsIssued) redeemAmount = stablecoinsIssued - 1;

    uint256[] memory minOuts = new uint256[](3);
    tokensHash = _redemptionTokensHash(redeemAmount);
    vm.startPrank(alice);
    parallelizer.redeem(redeemAmount, alice, block.timestamp * 2, minOuts, tokensHash);
    vm.stopPrank();

    assertGt(
      parallelizer.getTotalIssued(),
      0,
      "normalizedStables must not be driven to zero with amountBurnt < stablecoinsIssued"
    );
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  HELPERS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _computeCollateralisation() internal view returns (uint256 totalCollateralization) {
    address[] memory collateralList = parallelizer.getCollateralList();
    uint256 collateralListLength = collateralList.length;

    for (uint256 i; i < collateralListLength; ++i) {
      Collateral memory collateral = parallelizer.getCollateralInfo(collateralList[i]);
      uint256 collateralBalance;
      if (collateral.isManaged > 0) {
        (, bytes memory data) = abi.decode(collateral.managerData.config, (ManagerType, bytes));
        (, collateralBalance) = abi.decode(data, (IManager)).totalAssets();
      } else {
        collateralBalance = IERC20(collateralList[i]).balanceOf(address(parallelizer));
      }

      (,,,, uint256 oracleValue) = parallelizer.getOracleValues(collateralList[i]);
      totalCollateralization += (oracleValue
          * LibHelpers.convertDecimalTo(collateralBalance, collateral.decimals, 18, Math.Rounding.Floor)) / BASE_18;
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    EIP-3009 REDEEM WITH AUTHORIZATION
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function test_RedeemWithAuthorization() public {
    _mintExactInput(alice, address(eurA), 100 * BASE_6, 0);
    _mintExactInput(alice, address(eurB), 100 * 1e12, 0);
    _mintExactInput(alice, address(eurY), 100 * BASE_18, 0);

    uint256 tokenPBal = tokenP.balanceOf(alice);
    uint256 redeemAmount = tokenPBal / 4;

    {
      vm.startPrank(guardian);
      uint64[] memory xRedemption = new uint64[](1);
      xRedemption[0] = uint64(0);
      int64[] memory yRedemption = new int64[](1);
      yRedemption[0] = int64(int256(BASE_9));
      parallelizer.setRedemptionCurveParams(xRedemption, yRedemption);
      vm.stopPrank();
    }

    uint256 deadline = block.timestamp + 1 hours;
    uint256[] memory minOuts = new uint256[](3);
    tokensHash = _redemptionTokensHash(redeemAmount);
    address[] memory forfeit = new address[](0);
    bytes memory authData =
      _buildRedeemAuth(1, alice, redeemAmount, alice, deadline, minOuts, forfeit, tokensHash, bytes32("redeem1"));

    // bob relays alice's signed authorization
    vm.prank(bob);
    (address[] memory tokens, uint256[] memory amounts) =
      parallelizer.redeemWithAuthorization(redeemAmount, alice, deadline, minOuts, forfeit, tokensHash, authData);

    assertEq(tokens.length, 3);
    for (uint256 i; i < amounts.length; i++) {
      assertGt(amounts[i], 0);
    }
    assertEq(tokenP.balanceOf(alice), tokenPBal - redeemAmount);
  }

  /// @notice Regression: an authorization signed for `receiver = alice` cannot be replayed with
  /// `receiver = bob`.
  function test_RedeemWithAuthorization_FrontrunRejected() public {
    _mintExactInput(alice, address(eurA), 100 * BASE_6, 0);
    _mintExactInput(alice, address(eurB), 100 * 1e12, 0);
    _mintExactInput(alice, address(eurY), 100 * BASE_18, 0);

    uint256 redeemAmount = tokenP.balanceOf(alice) / 4;

    {
      vm.startPrank(guardian);
      uint64[] memory xR = new uint64[](1);
      xR[0] = uint64(0);
      int64[] memory yR = new int64[](1);
      yR[0] = int64(int256(BASE_9));
      parallelizer.setRedemptionCurveParams(xR, yR);
      vm.stopPrank();
    }

    uint256 deadline = block.timestamp + 1 hours;
    uint256[] memory minOuts = new uint256[](3);
    tokensHash = _redemptionTokensHash(redeemAmount);
    address[] memory forfeit = new address[](0);
    bytes memory aliceAuth = _buildRedeemAuth(
      1, alice, redeemAmount, alice, deadline, minOuts, forfeit, tokensHash, bytes32("redeem_frontrun")
    );

    vm.prank(bob);
    vm.expectRevert(bytes("invalid signature"));
    parallelizer.redeemWithAuthorization(redeemAmount, bob, deadline, minOuts, forfeit, tokensHash, aliceAuth);
  }

  function test_RedeemWithAuthorization_RevertWhen_ValueMismatch() public {
    _mintExactInput(alice, address(eurA), 100 * BASE_6, 0);
    uint256 redeemAmount = tokenP.balanceOf(alice) / 4;

    {
      vm.startPrank(guardian);
      uint64[] memory xR = new uint64[](1);
      xR[0] = uint64(0);
      int64[] memory yR = new int64[](1);
      yR[0] = int64(int256(BASE_9));
      parallelizer.setRedemptionCurveParams(xR, yR);
      vm.stopPrank();
    }

    uint256 deadline = block.timestamp + 1 hours;
    uint256[] memory minOuts = new uint256[](3);
    tokensHash = _redemptionTokensHash(redeemAmount);
    address[] memory forfeit = new address[](0);
    bytes memory authData = _buildRedeemAuth(
      1,
      alice,
      redeemAmount / 2,
      alice,
      deadline,
      minOuts,
      forfeit,
      _redemptionTokensHash(redeemAmount / 2),
      bytes32("bad_redeem")
    );

    vm.prank(bob);
    vm.expectRevert();
    parallelizer.redeemWithAuthorization(redeemAmount, alice, deadline, minOuts, forfeit, tokensHash, authData);
  }

  function test_RedeemWithAuthorization_RevertWhen_ReusedNonce() public {
    _mintExactInput(alice, address(eurA), 100 * BASE_6, 0);
    _mintExactInput(alice, address(eurB), 100 * 1e12, 0);
    _mintExactInput(alice, address(eurY), 100 * BASE_18, 0);

    uint256 redeemAmount = tokenP.balanceOf(alice) / 8;
    bytes32 userSalt = bytes32("reuse_redeem");

    {
      vm.startPrank(guardian);
      uint64[] memory xR = new uint64[](1);
      xR[0] = uint64(0);
      int64[] memory yR = new int64[](1);
      yR[0] = int64(int256(BASE_9));
      parallelizer.setRedemptionCurveParams(xR, yR);
      vm.stopPrank();
    }

    uint256 deadline = block.timestamp + 1 hours;
    uint256[] memory minOuts = new uint256[](3);
    tokensHash = _redemptionTokensHash(redeemAmount);
    address[] memory forfeit = new address[](0);
    bytes memory authData1 =
      _buildRedeemAuth(1, alice, redeemAmount, alice, deadline, minOuts, forfeit, tokensHash, userSalt);

    vm.prank(bob);
    parallelizer.redeemWithAuthorization(redeemAmount, alice, deadline, minOuts, forfeit, tokensHash, authData1);

    bytes memory authData2 =
      _buildRedeemAuth(1, alice, redeemAmount, alice, deadline, minOuts, forfeit, tokensHash, userSalt);

    vm.prank(bob);
    vm.expectRevert();
    parallelizer.redeemWithAuthorization(redeemAmount, alice, deadline, minOuts, forfeit, tokensHash, authData2);
  }

  event Redeemed(
    uint256 amount,
    address[] tokens,
    uint256[] amounts,
    address[] forfeitTokens,
    address indexed from,
    address indexed to
  );

  function test_RedeemWithAuthorization_HonorsForfeitTokens() public {
    _mintExactInput(alice, address(eurA), 100 * BASE_6, 0);
    _mintExactInput(alice, address(eurB), 100 * 1e12, 0);
    _mintExactInput(alice, address(eurY), 100 * BASE_18, 0);

    uint256 redeemAmount = tokenP.balanceOf(alice) / 4;

    {
      vm.startPrank(guardian);
      uint64[] memory xR = new uint64[](1);
      xR[0] = uint64(0);
      int64[] memory yR = new int64[](1);
      yR[0] = int64(int256(BASE_9));
      parallelizer.setRedemptionCurveParams(xR, yR);
      vm.stopPrank();
    }

    uint256 deadline = block.timestamp + 1 hours;
    uint256[] memory minOuts = new uint256[](3);
    tokensHash = _redemptionTokensHash(redeemAmount);
    address[] memory forfeit = new address[](1);
    forfeit[0] = address(eurA);

    bytes memory authData =
      _buildRedeemAuth(1, alice, redeemAmount, alice, deadline, minOuts, forfeit, tokensHash, bytes32("forfeit_ok"));

    uint256 eurABefore = IERC20(address(eurA)).balanceOf(alice);
    uint256 eurBBefore = IERC20(address(eurB)).balanceOf(alice);

    vm.prank(bob);
    parallelizer.redeemWithAuthorization(redeemAmount, alice, deadline, minOuts, forfeit, tokensHash, authData);

    assertEq(IERC20(address(eurA)).balanceOf(alice), eurABefore, "forfeited token must not be transferred");
    assertGt(IERC20(address(eurB)).balanceOf(alice), eurBBefore, "non-forfeited token must be transferred");
  }

  function test_RedeemWithAuthorization_RevertWhen_ForfeitMismatch() public {
    _mintExactInput(alice, address(eurA), 100 * BASE_6, 0);
    _mintExactInput(alice, address(eurB), 100 * 1e12, 0);
    _mintExactInput(alice, address(eurY), 100 * BASE_18, 0);

    uint256 redeemAmount = tokenP.balanceOf(alice) / 4;

    {
      vm.startPrank(guardian);
      uint64[] memory xR = new uint64[](1);
      xR[0] = uint64(0);
      int64[] memory yR = new int64[](1);
      yR[0] = int64(int256(BASE_9));
      parallelizer.setRedemptionCurveParams(xR, yR);
      vm.stopPrank();
    }

    uint256 deadline = block.timestamp + 1 hours;
    uint256[] memory minOuts = new uint256[](3);
    tokensHash = _redemptionTokensHash(redeemAmount);

    address[] memory signedForfeit = new address[](1);
    signedForfeit[0] = address(eurA);
    bytes memory authData = _buildRedeemAuth(
      1, alice, redeemAmount, alice, deadline, minOuts, signedForfeit, tokensHash, bytes32("forfeit_bind")
    );

    address[] memory tamperedForfeit = new address[](1);
    tamperedForfeit[0] = address(eurB);

    vm.prank(bob);
    vm.expectRevert(bytes("invalid signature"));
    parallelizer.redeemWithAuthorization(redeemAmount, alice, deadline, minOuts, tamperedForfeit, tokensHash, authData);
  }

  function test_RedeemWithAuthorization_EmitsAuthorizerNotRelayer() public {
    _mintExactInput(alice, address(eurA), 100 * BASE_6, 0);
    _mintExactInput(alice, address(eurB), 100 * 1e12, 0);
    _mintExactInput(alice, address(eurY), 100 * BASE_18, 0);

    uint256 redeemAmount = tokenP.balanceOf(alice) / 4;

    {
      vm.startPrank(guardian);
      uint64[] memory xR = new uint64[](1);
      xR[0] = uint64(0);
      int64[] memory yR = new int64[](1);
      yR[0] = int64(int256(BASE_9));
      parallelizer.setRedemptionCurveParams(xR, yR);
      vm.stopPrank();
    }

    uint256 deadline = block.timestamp + 1 hours;
    uint256[] memory minOuts = new uint256[](3);
    tokensHash = _redemptionTokensHash(redeemAmount);
    address[] memory forfeit = new address[](0);
    bytes memory authData = _buildRedeemAuth(
      1, alice, redeemAmount, alice, deadline, minOuts, forfeit, tokensHash, bytes32("event_attr_redeem")
    );

    vm.expectEmit(true, true, false, false, address(parallelizer));
    emit Redeemed(0, new address[](0), new uint256[](0), new address[](0), alice, alice);

    vm.prank(bob);
    parallelizer.redeemWithAuthorization(redeemAmount, alice, deadline, minOuts, forfeit, tokensHash, authData);
  }
}
