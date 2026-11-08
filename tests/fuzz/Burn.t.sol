// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "contracts/parallelizer/Storage.sol" as Storage;
import "contracts/utils/Errors.sol" as Errors;

import { ManagerStorage, ManagerType, WhitelistType } from "contracts/parallelizer/Storage.sol";
import { LibAuthorization } from "contracts/parallelizer/libraries/LibAuthorization.sol";
import { MockManager } from "../mock/MockManager.sol";
import { Mock1271Signer } from "../mock/Mock1271Signer.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";

contract BurnTest is Fixture, FunctionUtils {
  using SafeERC20 for IERC20;

  event Swap(
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 amountIn,
    uint256 amountOut,
    address indexed from,
    address to
  );

  uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
  // making this value smaller worsen rounding and make test harder to pass.
  // Trade off between bullet proof against all oracles and all interactions
  uint256 internal _minOracleValue = 10 ** 3; // 10**(-6)
  uint256 internal _minWallet = 10 ** 18; // in base 18
  uint256 internal _maxWallet = 10 ** (18 + 12); // in base 18
  int64 internal _minBurnFee = -int64(int256(BASE_9 / 2));

  address[] internal _collaterals;
  AggregatorV3Interface[] internal _oracles;
  uint256[] internal _maxTokenAmount;

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

    // Required for setting negative fees
    vm.startPrank(governor);
    accessManager.grantRole(GUARDIAN_ROLE, governor, 0);
    vm.stopPrank();
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 GETISSUEDBYCOLLATERAL
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_BurnGetIssuedByCollateral(
    uint256[3] memory initialAmounts,
    uint256[3] memory amounts,
    uint256[3] memory burntAmounts,
    uint256[3] memory latestOracleValue
  )
    public
  {
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(charlie, sweeper, initialAmounts, 0);
    _setMintFeesForNegativeBurnFees(0);
    _updateOracles(latestOracleValue);

    // let's first load the reserves of the protocol
    (uint256 mintedStables2, uint256[] memory collateralMintedStables2) = _loadReserves(charlie, sweeper, amounts, 0);

    (bool succeed, uint256 burntStables, uint256[] memory collateralBurntStables) =
      _emptyReserves(charlie, burntAmounts);
    if (!succeed) return;

    uint256 computedTotalStable = mintedStables + mintedStables2;
    for (uint256 i; i < collateralMintedStables.length; i++) {
      computedTotalStable -= collateralBurntStables[i];
      (uint256 stablecoinsFromCollateral,) = parallelizer.getIssuedByCollateral(address(_collaterals[i]));
      assertEq(
        collateralMintedStables[i] + collateralMintedStables2[i] - collateralBurntStables[i], stablecoinsFromCollateral
      );
    }

    assertEq(computedTotalStable, tokenP.totalSupply());
    assertEq(mintedStables + mintedStables2 - burntStables, tokenP.totalSupply());
    (, uint256 totalStablecoins) = parallelizer.getIssuedByCollateral(address(_collaterals[0]));
    assertEq(computedTotalStable, totalStablecoins);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  GETCOLLATERALRATIO
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_BurnGetCollateralRatio(
    uint256[3] memory initialAmounts,
    uint256[3] memory amounts,
    uint256[3] memory burntAmounts,
    uint256[3] memory latestOracleValue
  )
    public
  {
    // let's first load the reserves of the protocol
    (uint256 mintedStables,) = _loadReserves(charlie, sweeper, initialAmounts, 0);
    _setMintFeesForNegativeBurnFees(0);
    _updateOracles(latestOracleValue);

    // let's first load the reserves of the protocol
    (uint256 mintedStables2,) = _loadReserves(charlie, sweeper, amounts, 0);

    (bool succeed, uint256 burntStables,) = _emptyReserves(charlie, burntAmounts);
    if (!succeed) return;

    uint256 collateralisation;
    for (uint256 i; i < _collaterals.length; ++i) {
      (, int256 oracleValue,,,) = MockChainlinkOracle(address(_oracles[i])).latestRoundData();
      uint8 decimals = IERC20Metadata(address(_collaterals[i])).decimals();
      collateralisation += ((IERC20(_collaterals[i]).balanceOf(address(parallelizer))
            * 10
            ** (18 - decimals)
            * uint256(oracleValue))
          / BASE_8);
    }

    uint256 computedCollatRatio = type(uint64).max;
    if (mintedStables + mintedStables2 - burntStables > 0) {
      computedCollatRatio = uint64((collateralisation * BASE_9) / (mintedStables + mintedStables2 - burntStables));
      if ((collateralisation * BASE_9) / (mintedStables + mintedStables2 - burntStables) > type(uint64).max) {
        vm.expectRevert();
        parallelizer.getCollateralRatio();
        return;
      }
    }

    (uint64 collatRatio, uint256 reservesValue) = parallelizer.getCollateralRatio();
    assertApproxEqAbs(computedCollatRatio, collatRatio, 1 wei);
    assertApproxEqAbs(mintedStables + mintedStables2 - burntStables, reservesValue, 1 wei);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         BURN
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_QuoteBurnExactInputSimple(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256 burnAmount,
    uint256 fromToken
  )
    public
  {
    // let's first load the reserves of the protocol
    (, uint256[] memory collateralMintedStables) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);

    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
    uint256 amountOut = parallelizer.quoteIn(burnAmount, address(tokenP), _collaterals[fromToken]);

    assertEq(_convertDecimalTo(burnAmount, 18, IERC20Metadata(_collaterals[fromToken]).decimals()), amountOut);
  }

  function testFuzz_QuoteBurnExactInputNonNullFees(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    int64 burnFee,
    uint256 burnAmount,
    uint256 fromToken
  )
    public
  {
    // let's first load the reserves of the protocol
    (, uint256[] memory collateralMintedStables) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
    burnFee = int64(bound(int256(burnFee), 0, int256(BASE_9) - (2 * int256(BASE_9)) / 1000));
    uint64[] memory xFeeBurn = new uint64[](1);
    xFeeBurn[0] = uint64(BASE_9);
    int64[] memory yFeeBurn = new int64[](1);
    yFeeBurn[0] = burnFee;
    vm.prank(governor);
    parallelizer.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

    if (burnFee >= int256((BASE_9 * 999) / 1000)) vm.expectRevert(Errors.InvalidSwap.selector);
    uint256 amountOut = parallelizer.quoteIn(burnAmount, address(tokenP), _collaterals[fromToken]);
    if (burnFee >= int256((BASE_9 * 999) / 1000)) return;
    uint256 supposedAmountOut =
      (_convertDecimalTo(
        (burnAmount * (BASE_9 - uint64(burnFee))) / BASE_9, 18, IERC20Metadata(_collaterals[fromToken]).decimals()
      ));

    assertEq(supposedAmountOut, amountOut);
  }

  function testFuzz_QuoteBurnReflexivitySimple(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256 burnAmount,
    uint256 fromToken
  )
    public
  {
    // let's first load the reserves of the protocol
    (, uint256[] memory collateralMintedStables) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);

    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
    uint256 amountOut = parallelizer.quoteIn(burnAmount, address(tokenP), _collaterals[fromToken]);
    uint256 reflexiveBurnAmount = parallelizer.quoteOut(amountOut, address(tokenP), _collaterals[fromToken]);
    if (amountOut == 0) return;
    _assertApproxEqRelDecimalWithTolerance(
      amountOut,
      _convertDecimalTo(burnAmount, 18, IERC20Metadata(_collaterals[fromToken]).decimals()),
      _convertDecimalTo(burnAmount, 18, IERC20Metadata(_collaterals[fromToken]).decimals()),
      _MAX_PERCENTAGE_DEVIATION,
      18
    );
    if (amountOut > _minWallet) {
      _assertApproxEqRelDecimalWithTolerance(
        burnAmount, reflexiveBurnAmount, burnAmount, _MAX_PERCENTAGE_DEVIATION, 18
      );
    }
  }

  function testFuzz_QuoteBurnReflexivityRandomOracle(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3] memory latestOracleValue,
    uint256 burnAmount,
    uint256 fromToken
  )
    public
  {
    // let's first load the reserves of the protocol
    (, uint256[] memory collateralMintedStables) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
    _updateOracles(latestOracleValue);

    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
    uint256 supposedAmountOut =
      _convertDecimalTo(_getBurnOracle(burnAmount, fromToken), 18, IERC20Metadata(_collaterals[fromToken]).decimals());
    uint256 amountOut = parallelizer.quoteIn(burnAmount, address(tokenP), _collaterals[fromToken]);
    uint256 reflexiveBurnAmount = parallelizer.quoteOut(amountOut, address(tokenP), _collaterals[fromToken]);
    _assertApproxEqRelDecimalWithTolerance(supposedAmountOut, amountOut, amountOut, _MAX_PERCENTAGE_DEVIATION, 18);
    if (amountOut > _minWallet) {
      _assertApproxEqRelDecimalWithTolerance(
        burnAmount, reflexiveBurnAmount, burnAmount, _MAX_PERCENTAGE_DEVIATION, 18
      );
    }
  }

  function testFuzz_QuoteBurnExactInputReflexivityFees(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    int64 burnFee,
    uint256 burnAmount,
    uint256 fromToken
  )
    public
  {
    // let's first load the reserves of the protocol
    (, uint256[] memory collateralMintedStables) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
    burnFee = int64(bound(int256(burnFee), 0, int256(BASE_9) - (2 * int256(BASE_9)) / 1000));
    uint64[] memory xFeeBurn = new uint64[](1);
    xFeeBurn[0] = uint64(BASE_9);
    int64[] memory yFeeBurn = new int64[](1);
    yFeeBurn[0] = burnFee;
    vm.prank(governor);
    parallelizer.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

    uint256 supposedAmountOut = _convertDecimalTo(
      (burnAmount * (BASE_9 - uint64(burnFee))) / BASE_9, 18, IERC20Metadata(_collaterals[fromToken]).decimals()
    );

    if (burnFee >= int256((BASE_9 * 999) / 1000)) vm.expectRevert(Errors.InvalidSwap.selector);
    uint256 amountOut = parallelizer.quoteIn(burnAmount, address(tokenP), _collaterals[fromToken]);
    if (burnFee >= int256((BASE_9 * 999) / 1000)) vm.expectRevert(Errors.InvalidSwap.selector);
    uint256 reflexiveBurnAmount = parallelizer.quoteOut(amountOut, address(tokenP), _collaterals[fromToken]);
    if (burnFee >= int256((BASE_9 * 999) / 1000)) return;

    assertEq(supposedAmountOut, amountOut);
    if (amountOut > _minWallet) {
      _assertApproxEqRelDecimalWithTolerance(
        burnAmount, reflexiveBurnAmount, burnAmount, _MAX_PERCENTAGE_DEVIATION, 18
      );
    }
  }

  function testFuzz_QuoteBurnExactInputReflexivityOracleFees(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3] memory latestOracleValue,
    int64 burnFee,
    uint256 burnAmount,
    uint256 fromToken
  )
    public
  {
    // let's first load the reserves of the protocol
    (, uint256[] memory collateralMintedStables) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
    _updateOracles(latestOracleValue);

    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    burnAmount = bound(burnAmount, 0, collateralMintedStables[fromToken]);
    burnFee = int64(bound(int256(burnFee), 0, int256(BASE_9) - (2 * int256(BASE_9)) / 1000));
    uint64[] memory xFeeBurn = new uint64[](1);
    xFeeBurn[0] = uint64(BASE_9);
    int64[] memory yFeeBurn = new int64[](1);
    yFeeBurn[0] = burnFee;
    vm.prank(governor);
    parallelizer.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

    uint256 supposedAmountOut = _convertDecimalTo(
      _getBurnOracle((burnAmount * (BASE_9 - uint64(burnFee))), fromToken) / BASE_9,
      18,
      IERC20Metadata(_collaterals[fromToken]).decimals()
    );
    uint256 amountOut = parallelizer.quoteIn(burnAmount, address(tokenP), _collaterals[fromToken]);
    if (amountOut == 0 || burnAmount == 0) return;
    uint256 reflexiveBurnAmount = parallelizer.quoteOut(amountOut, address(tokenP), _collaterals[fromToken]);

    _assertApproxEqRelDecimalWithTolerance(
      supposedAmountOut,
      amountOut,
      amountOut,
      _MAX_PERCENTAGE_DEVIATION,
      IERC20Metadata(_collaterals[fromToken]).decimals()
    );
    if (amountOut > _minWallet) {
      _assertApproxEqRelDecimalWithTolerance(
        burnAmount, reflexiveBurnAmount, burnAmount, _MAX_PERCENTAGE_DEVIATION, 18
      );
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 PIECEWISE LINEAR FEES
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_QuoteBurnExactInputReflexivityFixPiecewiseFees(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3] memory latestOracleValue,
    int64 upperFees,
    uint256 stableAmount,
    uint256 fromToken
  )
    public
  {
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
    if (mintedStables == 0) return;
    _updateOracles(latestOracleValue);

    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
    if (stableAmount == 0) return;
    upperFees = int64(bound(int256(upperFees), 0, int256((BASE_9 * 999) / 1000) - 1));
    uint64[] memory xFeeBurn = new uint64[](3);
    xFeeBurn[0] = uint64(BASE_9);
    xFeeBurn[1] = uint64((BASE_9 * 99) / 100);
    xFeeBurn[2] = uint64(BASE_9 / 2);
    int64[] memory yFeeBurn = new int64[](3);
    yFeeBurn[0] = int64(0);
    yFeeBurn[1] = int64(0);
    yFeeBurn[2] = upperFees;
    vm.prank(governor);
    parallelizer.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

    uint256 supposedAmountOut;
    {
      uint256 copyStableAmount = stableAmount;
      uint256[] memory exposures = _getExposures(mintedStables, collateralMintedStables);
      (uint256 amountFromPrevBreakpoint, uint256 amountToNextBreakpoint, uint256 lowerIndex) =
        _amountToPrevAndNextExposure(mintedStables, fromToken, collateralMintedStables, exposures[fromToken], xFeeBurn);
      // this is to handle in easy tests
      if (lowerIndex == xFeeBurn.length - 1) return;

      if (lowerIndex == 0) {
        if (copyStableAmount <= amountToNextBreakpoint) {
          collateralMintedStables[fromToken] -= copyStableAmount;
          mintedStables -= copyStableAmount;
          // first burn segment are always constant fees
          supposedAmountOut += (copyStableAmount * (BASE_9 - uint64(yFeeBurn[0]))) / BASE_9;
          copyStableAmount = 0;
        } else {
          collateralMintedStables[fromToken] -= amountToNextBreakpoint;
          mintedStables -= amountToNextBreakpoint;
          // first burn segment are always constant fees
          supposedAmountOut += (amountToNextBreakpoint * (BASE_9 - uint64(yFeeBurn[0]))) / BASE_9;
          copyStableAmount -= amountToNextBreakpoint;

          exposures = _getExposures(mintedStables, collateralMintedStables);
          (amountFromPrevBreakpoint, amountToNextBreakpoint, lowerIndex) = _amountToPrevAndNextExposure(
            mintedStables, fromToken, collateralMintedStables, exposures[fromToken], xFeeBurn
          );
        }
      }
      if (copyStableAmount > 0) {
        if (copyStableAmount <= amountToNextBreakpoint) {
          collateralMintedStables[fromToken] -= copyStableAmount;
          int256 midFees;
          {
            int256 currentFees;
            uint256 slope = (uint256(uint64(yFeeBurn[lowerIndex + 1] - yFeeBurn[lowerIndex])) * BASE_36)
              / (amountToNextBreakpoint + amountFromPrevBreakpoint);
            currentFees = yFeeBurn[lowerIndex] + int256((slope * amountFromPrevBreakpoint) / BASE_36);
            int256 endFees =
              yFeeBurn[lowerIndex] + int256((slope * (amountFromPrevBreakpoint + copyStableAmount)) / BASE_36);
            midFees = (currentFees + endFees) / 2;
          }
          supposedAmountOut += (copyStableAmount * (BASE_9 - uint64(uint256(midFees)))) / BASE_9;
        } else {
          collateralMintedStables[fromToken] -= amountToNextBreakpoint;
          {
            int256 midFees;
            {
              uint256 slope = (uint256(uint64(yFeeBurn[lowerIndex + 1] - yFeeBurn[lowerIndex])) * BASE_36)
                / (amountToNextBreakpoint + amountFromPrevBreakpoint);
              int256 currentFees = yFeeBurn[lowerIndex] + int256((slope * amountFromPrevBreakpoint) / BASE_36);
              int256 endFees = yFeeBurn[lowerIndex + 1];
              midFees = (currentFees + endFees) / 2;
            }
            supposedAmountOut += (amountToNextBreakpoint * (BASE_9 - uint64(uint256(midFees)))) / BASE_9;
          }
          // next part is just with end fees
          supposedAmountOut += ((copyStableAmount - amountToNextBreakpoint)
              * (BASE_9 - uint64(yFeeBurn[lowerIndex + 1]))) / BASE_9;
        }
      }
    }
    supposedAmountOut = _convertDecimalTo(
      _getBurnOracle(supposedAmountOut, fromToken), 18, IERC20Metadata(_collaterals[fromToken]).decimals()
    );

    uint256 amountOut = parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]);
    if (amountOut == 0) return;
    uint256 reflexiveAmountStable = parallelizer.quoteOut(amountOut, address(tokenP), _collaterals[fromToken]);
    // TODO Anyone know how we could do without this double reflexivity?
    // The problem to compare reflexiveAmountStable and amountOut is: suppose there are very high fees
    // at the end segment BASE_9-1
    // Suppose also that when burning M stablecoins, M-N are used up until xFeeBurn[2] yielding C collateral
    // Then the remaining N yield EPS<<0 collateral --> total collateral C+EPS but with precision error
    // (collateral being with 6 decimals) --> I end up with C
    // Now quote C collateral to burn --> M-N
    uint256 reflexiveAmountOut = parallelizer.quoteIn(reflexiveAmountStable, address(tokenP), _collaterals[fromToken]);

    if (stableAmount > _minWallet) {
      _assertApproxEqRelDecimalWithTolerance(
        supposedAmountOut,
        amountOut,
        amountOut,
        // precision of 0.01%
        _MAX_PERCENTAGE_DEVIATION * 100,
        18
      );
      _assertApproxEqRelDecimalWithTolerance(
        reflexiveAmountOut, amountOut, reflexiveAmountOut, _MAX_PERCENTAGE_DEVIATION * 10, 18
      );
    }
  }

  function testFuzz_QuoteBurnReflexivityRandPiecewiseFees(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint64[10] memory xFeeBurnUnbounded,
    int64[10] memory yFeeBurnUnbounded,
    uint256 stableAmount,
    uint256 fromToken
  )
    public
  {
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    // let's first load the reserves of the protocol
    (, uint256[] memory collateralMintedStables) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
    _randomBurnFees(
      _collaterals[fromToken], xFeeBurnUnbounded, yFeeBurnUnbounded, int256(BASE_9) - (2 * int256(BASE_9)) / 1000
    );

    stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
    if (stableAmount == 0) return;

    // _logIssuedCollateral();
    try parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]) returns (uint256 amountOut) {
      if (amountOut != 0) {
        uint256 reflexiveAmountStable = parallelizer.quoteOut(amountOut, address(tokenP), _collaterals[fromToken]);
        uint256 reflexiveAmountOut =
          parallelizer.quoteIn(reflexiveAmountStable, address(tokenP), _collaterals[fromToken]);

        if (amountOut > _minWallet / 10 ** (18 - IERC20Metadata(_collaterals[fromToken]).decimals())) {
          _assertApproxEqRelDecimalWithTolerance(
            reflexiveAmountOut,
            amountOut,
            reflexiveAmountOut,
            // 0.01%
            _MAX_PERCENTAGE_DEVIATION * 100,
            IERC20Metadata(_collaterals[fromToken]).decimals()
          );
        }
      }
    } catch { }
  }

  // Oracle precision worsen reflexivity
  function testFuzz_QuoteBurnReflexivityRandOracleAndPiecewiseFees(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3] memory latestOracleValue,
    uint64[10] memory xFeeBurnUnbounded,
    int64[10] memory yFeeBurnUnbounded,
    uint256 stableAmount,
    uint256 fromToken
  )
    public
  {
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    // let's first load the reserves of the protocol
    (, uint256[] memory collateralMintedStables) = _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
    _updateOracles(latestOracleValue);
    _randomBurnFees(
      _collaterals[fromToken], xFeeBurnUnbounded, yFeeBurnUnbounded, int256(BASE_9) - (2 * int256(BASE_9)) / 1000
    );

    stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
    if (stableAmount == 0) return;

    try parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]) returns (uint256 amountOut) {
      if (amountOut != 0) {
        uint256 reflexiveAmountStable = parallelizer.quoteOut(amountOut, address(tokenP), _collaterals[fromToken]);
        uint256 reflexiveAmountOut =
          parallelizer.quoteIn(reflexiveAmountStable, address(tokenP), _collaterals[fromToken]);

        if (amountOut > (10 * _minWallet) / 10 ** (18 - IERC20Metadata(_collaterals[fromToken]).decimals())) {
          _assertApproxEqRelDecimalWithTolerance(
            reflexiveAmountOut,
            amountOut,
            reflexiveAmountOut,
            // 0.01%
            _MAX_PERCENTAGE_DEVIATION * 100,
            IERC20Metadata(_collaterals[fromToken]).decimals()
          );
        }
      }
    } catch {
      vm.expectRevert(Errors.InvalidSwap.selector);
      parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]);
    }
    // This will crash if the
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       FIREWALL
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_QuoteBurnExactInput_WithFirewall_FixPiecewiseFees(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3] memory latestOracleValue,
    uint128[6] memory userAndBurnFirewall,
    int64 upperFees,
    uint256 stableAmount,
    uint256 fromToken
  )
    public
  {
    _updateOracleFirewalls(userAndBurnFirewall);
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(charlie, sweeper, initialAmounts, transferProportion);
    if (mintedStables == 0) return;
    _updateOracles(latestOracleValue);

    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
    if (stableAmount == 0) return;
    upperFees = int64(bound(int256(upperFees), 0, int256((BASE_9 * 999) / 1000) - 1));
    uint64[] memory xFeeBurn = new uint64[](3);
    xFeeBurn[0] = uint64(BASE_9);
    xFeeBurn[1] = uint64((BASE_9 * 99) / 100);
    xFeeBurn[2] = uint64(BASE_9 / 2);
    int64[] memory yFeeBurn = new int64[](3);
    yFeeBurn[0] = int64(0);
    yFeeBurn[1] = int64(0);
    yFeeBurn[2] = upperFees;
    vm.prank(governor);
    parallelizer.setFees(_collaterals[fromToken], xFeeBurn, yFeeBurn, false);

    uint256 supposedAmountOut;
    {
      uint256 copyStableAmount = stableAmount;
      uint256[] memory exposures = _getExposures(mintedStables, collateralMintedStables);
      (uint256 amountFromPrevBreakpoint, uint256 amountToNextBreakpoint, uint256 lowerIndex) =
        _amountToPrevAndNextExposure(mintedStables, fromToken, collateralMintedStables, exposures[fromToken], xFeeBurn);
      // this is to handle in easy tests
      if (lowerIndex == xFeeBurn.length - 1) return;

      if (lowerIndex == 0) {
        if (copyStableAmount <= amountToNextBreakpoint) {
          collateralMintedStables[fromToken] -= copyStableAmount;
          mintedStables -= copyStableAmount;
          // first burn segment are always constant fees
          supposedAmountOut += (copyStableAmount * (BASE_9 - uint64(yFeeBurn[0]))) / BASE_9;
          copyStableAmount = 0;
        } else {
          collateralMintedStables[fromToken] -= amountToNextBreakpoint;
          mintedStables -= amountToNextBreakpoint;
          // first burn segment are always constant fees
          supposedAmountOut += (amountToNextBreakpoint * (BASE_9 - uint64(yFeeBurn[0]))) / BASE_9;
          copyStableAmount -= amountToNextBreakpoint;

          exposures = _getExposures(mintedStables, collateralMintedStables);
          (amountFromPrevBreakpoint, amountToNextBreakpoint, lowerIndex) = _amountToPrevAndNextExposure(
            mintedStables, fromToken, collateralMintedStables, exposures[fromToken], xFeeBurn
          );
        }
      }
      if (copyStableAmount > 0) {
        if (copyStableAmount <= amountToNextBreakpoint) {
          collateralMintedStables[fromToken] -= copyStableAmount;
          int256 midFees;
          {
            int256 currentFees;
            uint256 slope = (uint256(uint64(yFeeBurn[lowerIndex + 1] - yFeeBurn[lowerIndex])) * BASE_36)
              / (amountToNextBreakpoint + amountFromPrevBreakpoint);
            currentFees = yFeeBurn[lowerIndex] + int256((slope * amountFromPrevBreakpoint) / BASE_36);
            int256 endFees =
              yFeeBurn[lowerIndex] + int256((slope * (amountFromPrevBreakpoint + copyStableAmount)) / BASE_36);
            midFees = (currentFees + endFees) / 2;
          }
          supposedAmountOut += (copyStableAmount * (BASE_9 - uint64(uint256(midFees)))) / BASE_9;
        } else {
          collateralMintedStables[fromToken] -= amountToNextBreakpoint;
          {
            int256 midFees;
            {
              uint256 slope = (uint256(uint64(yFeeBurn[lowerIndex + 1] - yFeeBurn[lowerIndex])) * BASE_36)
                / (amountToNextBreakpoint + amountFromPrevBreakpoint);
              int256 currentFees = yFeeBurn[lowerIndex] + int256((slope * amountFromPrevBreakpoint) / BASE_36);
              int256 endFees = yFeeBurn[lowerIndex + 1];
              midFees = (currentFees + endFees) / 2;
            }
            supposedAmountOut += (amountToNextBreakpoint * (BASE_9 - uint64(uint256(midFees)))) / BASE_9;
          }
          // next part is just with end fees
          supposedAmountOut += ((copyStableAmount - amountToNextBreakpoint)
              * (BASE_9 - uint64(yFeeBurn[lowerIndex + 1]))) / BASE_9;
        }
      }
    }
    supposedAmountOut = _convertDecimalTo(
      _getBurnOracle(supposedAmountOut, fromToken), 18, IERC20Metadata(_collaterals[fromToken]).decimals()
    );
    if (supposedAmountOut > initialAmounts[fromToken]) vm.expectRevert(Errors.InvalidSwap.selector);
    uint256 amountOut = parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]);
    if (amountOut == 0 || supposedAmountOut > initialAmounts[fromToken]) return;

    if (stableAmount > _minWallet) {
      _assertApproxEqRelDecimalWithTolerance(
        supposedAmountOut,
        amountOut,
        amountOut,
        // precision of 0.01%
        _MAX_PERCENTAGE_DEVIATION * 100,
        18
      );
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   INDEPENDENT PATH
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_QuoteBurnExactInputIndependant(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256 splitProportion,
    uint256[3] memory latestOracleValue,
    uint64[10] memory xFeeBurnUnbounded,
    int64[10] memory yFeeBurnUnbounded,
    uint256 stableAmount,
    uint256 fromToken
  )
    public
  {
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(alice, address(0), initialAmounts, transferProportion);
    if (mintedStables == 0) return;
    _updateOracles(latestOracleValue);
    _randomBurnFees(
      _collaterals[fromToken],
      xFeeBurnUnbounded,
      yFeeBurnUnbounded,
      // when fees are larger than 99.9% we don't ensure the independent path
      // It won't be independant anymore because the current fees and the mid fee
      // approximation won't be correct and could be trickable. by chosing one over the other
      int256(BASE_9) - (2 * int256(BASE_9)) / 1000
    );
    stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
    if (stableAmount == 0) return;
    try parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]) returns (uint256 amountOut) {
      splitProportion = bound(splitProportion, 0, BASE_9);
      uint256 amountStableSplit1 = (stableAmount * splitProportion) / BASE_9;
      amountStableSplit1 = amountStableSplit1 == 0 ? 1 : amountStableSplit1;
      uint256 amountOutSplit1 = parallelizer.quoteIn(amountStableSplit1, address(tokenP), _collaterals[fromToken]);
      // do the swap to update the system
      _burnExactInput(alice, _collaterals[fromToken], amountStableSplit1, amountOutSplit1);

      try parallelizer.quoteIn(stableAmount - amountStableSplit1, address(tokenP), _collaterals[fromToken]) returns (
        uint256 amountOutSplit2
      ) {
        if (stableAmount > _minWallet) {
          _assertApproxEqRelDecimalWithTolerance(
            amountOutSplit1 + amountOutSplit2,
            amountOut,
            amountOut,
            // 0.01%
            _MAX_PERCENTAGE_DEVIATION * 100,
            18
          );
        }
      } catch { }
    } catch {
      vm.expectRevert(Errors.InvalidSwap.selector);
      parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]);
    }
  }

  function testFuzz_QuoteBurnExactOutputIndependant(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256 splitProportion,
    uint256[3] memory latestOracleValue,
    uint64[10] memory xFeeBurnUnbounded,
    int64[10] memory yFeeBurnUnbounded,
    uint256 amountOut,
    uint256 fromToken
  )
    public
  {
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    // let's first load the reserves of the protocol
    (uint256 mintedStables,) = _loadReserves(alice, address(0), initialAmounts, transferProportion);
    if (mintedStables == 0) return;
    _updateOracles(latestOracleValue);
    _randomBurnFees(
      _collaterals[fromToken], xFeeBurnUnbounded, yFeeBurnUnbounded, int256(BASE_9) - (2 * int256(BASE_9)) / 1000
    );
    amountOut = bound(amountOut, 0, IERC20(_collaterals[fromToken]).balanceOf(address(parallelizer)));
    if (amountOut == 0) return;

    uint256 amountStable = parallelizer.quoteOut(amountOut, address(tokenP), _collaterals[fromToken]);
    splitProportion = bound(splitProportion, 0, BASE_9);
    uint256 amountOutSplit1 = (amountOut * splitProportion) / BASE_9;
    amountOutSplit1 = amountOutSplit1 == 0 ? 1 : amountOutSplit1;
    uint256 amountStableSplit1 = parallelizer.quoteOut(amountOutSplit1, address(tokenP), _collaterals[fromToken]);
    // do the swap to update the system
    bool notReverted = _burnExactOutput(alice, _collaterals[fromToken], amountOutSplit1, amountStableSplit1);
    if (notReverted) return;
    uint256 amountStableSplit2 =
      parallelizer.quoteOut(amountOut - amountOutSplit1, address(tokenP), _collaterals[fromToken]);
    if (amountStable > _minWallet) {
      _assertApproxEqRelDecimalWithTolerance(
        amountStableSplit1 + amountStableSplit2,
        amountStable,
        amountStable,
        // 0.01%
        _MAX_PERCENTAGE_DEVIATION * 100,
        18
      );
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         BURN
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_BurnExactInput(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3] memory latestOracleValue,
    uint64[10] memory xFeeBurnUnbounded,
    int64[10] memory yFeeBurnUnbounded,
    uint256 stableAmount,
    uint256 fromToken
  )
    public
  {
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(alice, address(0), initialAmounts, transferProportion);
    if (mintedStables == 0) return;
    _updateOracles(latestOracleValue);
    _randomBurnFees(
      _collaterals[fromToken], xFeeBurnUnbounded, yFeeBurnUnbounded, int256(BASE_9) - (2 * int256(BASE_9)) / 1000
    );
    stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
    if (stableAmount == 0) return;
    // `quoteIn` does not model the CannotBurnAllStableIssued guard; skip the boundary case so the
    // follow-on swapExactInput (which is not wrapped by the try/catch below) stays successful.
    if (stableAmount >= mintedStables) return;

    uint256 prevBalanceStable = tokenP.balanceOf(alice);
    uint256 prevParallelizerCollat = IERC20(_collaterals[fromToken]).balanceOf(address(parallelizer));

    try parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]) returns (uint256 amountOut) {
      bool burnMoreThanHad = _burnExactInput(alice, _collaterals[fromToken], stableAmount, amountOut);

      uint256 balanceStable = tokenP.balanceOf(alice);
      if (amountOut == 0 || stableAmount == 0) assertEq(balanceStable, prevBalanceStable);
      else assertEq(balanceStable, prevBalanceStable - stableAmount);
      assertEq(IERC20(_collaterals[fromToken]).balanceOf(alice), amountOut);
      assertEq(
        IERC20(_collaterals[fromToken]).balanceOf(address(parallelizer)),
        burnMoreThanHad ? 0 : prevParallelizerCollat - amountOut
      );

      (uint256 newStableAmountCollat, uint256 newStableAmount) =
        parallelizer.getIssuedByCollateral(_collaterals[fromToken]);

      if (amountOut == 0 || stableAmount == 0) {
        assertApproxEqAbs(newStableAmountCollat, collateralMintedStables[fromToken], 1 wei);
        assertApproxEqAbs(newStableAmount, mintedStables, 1 wei);
      } else {
        assertApproxEqAbs(newStableAmountCollat, collateralMintedStables[fromToken] - stableAmount, 1 wei);
        assertApproxEqAbs(newStableAmount, mintedStables - stableAmount, 1 wei);
      }
    } catch { }
  }

  function testFuzz_BurnExactOutput(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3] memory latestOracleValue,
    uint64[10] memory xFeeBurnUnbounded,
    int64[10] memory yFeeBurnUnbounded,
    uint256 amountOut,
    uint256 fromToken
  )
    public
  {
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(alice, address(0), initialAmounts, transferProportion);
    if (mintedStables == 0) return;
    _updateOracles(latestOracleValue);
    _randomBurnFees(
      _collaterals[fromToken], xFeeBurnUnbounded, yFeeBurnUnbounded, int256(BASE_9) - (2 * int256(BASE_9)) / 1000
    );
    amountOut = bound(amountOut, 0, IERC20(_collaterals[fromToken]).balanceOf(address(parallelizer)));
    if (amountOut == 0) return;

    uint256 prevBalanceStable = tokenP.balanceOf(alice);

    uint256 stableAmount = parallelizer.quoteOut(amountOut, address(tokenP), _collaterals[fromToken]);
    bool notReverted = _burnExactOutput(alice, _collaterals[fromToken], amountOut, stableAmount);
    if (notReverted) return;

    uint256 balanceStable = tokenP.balanceOf(alice);
    uint256 prevParallelizerCollat = IERC20(_collaterals[fromToken]).balanceOf(address(parallelizer));

    assertEq(balanceStable, prevBalanceStable - stableAmount);
    assertEq(IERC20(_collaterals[fromToken]).balanceOf(alice), amountOut);
    assertEq(IERC20(_collaterals[fromToken]).balanceOf(address(parallelizer)), prevParallelizerCollat - amountOut);

    (uint256 newStableAmountCollat, uint256 newStableAmount) =
      parallelizer.getIssuedByCollateral(_collaterals[fromToken]);

    assertApproxEqAbs(newStableAmountCollat, collateralMintedStables[fromToken] - stableAmount, 1 wei);
    assertApproxEqAbs(newStableAmount, mintedStables - stableAmount, 1 wei);
  }

  function testFuzz_Burn_RevertWhen_BurningAllStableIssued(
    uint256[3] memory initialAmounts,
    uint256[3] memory latestOracleValue,
    uint256 stableAmount
  )
    public
  {
    _setMintFeesForNegativeBurnFees(0);
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(alice, address(0), initialAmounts, 0);
    _setZeroBurnFees(_collaterals);

    if (mintedStables == 0) return;

    _updateOracles(latestOracleValue);
    vm.startPrank(alice);
    IERC20(address(tokenP)).approve(address(parallelizer), mintedStables);

    for (uint8 i; i < _collaterals.length; i++) {
      uint256 stableIssued = parallelizer.getTotalIssued();
      uint256 amountOut = parallelizer.quoteIn(collateralMintedStables[i], address(tokenP), _collaterals[i]);
      if (amountOut == 0) continue;
      bool expectRevert = collateralMintedStables[i] >= stableIssued;
      if (expectRevert) {
        vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
      }
      parallelizer.swapExactInput(
        collateralMintedStables[i], 0, address(tokenP), _collaterals[i], alice, block.timestamp * 2
      );
      if (expectRevert) break;
    }
  }

  function testFuzz_Burn_RevertWhen_BurningAllStableIssuedWithWhitelist(
    uint256[3] memory initialAmounts,
    uint256[3] memory latestOracleValue,
    uint256 stableAmount
  )
    public
  {
    _setMintFeesForNegativeBurnFees(0);
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(alice, address(0), initialAmounts, 0);
    _setZeroBurnFees(_collaterals);

    if (mintedStables == 0) return;

    // Enable whitelist on the first collateral and whitelist alice
    bytes memory emptyData;
    bytes memory whitelistData = abi.encode(WhitelistType.BACKED, emptyData);
    hoax(governor);
    parallelizer.setWhitelistStatus(_collaterals[0], 1, whitelistData);
    hoax(guardian);
    parallelizer.toggleWhitelist(WhitelistType.BACKED, alice);

    _updateOracles(latestOracleValue);
    vm.startPrank(alice);
    IERC20(address(tokenP)).approve(address(parallelizer), mintedStables);

    for (uint8 i; i < _collaterals.length; i++) {
      uint256 stableIssued = parallelizer.getTotalIssued();
      uint256 amountOut = parallelizer.quoteIn(collateralMintedStables[i], address(tokenP), _collaterals[i]);
      if (amountOut == 0) continue;
      bool expectRevert = collateralMintedStables[i] >= stableIssued;
      if (expectRevert) {
        vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
      }
      parallelizer.swapExactInput(
        collateralMintedStables[i], 0, address(tokenP), _collaterals[i], alice, block.timestamp * 2
      );
      if (expectRevert) break;
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   BURN WITH MANAGER
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
  function testFuzz_BurnMaxAvailableManager(uint256[3] memory initialAmounts, uint256 stableAmount) public {
    // create a manager to be above the maxAvailable
    MockManager manager = new MockManager(_collaterals[0]);
    IERC20[] memory subCollaterals = new IERC20[](1);
    AggregatorV3Interface[] memory oracles = new AggregatorV3Interface[](1);
    subCollaterals[0] = IERC20(_collaterals[0]);
    uint8[] memory decimals = new uint8[](1);
    decimals[0] = IERC20Metadata(_collaterals[0]).decimals();
    uint32[] memory stalePeriods = new uint32[](1);
    uint8[] memory oracleIsMultiplied = new uint8[](1);
    uint8[] memory chainlinkDecimals = new uint8[](1);
    oracles[0] = oracleA;
    stalePeriods[0] = 365 days;
    oracleIsMultiplied[0] = 1;
    chainlinkDecimals[0] = 8;

    manager.setSubCollaterals(
      subCollaterals, abi.encode(decimals, oracles, stalePeriods, oracleIsMultiplied, chainlinkDecimals)
    );
    ManagerStorage memory managerData =
      ManagerStorage(subCollaterals, abi.encode(ManagerType.EXTERNAL, abi.encode(IManager(address(manager)))));
    vm.prank(governor);
    parallelizer.setCollateralManager(_collaterals[0], true, managerData);
    // done

    // let's first load the reserves of the protocol
    (, uint256[] memory collateralMintedStables) = _loadReserves(alice, address(0), initialAmounts, 0);
    if (collateralMintedStables[0] < BASE_18) return;

    // artificially make the manager maxAvailable to 0
    deal(_collaterals[0], address(manager), 0);

    stableAmount = bound(stableAmount, BASE_18, collateralMintedStables[0]);
    if (stableAmount == 0) return;

    vm.expectRevert(Errors.InvalidSwap.selector);
    parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[0]);
    vm.startPrank(alice);
    vm.expectRevert();
    parallelizer.swapExactInput(stableAmount, 0, address(tokenP), _collaterals[0], alice, 1 hours);
    vm.stopPrank();
  }

  function testFuzz_Burn_RevertWhen_BurningAllStableIssuedWithManager(
    uint256[3] memory initialAmounts,
    uint256[3] memory latestOracleValue,
    uint256 stableAmount
  )
    public
  {
    // create a manager for the first collateral
    MockManager manager = new MockManager(_collaterals[0]);
    IERC20[] memory subCollaterals = new IERC20[](1);
    AggregatorV3Interface[] memory oracles = new AggregatorV3Interface[](1);
    subCollaterals[0] = IERC20(_collaterals[0]);
    uint8[] memory decimals = new uint8[](1);
    decimals[0] = IERC20Metadata(_collaterals[0]).decimals();
    uint32[] memory stalePeriods = new uint32[](1);
    uint8[] memory oracleIsMultiplied = new uint8[](1);
    uint8[] memory chainlinkDecimals = new uint8[](1);
    oracles[0] = oracleA;
    stalePeriods[0] = 365 days;
    oracleIsMultiplied[0] = 1;
    chainlinkDecimals[0] = 8;

    manager.setSubCollaterals(
      subCollaterals, abi.encode(decimals, oracles, stalePeriods, oracleIsMultiplied, chainlinkDecimals)
    );
    ManagerStorage memory managerData =
      ManagerStorage(subCollaterals, abi.encode(ManagerType.EXTERNAL, abi.encode(IManager(address(manager)))));
    vm.prank(governor);
    parallelizer.setCollateralManager(_collaterals[0], true, managerData);

    _setMintFeesForNegativeBurnFees(0);
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(alice, address(0), initialAmounts, 0);
    _setZeroBurnFees(_collaterals);

    if (mintedStables == 0) return;

    _updateOracles(latestOracleValue);
    vm.startPrank(alice);
    IERC20(address(tokenP)).approve(address(parallelizer), mintedStables);

    for (uint8 i; i < _collaterals.length; i++) {
      uint256 stableIssued = parallelizer.getTotalIssued();
      uint256 amountOut = parallelizer.quoteIn(collateralMintedStables[i], address(tokenP), _collaterals[i]);
      if (amountOut == 0) continue;
      bool expectRevert = collateralMintedStables[i] >= stableIssued;
      if (expectRevert) {
        vm.expectRevert(Errors.CannotBurnAllStableIssued.selector);
      }
      parallelizer.swapExactInput(
        collateralMintedStables[i], 0, address(tokenP), _collaterals[i], alice, block.timestamp * 2
      );
      if (expectRevert) break;
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                  BURN WITH WHITELIST
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_RevertWhen_Whitelist(
    uint256[3] memory initialAmounts,
    uint256[3] memory latestOracleValue,
    uint256 stableAmount,
    uint256 fromToken
  )
    public
  {
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(alice, address(0), initialAmounts, 0);
    if (mintedStables == 0) return;
    _updateOracles(latestOracleValue);

    stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
    uint256 burnAmount = IERC20(_collaterals[fromToken]).balanceOf(address(parallelizer)) / 2;

    uint256 amountOut = parallelizer.quoteIn(burnAmount, address(tokenP), _collaterals[fromToken]);
    uint256 amountIn = parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]);

    bytes memory emptyData;
    bytes memory whitelistData = abi.encode(WhitelistType.BACKED, emptyData);
    hoax(governor);
    parallelizer.setWhitelistStatus(_collaterals[fromToken], 1, whitelistData);

    assertEq(amountOut, parallelizer.quoteIn(burnAmount, address(tokenP), _collaterals[fromToken]));
    assertEq(amountIn, parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]));

    if (stableAmount == 0 || amountIn == 0 || amountOut == 0 || burnAmount == 0) return;

    vm.expectRevert(Errors.NotWhitelisted.selector);
    parallelizer.swapExactInput(stableAmount, 0, address(tokenP), _collaterals[fromToken], address(alice), 1 hours);

    vm.expectRevert(Errors.NotWhitelisted.selector);
    parallelizer.swapExactOutput(
      burnAmount, type(uint256).max, address(tokenP), _collaterals[fromToken], address(alice), 1 hours
    );
  }

  function testFuzz_BurnExactInputAndWhitelist(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3] memory latestOracleValue,
    uint64[10] memory xFeeBurnUnbounded,
    int64[10] memory yFeeBurnUnbounded,
    uint256 stableAmount,
    uint256 fromToken
  )
    public
  {
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(alice, address(0), initialAmounts, transferProportion);
    if (mintedStables == 0) return;
    _updateOracles(latestOracleValue);
    _randomBurnFees(
      _collaterals[fromToken], xFeeBurnUnbounded, yFeeBurnUnbounded, int256(BASE_9) - (2 * int256(BASE_9)) / 1000
    );
    stableAmount = bound(stableAmount, 0, collateralMintedStables[fromToken]);
    if (stableAmount == 0) return;
    // See rationale in testFuzz_BurnExactInput.
    if (stableAmount >= mintedStables) return;

    uint256 prevBalanceStable = tokenP.balanceOf(alice);
    uint256 prevParallelizerCollat = IERC20(_collaterals[fromToken]).balanceOf(address(parallelizer));

    bytes memory emptyData;
    bytes memory whitelistData = abi.encode(WhitelistType.BACKED, emptyData);
    hoax(governor);
    parallelizer.setWhitelistStatus(_collaterals[fromToken], 1, whitelistData);

    hoax(guardian);
    parallelizer.toggleWhitelist(WhitelistType.BACKED, alice);

    try parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]) returns (uint256 amountOut) {
      bool burnMoreThanHad = _burnExactInput(alice, _collaterals[fromToken], stableAmount, amountOut);

      uint256 balanceStable = tokenP.balanceOf(alice);
      if (amountOut == 0 || stableAmount == 0) assertEq(balanceStable, prevBalanceStable);
      else assertEq(balanceStable, prevBalanceStable - stableAmount);
      assertEq(IERC20(_collaterals[fromToken]).balanceOf(alice), amountOut);
      assertEq(
        IERC20(_collaterals[fromToken]).balanceOf(address(parallelizer)),
        burnMoreThanHad ? 0 : prevParallelizerCollat - amountOut
      );

      (uint256 newStableAmountCollat, uint256 newStableAmount) =
        parallelizer.getIssuedByCollateral(_collaterals[fromToken]);

      if (amountOut == 0 || stableAmount == 0) {
        assertApproxEqAbs(newStableAmountCollat, collateralMintedStables[fromToken], 1 wei);
        assertApproxEqAbs(newStableAmount, mintedStables, 1 wei);
      } else {
        assertApproxEqAbs(newStableAmountCollat, collateralMintedStables[fromToken] - stableAmount, 1 wei);
        assertApproxEqAbs(newStableAmount, mintedStables - stableAmount, 1 wei);
      }
    } catch { }
  }

  function testFuzz_BurnExactOutputAndWhitelist(
    uint256[3] memory initialAmounts,
    uint256 transferProportion,
    uint256[3] memory latestOracleValue,
    uint64[10] memory xFeeBurnUnbounded,
    int64[10] memory yFeeBurnUnbounded,
    uint256 amountOut,
    uint256 fromToken
  )
    public
  {
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    // let's first load the reserves of the protocol
    (uint256 mintedStables, uint256[] memory collateralMintedStables) =
      _loadReserves(alice, address(0), initialAmounts, transferProportion);
    if (mintedStables == 0) return;
    _updateOracles(latestOracleValue);
    _randomBurnFees(
      _collaterals[fromToken], xFeeBurnUnbounded, yFeeBurnUnbounded, int256(BASE_9) - (2 * int256(BASE_9)) / 1000
    );
    amountOut = bound(amountOut, 0, IERC20(_collaterals[fromToken]).balanceOf(address(parallelizer)));
    if (amountOut == 0) return;

    uint256 prevBalanceStable = tokenP.balanceOf(alice);

    bytes memory emptyData;
    bytes memory whitelistData = abi.encode(WhitelistType.BACKED, emptyData);
    hoax(governor);
    parallelizer.setWhitelistStatus(_collaterals[fromToken], 1, whitelistData);

    hoax(guardian);
    parallelizer.toggleWhitelist(WhitelistType.BACKED, alice);

    uint256 stableAmount = parallelizer.quoteOut(amountOut, address(tokenP), _collaterals[fromToken]);
    bool notReverted = _burnExactOutput(alice, _collaterals[fromToken], amountOut, stableAmount);
    if (notReverted) return;

    uint256 balanceStable = tokenP.balanceOf(alice);
    uint256 prevParallelizerCollat = IERC20(_collaterals[fromToken]).balanceOf(address(parallelizer));

    assertEq(balanceStable, prevBalanceStable - stableAmount);
    assertEq(IERC20(_collaterals[fromToken]).balanceOf(alice), amountOut);
    assertEq(IERC20(_collaterals[fromToken]).balanceOf(address(parallelizer)), prevParallelizerCollat - amountOut);

    (uint256 newStableAmountCollat, uint256 newStableAmount) =
      parallelizer.getIssuedByCollateral(_collaterals[fromToken]);

    assertApproxEqAbs(newStableAmountCollat, collateralMintedStables[fromToken] - stableAmount, 1 wei);
    assertApproxEqAbs(newStableAmount, mintedStables - stableAmount, 1 wei);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _loadReserves(
    address owner,
    address receiver,
    uint256[3] memory initialAmounts,
    uint256 transferProportion
  )
    internal
    returns (uint256 mintedStables, uint256[] memory collateralMintedStables)
  {
    collateralMintedStables = new uint256[](_collaterals.length);

    vm.startPrank(owner);
    for (uint256 i; i < _collaterals.length; i++) {
      initialAmounts[i] = bound(initialAmounts[i], 0, _maxTokenAmount[i]);
      deal(_collaterals[i], owner, initialAmounts[i]);
      IERC20(_collaterals[i]).approve(address(parallelizer), initialAmounts[i]);

      collateralMintedStables[i] =
        parallelizer.swapExactInput(initialAmounts[i], 0, _collaterals[i], address(tokenP), owner, 1 hours);
      mintedStables += collateralMintedStables[i];
    }

    // Send a proportion of these to another account user just to complexify the case
    transferProportion = bound(transferProportion, 0, BASE_9);
    if (receiver != address(0)) tokenP.transfer(receiver, (mintedStables * transferProportion) / BASE_9);
    vm.stopPrank();

    _setMintFeesForNegativeBurnFees(-_minBurnFee);
  }

  function _emptyReserves(
    address owner,
    uint256[3] memory amounts
  )
    internal
    returns (bool succeed, uint256 burntStables, uint256[] memory collateralBurntStables)
  {
    collateralBurntStables = new uint256[](_collaterals.length);
    succeed = true;

    vm.startPrank(owner);
    for (uint256 i; i < _collaterals.length; i++) {
      amounts[i] = bound(amounts[i], 0, IERC20(_collaterals[i]).balanceOf(address(parallelizer)));
      (uint256 maxAmount,) = parallelizer.getIssuedByCollateral(_collaterals[i]);
      uint256 estimatedStable = parallelizer.quoteOut(amounts[i], address(tokenP), _collaterals[i]);
      uint256 balanceStableOwner = tokenP.balanceOf(owner);
      if (estimatedStable > maxAmount && estimatedStable > balanceStableOwner) vm.expectRevert();
      else if (estimatedStable > balanceStableOwner) vm.expectRevert("ERC20: burn amount exceeds balance");
      else if (estimatedStable > maxAmount) vm.expectRevert();
      collateralBurntStables[i] =
        parallelizer.swapExactOutput(amounts[i], estimatedStable, address(tokenP), _collaterals[i], owner, 1 hours);
      if (estimatedStable > balanceStableOwner || estimatedStable > maxAmount) {
        return (false, burntStables, collateralBurntStables);
      }
      burntStables += collateralBurntStables[i];
    }
    vm.stopPrank();
  }

  function _setMintFeesForNegativeBurnFees(int64 smallestFee) internal {
    // set mint Fees to be consistent with the min fee on Burn
    uint64[] memory xFee = new uint64[](1);
    xFee[0] = uint64(0);
    int64[] memory yFee = new int64[](1);
    yFee[0] = smallestFee;
    vm.startPrank(guardian);
    parallelizer.setFees(address(eurA), xFee, yFee, true);
    parallelizer.setFees(address(eurB), xFee, yFee, true);
    parallelizer.setFees(address(eurY), xFee, yFee, true);
    vm.stopPrank();
  }

  function _setZeroBurnFees(address[] memory collaterals) internal {
    vm.startPrank(guardian);
    uint64[] memory xBurnFee = new uint64[](1);
    xBurnFee[0] = uint64(BASE_9);
    int64[] memory yBurnFee = new int64[](1);
    yBurnFee[0] = int64(0);
    for (uint256 i; i < collaterals.length; i++) {
      parallelizer.setFees(collaterals[i], xBurnFee, yBurnFee, false);
    }
    vm.stopPrank();
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                          NORMALIZED STABLES GUARD
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
  function test_BurnPath_CannotDriveNormalizedStablesToZero() public {
    uint256 mintAmount = 100 * BASE_6;
    deal(address(eurA), alice, mintAmount);
    vm.startPrank(alice);
    eurA.approve(address(parallelizer), mintAmount);
    uint256 minted =
      parallelizer.swapExactInput(mintAmount, 0, address(eurA), address(tokenP), alice, block.timestamp + 1 hours);
    vm.stopPrank();

    vm.startPrank(alice);
    vm.expectRevert(CannotBurnAllStableIssued.selector);
    parallelizer.swapExactInput(minted, 0, address(tokenP), address(eurA), alice, block.timestamp + 1 hours);
    vm.stopPrank();

    assertGt(parallelizer.getTotalIssued(), 0, "normalizedStables must not be zero");
  }

  function _getExposures(
    uint256 mintedStables,
    uint256[] memory collateralMintedStables
  )
    internal
    view
    returns (uint256[] memory exposures)
  {
    exposures = new uint256[](_collaterals.length);
    for (uint256 i; i < _collaterals.length; i++) {
      exposures[i] = (collateralMintedStables[i] * BASE_9) / mintedStables;
    }
  }

  function _amountToPrevAndNextExposure(
    uint256 mintedStables,
    uint256 indexCollat,
    uint256[] memory collateralMintedStables,
    uint256 exposure,
    uint64[] memory xThres
  )
    internal
    pure
    returns (uint256 amountToPrevBreakpoint, uint256 amountToNextBreakpoint, uint256 indexExposure)
  {
    if (exposure <= xThres[xThres.length - 1]) return (0, 0, xThres.length - 1);
    while (exposure < xThres[indexExposure]) indexExposure++;
    if (exposure > xThres[indexExposure]) indexExposure--;
    amountToNextBreakpoint = (BASE_9
        * collateralMintedStables[indexCollat]
        - xThres[indexExposure + 1]
        * mintedStables) / (BASE_9 - xThres[indexExposure + 1]);
    // if we are on the first segment amountToPrevBreakpoint is infinite
    // so we need to set constant fees for this segment
    amountToPrevBreakpoint = indexExposure == 0
      ? type(uint256).max
      : (xThres[indexExposure] * mintedStables - BASE_9 * collateralMintedStables[indexCollat])
        / (BASE_9 - xThres[indexExposure]);
  }

  function _updateOracles(uint256[3] memory latestOracleValue) internal {
    for (uint256 i; i < _collaterals.length; i++) {
      latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue * 10, BASE_18 / 100);
      MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
    }
  }

  function _randomBurnFees(
    address collateral,
    uint64[10] memory xFeeBurnUnbounded,
    int64[10] memory yFeeBurnUnbounded,
    int256 maxFee
  )
    internal
    returns (uint64[] memory xFeeBurn, int64[] memory yFeeBurn)
  {
    (xFeeBurn, yFeeBurn) = _generateCurves(xFeeBurnUnbounded, yFeeBurnUnbounded, false, false, _minBurnFee, maxFee);
    vm.prank(governor);
    console.log("collateral TEST");
    parallelizer.setFees(collateral, xFeeBurn, yFeeBurn, false);
  }

  function _sweepBalances(address owner, address[] memory tokens) internal {
    vm.startPrank(owner);
    for (uint256 i; i < tokens.length; ++i) {
      IERC20(tokens[i]).transfer(sweeper, IERC20(tokens[i]).balanceOf(owner));
    }
    vm.stopPrank();
  }

  // function _logIssuedCollateral() internal view {
  //     for (uint256 i; i < _collaterals.length; i++) {
  //         (uint256 collateralIssued, uint256 total) = parallelizer.getIssuedByCollateral(_collaterals[i]);
  //         console.log("collateralIssued ", i, collateralIssued);
  //     }
  // }

  function _getBurnOracle(uint256 amount, uint256 fromToken) internal view returns (uint256) {
    uint256 minDeviation = BASE_8;
    uint256 oracleValue;
    for (uint256 i; i < _oracles.length; i++) {
      uint128 userFirewall;
      uint128 burnRatioDeviation;
      {
        (,,,, bytes memory hyperparameters) = parallelizer.getOracle(address(_collaterals[i]));
        (userFirewall, burnRatioDeviation) = abi.decode(hyperparameters, (uint128, uint128));
      }
      (, int256 oracleValueTmp,,,) = _oracles[i].latestRoundData();
      if (
        BASE_8 * (BASE_18 - userFirewall) > uint256(oracleValueTmp) * BASE_18
          && uint256(oracleValueTmp) * BASE_18 < BASE_8 * (BASE_18 - burnRatioDeviation)
          && minDeviation > uint256(oracleValueTmp)
      ) minDeviation = uint256(oracleValueTmp);
      if (i == fromToken) {
        oracleValue = uint256(oracleValueTmp);
        if (
          // We are in the user deviation tolerance
          // Or we are in the burn deviation tolerance
          (BASE_8 * (BASE_18 - userFirewall) < oracleValue * BASE_18
              && oracleValue * BASE_18 < BASE_8 * (BASE_18 + userFirewall))
            || (BASE_8 * (BASE_18 - burnRatioDeviation) <= oracleValue * BASE_18 && oracleValue <= BASE_8)
        ) oracleValue = BASE_8;
      }
    }
    return (amount * minDeviation) / oracleValue;
  }

  function _updateOracleFirewalls(uint128[6] memory userAndBurnFirewall) internal returns (uint128[6] memory) {
    uint128[] memory userFirewall = new uint128[](3);
    uint128[] memory burnFirewall = new uint128[](3);
    for (uint256 i; i < _collaterals.length; i++) {
      userFirewall[i] = uint128(bound(userAndBurnFirewall[i], 0, BASE_18));
      burnFirewall[i] = uint128(bound(userAndBurnFirewall[i + 3], userFirewall[i], BASE_18));
      userAndBurnFirewall[i] = userFirewall[i];
      userAndBurnFirewall[i + 3] = burnFirewall[i];
    }

    vm.startPrank(governor);
    for (uint256 i; i < _collaterals.length; i++) {
      (
        Storage.OracleReadType readType,
        Storage.OracleReadType targetType,
        bytes memory data,
        bytes memory targetData,
      ) = parallelizer.getOracle(address(_collaterals[i]));
      parallelizer.setOracle(
        _collaterals[i],
        abi.encode(
          readType, targetType, data, targetData, abi.encode(uint128(userFirewall[i]), uint128(burnFirewall[i]))
        )
      );
    }
    vm.stopPrank();
    return userAndBurnFirewall;
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ACTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _burnExactInput(
    address owner,
    address tokenOut,
    uint256 amountStable,
    uint256 estimatedAmountOut
  )
    internal
    returns (bool burnMoreThanHad)
  {
    // we need to increase the balance because fees are negative and we need to transfer
    // more than what we received with the mint
    if (IERC20(tokenOut).balanceOf(address(parallelizer)) < estimatedAmountOut) {
      deal(tokenOut, address(parallelizer), estimatedAmountOut);
      burnMoreThanHad = true;
    }
    vm.startPrank(owner);
    parallelizer.swapExactInput(amountStable, estimatedAmountOut, address(tokenP), tokenOut, owner, 1 hours);
    vm.stopPrank();
  }

  function _burnExactOutput(
    address owner,
    address tokenOut,
    uint256 amountOut,
    uint256 estimatedStable
  )
    internal
    returns (bool)
  {
    // _logIssuedCollateral();
    vm.startPrank(owner);
    (uint256 maxAmount,) = parallelizer.getIssuedByCollateral(tokenOut);
    uint256 balanceStableOwner = tokenP.balanceOf(owner);
    if (estimatedStable > maxAmount) vm.expectRevert();
    else if (estimatedStable > balanceStableOwner) vm.expectRevert("ERC20: burn amount exceeds balance");
    parallelizer.swapExactOutput(amountOut, estimatedStable, address(tokenP), tokenOut, owner, 1 hours);
    if (amountOut > maxAmount) return false;
    vm.stopPrank();
    return true;
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    EIP-3009 SWAP WITH AUTHORIZATION
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function test_SwapExactInputWithAuthorization_Mint() public {
    uint256 mintAmount = 100 * BASE_6;
    deal(address(eurA), alice, mintAmount);

    uint256 deadline = block.timestamp + 1 hours;
    bytes memory authData = _buildSwapExactInputAuth(
      1, address(eurA), address(tokenP), alice, mintAmount, 0, alice, deadline, bytes32("mint1")
    );

    // bob relays alice's signed authorization
    vm.prank(bob);
    uint256 amountOut = parallelizer.swapExactInputWithAuthorization(
      mintAmount, 0, address(eurA), address(tokenP), alice, deadline, authData
    );

    assertGt(amountOut, 0);
    assertGt(tokenP.balanceOf(alice), 0);
    assertEq(IERC20(address(eurA)).balanceOf(alice), 0);
  }

  /// @notice Regression: an authorization signed for `to = alice` cannot be replayed with `to = bob`.
  function test_SwapExactInputWithAuthorization_FrontrunRejected() public {
    uint256 mintAmount = 100 * BASE_6;
    deal(address(eurA), alice, mintAmount);

    uint256 deadline = block.timestamp + 1 hours;
    bytes memory aliceAuth = _buildSwapExactInputAuth(
      1, address(eurA), address(tokenP), alice, mintAmount, 0, alice, deadline, bytes32("frontrun1")
    );

    vm.prank(bob);
    vm.expectRevert(bytes("invalid signature"));
    parallelizer.swapExactInputWithAuthorization(
      mintAmount, 0, address(eurA), address(tokenP), bob, deadline, aliceAuth
    );
  }

  function test_SwapExactOutputWithAuthorization_Mint() public {
    uint256 maxIn = 200 * BASE_6;
    deal(address(eurA), alice, maxIn);

    uint256 deadline = block.timestamp + 1 hours;
    bytes memory authData = _buildSwapExactOutputAuth(
      1, address(eurA), address(tokenP), alice, 50 * BASE_18, maxIn, alice, deadline, bytes32("mint2")
    );

    vm.prank(bob);
    uint256 amountIn = parallelizer.swapExactOutputWithAuthorization(
      50 * BASE_18, maxIn, address(eurA), address(tokenP), alice, deadline, authData
    );

    assertLe(amountIn, maxIn);
    assertGt(tokenP.balanceOf(alice), 0);
    assertEq(IERC20(address(eurA)).balanceOf(alice), maxIn - amountIn);
  }

  function test_SwapExactInputWithAuthorization_Burn() public {
    _mintExactInput(alice, address(eurA), 100 * BASE_6, 0);
    uint256 tokenPBal = tokenP.balanceOf(alice);
    uint256 burnAmount = tokenPBal / 2;

    uint256 deadline = block.timestamp + 1 hours;
    bytes memory authData = _buildSwapExactInputAuth(
      1, address(tokenP), address(eurA), alice, burnAmount, 0, alice, deadline, bytes32("burn1")
    );

    vm.prank(bob);
    uint256 amountOut = parallelizer.swapExactInputWithAuthorization(
      burnAmount, 0, address(tokenP), address(eurA), alice, deadline, authData
    );

    assertGt(amountOut, 0);
    assertEq(tokenP.balanceOf(alice), tokenPBal - burnAmount);
  }

  function test_RevertWhen_AuthorizationValueMismatch() public {
    uint256 mintAmount = 100 * BASE_6;
    deal(address(eurA), alice, mintAmount);

    uint256 deadline = block.timestamp + 1 hours;
    bytes memory authData = _buildSwapExactInputAuth(
      1, address(eurA), address(tokenP), alice, mintAmount / 2, 0, alice, deadline, bytes32("bad1")
    );

    vm.prank(bob);
    vm.expectRevert(InvalidSwap.selector);
    parallelizer.swapExactInputWithAuthorization(
      mintAmount, 0, address(eurA), address(tokenP), alice, deadline, authData
    );
  }

  function test_RevertWhen_AuthorizationReusedNonce() public {
    uint256 mintAmount = 50 * BASE_6;
    deal(address(eurA), alice, mintAmount * 2);
    bytes32 userSalt = bytes32("reuse1");
    uint256 deadline = block.timestamp + 1 hours;

    bytes memory authData1 =
      _buildSwapExactInputAuth(1, address(eurA), address(tokenP), alice, mintAmount, 0, alice, deadline, userSalt);

    vm.prank(bob);
    parallelizer.swapExactInputWithAuthorization(
      mintAmount, 0, address(eurA), address(tokenP), alice, deadline, authData1
    );

    bytes memory authData2 =
      _buildSwapExactInputAuth(1, address(eurA), address(tokenP), alice, mintAmount, 0, alice, deadline, userSalt);

    vm.prank(bob);
    vm.expectRevert();
    parallelizer.swapExactInputWithAuthorization(
      mintAmount, 0, address(eurA), address(tokenP), alice, deadline, authData2
    );
  }

  /// @notice Bailsec Issue_08: a zero-amount signed payload must consume the nonce so it cannot be
  /// replayed, even though no swap happens.
  function test_SwapExactInputWithAuthorization_ZeroAmountConsumesNonce() public {
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 userSalt = bytes32("zeroIn");
    bytes memory authData = _buildSwapExactInputAuth(
      1, address(eurA), address(tokenP), alice, 0, 0, alice, deadline, userSalt
    );

    vm.prank(bob);
    uint256 amountOut = parallelizer.swapExactInputWithAuthorization(
      0, 0, address(eurA), address(tokenP), alice, deadline, authData
    );
    assertEq(amountOut, 0);

    // Replaying the same signature must now revert because the nonce is consumed.
    bytes memory replayAuthData = _buildSwapExactInputAuth(
      1, address(eurA), address(tokenP), alice, 0, 0, alice, deadline, userSalt
    );
    vm.prank(bob);
    vm.expectRevert(bytes("authorization is used"));
    parallelizer.swapExactInputWithAuthorization(
      0, 0, address(eurA), address(tokenP), alice, deadline, replayAuthData
    );
  }

  function test_SwapExactOutputWithAuthorization_ZeroAmountConsumesNonce() public {
    uint256 deadline = block.timestamp + 1 hours;
    bytes32 userSalt = bytes32("zeroOut");
    bytes memory authData = _buildSwapExactOutputAuth(
      1, address(eurA), address(tokenP), alice, 0, 0, alice, deadline, userSalt
    );

    vm.prank(bob);
    uint256 amountIn = parallelizer.swapExactOutputWithAuthorization(
      0, 0, address(eurA), address(tokenP), alice, deadline, authData
    );
    assertEq(amountIn, 0);

    bytes memory replayAuthData = _buildSwapExactOutputAuth(
      1, address(eurA), address(tokenP), alice, 0, 0, alice, deadline, userSalt
    );
    vm.prank(bob);
    vm.expectRevert(bytes("authorization is used"));
    parallelizer.swapExactOutputWithAuthorization(
      0, 0, address(eurA), address(tokenP), alice, deadline, replayAuthData
    );
  }

  function test_SwapExactInputWithAuthorization_EmitsAuthorizerNotRelayer() public {
    uint256 mintAmount = 100 * BASE_6;
    deal(address(eurA), alice, mintAmount);

    uint256 deadline = block.timestamp + 1 hours;
    bytes memory authData = _buildSwapExactInputAuth(
      1, address(eurA), address(tokenP), alice, mintAmount, 0, alice, deadline, bytes32("event_attr")
    );

    uint256 expectedAmountOut = parallelizer.quoteIn(mintAmount, address(eurA), address(tokenP));
    vm.expectEmit(address(parallelizer));
    emit Swap(address(eurA), address(tokenP), mintAmount, expectedAmountOut, alice, alice);

    vm.prank(bob);
    parallelizer.swapExactInputWithAuthorization(
      mintAmount, 0, address(eurA), address(tokenP), alice, deadline, authData
    );
  }

  function test_SwapExactInputWithAuthorization_EIP1271_NonStandardSignatureLength() public {
    Mock1271Signer signer = new Mock1271Signer();
    uint256 mintAmount = 100 * BASE_6;
    deal(address(eurA), address(signer), mintAmount);

    uint256 deadline = block.timestamp + 1 hours;
    bytes32 userSalt = bytes32("eip1271");
    bytes32 derivedNonce = LibAuthorization.computeSwapExactInputNonce(
      address(signer), address(eurA), address(tokenP), mintAmount, 0, address(signer), deadline, userSalt
    );

    bytes32 structHash = keccak256(
      abi.encode(
        RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
        address(signer),
        address(parallelizer),
        mintAmount,
        uint256(0),
        deadline,
        derivedNonce
      )
    );
    bytes32 typedDataHash =
      MessageHashUtils.toTypedDataHash(MockTokenPermit(address(eurA)).DOMAIN_SEPARATOR(), structHash);

    bytes memory signature = new bytes(130);
    for (uint256 i; i < 130; ++i) {
      signature[i] = bytes1(uint8(i + 1));
    }
    signer.setAuthorized(typedDataHash, signature);

    bytes memory authData = abi.encode(
      AuthorizationParams({
        from: address(signer),
        value: mintAmount,
        validAfter: 0,
        validBefore: deadline,
        nonce: userSalt,
        signature: signature
      })
    );

    vm.prank(bob);
    uint256 amountOut = parallelizer.swapExactInputWithAuthorization(
      mintAmount, 0, address(eurA), address(tokenP), address(signer), deadline, authData
    );

    assertGt(amountOut, 0);
    assertEq(tokenP.balanceOf(address(signer)), amountOut);
    assertEq(IERC20(address(eurA)).balanceOf(address(signer)), 0);
  }

  function testFuzz_RevertWhen_AuthorizationDoesNotTransferTokens_ExactInput(
    uint256 mintAmount,
    bytes32 userSalt
  )
    public
  {
    mintAmount = bound(mintAmount, BASE_6, 10_000 * BASE_6);
    deal(address(eurA), alice, mintAmount);

    uint256 deadline = block.timestamp + 1 hours;
    bytes memory authData =
      _buildSwapExactInputAuth(1, address(eurA), address(tokenP), alice, mintAmount, 0, alice, deadline, userSalt);

    vm.mockCall(
      address(eurA),
      abi.encodeWithSelector(
        bytes4(keccak256("receiveWithAuthorization(address,address,uint256,uint256,uint256,bytes32,bytes)"))
      ),
      ""
    );

    vm.prank(bob);
    vm.expectRevert(AuthorizationTransferMismatch.selector);
    parallelizer.swapExactInputWithAuthorization(
      mintAmount, 0, address(eurA), address(tokenP), alice, deadline, authData
    );
  }

  function testFuzz_RevertWhen_AuthorizationDoesNotTransferTokens_ExactOutput(
    uint256 amountOut,
    bytes32 userSalt
  )
    public
  {
    amountOut = bound(amountOut, BASE_18, 1000 * BASE_18);
    uint256 maxIn = (amountOut / 1e12) * 4;
    deal(address(eurA), alice, maxIn);

    uint256 deadline = block.timestamp + 1 hours;
    bytes memory authData = _buildSwapExactOutputAuth(
      1, address(eurA), address(tokenP), alice, amountOut, maxIn, alice, deadline, userSalt
    );

    vm.mockCall(
      address(eurA),
      abi.encodeWithSelector(
        bytes4(keccak256("receiveWithAuthorization(address,address,uint256,uint256,uint256,bytes32,bytes)"))
      ),
      ""
    );

    vm.prank(bob);
    vm.expectRevert(AuthorizationTransferMismatch.selector);
    parallelizer.swapExactOutputWithAuthorization(
      amountOut, maxIn, address(eurA), address(tokenP), alice, deadline, authData
    );
  }

  function testFuzz_RevertWhen_AuthorizationDoesNotTransferTokens_BurnTokenP(
    uint256 burnAmount,
    bytes32 userSalt
  )
    public
  {
    _mintExactInput(alice, address(eurA), 10_000 * BASE_6, 0);
    uint256 tokenPBal = tokenP.balanceOf(alice);
    burnAmount = bound(burnAmount, BASE_18, tokenPBal / 2);

    uint256 deadline = block.timestamp + 1 hours;
    bytes memory authData =
      _buildSwapExactInputAuth(1, address(tokenP), address(eurA), alice, burnAmount, 0, alice, deadline, userSalt);

    vm.mockCall(
      address(tokenP),
      abi.encodeWithSelector(
        bytes4(keccak256("receiveWithAuthorization(address,address,uint256,uint256,uint256,bytes32,bytes)"))
      ),
      ""
    );

    vm.prank(bob);
    vm.expectRevert(AuthorizationTransferMismatch.selector);
    parallelizer.swapExactInputWithAuthorization(
      burnAmount, 0, address(tokenP), address(eurA), alice, deadline, authData
    );
  }
}
