// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

import "contracts/utils/Errors.sol";
import { Collateral } from "contracts/parallelizer/Storage.sol";

import "../Fixture.sol";
import "../utils/FunctionUtils.sol";

import { stdError } from "@forge-std/Test.sol";

contract GettersTest is Fixture, FunctionUtils {
  using SafeERC20 for IERC20;

  int64 internal _minRedeemFee = 0;
  int64 internal _minMintFee = -int64(int256(BASE_9 / 2));
  int64 internal _minBurnFee = -int64(int256(BASE_9 / 2));
  int64 internal _maxRedeemFee = int64(int256(BASE_9));
  int64 internal _maxMintFee = int64(int256(BASE_12));
  int64 internal _maxBurnFee = int64(int256((BASE_9 * 999) / 1000));

  address[] internal _collaterals;
  AggregatorV3Interface[] internal _oracles;
  uint256[] internal _maxTokenAmount;

  function setUp() public override {
    super.setUp();

    _collaterals.push(address(eurA));
    _collaterals.push(address(eurB));
    _collaterals.push(address(eurY));
    _oracles.push(oracleA);
    _oracles.push(oracleB);
    _oracles.push(oracleY);
  }

  // only the governor that has the guardian role is allowed to set negatives fees, so we need
  // to grant the governor role to the guardian to be able to set negatives fees.
  modifier grantGovernorRoleToGuardian() {
    vm.startPrank(governor);
    accessManager.grantRole(GOVERNOR_ROLE, guardian, 0);
    vm.stopPrank();
    _;
  }
  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       RAW CALLS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function test_GetRawCalls() public {
    address accessManagerParallelizer = parallelizer.accessManager();
    ITokenP tokenPParallelizer = parallelizer.tokenP();
    assertEq(address(tokenP), address(tokenPParallelizer));
    assertEq(address(accessManager), accessManagerParallelizer);
  }

  function test_AccessManager() public {
    IAccessManager accessManagerParallelizer = IAccessManager(parallelizer.accessManager());
    (bool isGovernor,) = accessManagerParallelizer.hasRole(GOVERNOR_ROLE, governor);
    assertTrue(isGovernor);
    (isGovernor,) = accessManagerParallelizer.hasRole(GOVERNOR_ROLE, guardian);
    assertFalse(isGovernor);
    (isGovernor,) = accessManagerParallelizer.hasRole(GOVERNOR_ROLE, alice);
    assertFalse(isGovernor);
    (bool isGuardian,) = accessManagerParallelizer.hasRole(GUARDIAN_ROLE, governor);
    assertFalse(isGuardian);
    (isGuardian,) = accessManagerParallelizer.hasRole(GUARDIAN_ROLE, guardian);
    assertTrue(isGuardian);
    (isGuardian,) = accessManagerParallelizer.hasRole(GUARDIAN_ROLE, alice);
    assertFalse(isGuardian);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   GETCOLLATERALLIST
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_GetCollateralList(uint256 addCollateral) public {
    addCollateral = bound(addCollateral, 0, 43);
    vm.startPrank(governor);
    for (uint256 i; i < addCollateral; i++) {
      address eurCollat = address(
        new MockTokenPermit(string.concat("EUR_", Strings.toString(i)), string.concat("EUR_", Strings.toString(i)), 18)
      );
      parallelizer.addCollateral(eurCollat);
      _collaterals.push(eurCollat);
    }
    vm.stopPrank();
    address[] memory collateralList = parallelizer.getCollateralList();
    assertEq(_collaterals, collateralList);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   GETCOLLATERALINFO
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_GetCollateralInfo(
    uint256 fromToken,
    uint64[10] memory xFeeMintUnbounded,
    int64[10] memory yFeeMintUnbounded
  )
    public
    grantGovernorRoleToGuardian
  {
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    _setBurnFeesForNegativeMintFees();
    (uint64[] memory xFeeMint, int64[] memory yFeeMint) =
      _randomMintFees(_collaterals[fromToken], xFeeMintUnbounded, yFeeMintUnbounded);
    Collateral memory collat = parallelizer.getCollateralInfo(_collaterals[fromToken]);
    _assertArrayUint64(xFeeMint, collat.xFeeMint);
    _assertArrayInt64(yFeeMint, collat.yFeeMint);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 GETCOLLATERALMINTFEES
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_GetCollateralMintFees(
    uint256 fromToken,
    uint64[10] memory xFeeMintUnbounded,
    int64[10] memory yFeeMintUnbounded
  )
    public
    grantGovernorRoleToGuardian
  {
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    _setBurnFeesForNegativeMintFees();
    (uint64[] memory xFeeMint, int64[] memory yFeeMint) =
      _randomMintFees(_collaterals[fromToken], xFeeMintUnbounded, yFeeMintUnbounded);
    (uint64[] memory xRealFeeMint, int64[] memory yRealFeeMint) =
      parallelizer.getCollateralMintFees(_collaterals[fromToken]);
    _assertArrayUint64(xFeeMint, xRealFeeMint);
    _assertArrayInt64(yFeeMint, yRealFeeMint);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 GETCOLLATERALBURNFEES
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_GetCollateralBurnFees(
    uint256 fromToken,
    uint64[10] memory xFeeBurnUnbounded,
    int64[10] memory yFeeBurnUnbounded
  )
    public
    grantGovernorRoleToGuardian
  {
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    _setMintFeesForNegativeBurnFees();
    (uint64[] memory xFeeBurn, int64[] memory yFeeBurn) =
      _randomBurnFees(_collaterals[fromToken], xFeeBurnUnbounded, yFeeBurnUnbounded);
    (uint64[] memory xRealFeeBurn, int64[] memory yRealFeeBurn) =
      parallelizer.getCollateralBurnFees(_collaterals[fromToken]);
    _assertArrayUint64(xFeeBurn, xRealFeeBurn);
    _assertArrayInt64(yFeeBurn, yRealFeeBurn);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   GETREDEMPTIONFEES
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_GetRedemptionFees(
    uint64[10] memory xFeeRedemptionUnbounded,
    int64[10] memory yFeeRedemptionUnbounded
  )
    public
    grantGovernorRoleToGuardian
  {
    (uint64[] memory xFeeRedemption, int64[] memory yFeeRedemption) =
      _randomRedemptionFees(xFeeRedemptionUnbounded, yFeeRedemptionUnbounded);
    (uint64[] memory xRealFeeRedemption, int64[] memory yRealFeeRedemption) = parallelizer.getRedemptionFees();
    _assertArrayUint64(xFeeRedemption, xRealFeeRedemption);
    _assertArrayInt64(yFeeRedemption, yRealFeeRedemption);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        ASSERTS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _assertArrayUint64(uint64[] memory a, uint64[] memory b) internal {
    if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
      fail();
    }
  }

  function _assertArrayInt64(int64[] memory a, int64[] memory b) internal {
    if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
      fail();
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         UTILS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _setMintFeesForNegativeBurnFees() internal {
    // set mint Fees to be consistent with the min fee on Burn
    uint64[] memory xFee = new uint64[](1);
    xFee[0] = uint64(0);
    int64[] memory yFee = new int64[](1);
    yFee[0] = -_minMintFee;
    vm.startPrank(guardian);
    parallelizer.setFees(address(eurA), xFee, yFee, true);
    parallelizer.setFees(address(eurB), xFee, yFee, true);
    parallelizer.setFees(address(eurY), xFee, yFee, true);
    vm.stopPrank();
  }

  function _setBurnFeesForNegativeMintFees() internal {
    // set mint Fees to be consistent with the min fee on Burn
    uint64[] memory xFee = new uint64[](1);
    xFee[0] = uint64(BASE_9);
    int64[] memory yFee = new int64[](1);
    yFee[0] = -_minBurnFee;
    vm.startPrank(guardian);
    parallelizer.setFees(address(eurA), xFee, yFee, false);
    parallelizer.setFees(address(eurB), xFee, yFee, false);
    parallelizer.setFees(address(eurY), xFee, yFee, false);
    vm.stopPrank();
  }

  function _randomRedemptionFees(
    uint64[10] memory xFeeRedeemUnbounded,
    int64[10] memory yFeeRedeemUnbounded
  )
    internal
    returns (uint64[] memory xFeeRedeem, int64[] memory yFeeRedeem)
  {
    (xFeeRedeem, yFeeRedeem) =
      _generateCurves(xFeeRedeemUnbounded, yFeeRedeemUnbounded, true, false, _minRedeemFee, _maxRedeemFee);
    vm.prank(guardian);
    parallelizer.setRedemptionCurveParams(xFeeRedeem, yFeeRedeem);
  }

  function _randomBurnFees(
    address collateral,
    uint64[10] memory xFeeBurnUnbounded,
    int64[10] memory yFeeBurnUnbounded
  )
    internal
    returns (uint64[] memory xFeeBurn, int64[] memory yFeeBurn)
  {
    (xFeeBurn, yFeeBurn) =
      _generateCurves(xFeeBurnUnbounded, yFeeBurnUnbounded, false, false, _minBurnFee, _maxBurnFee);
    vm.prank(guardian);
    parallelizer.setFees(collateral, xFeeBurn, yFeeBurn, false);
  }

  function _randomMintFees(
    address collateral,
    uint64[10] memory xFeeMintUnbounded,
    int64[10] memory yFeeMintUnbounded
  )
    internal
    returns (uint64[] memory xFeeMint, int64[] memory yFeeMint)
  {
    (xFeeMint, yFeeMint) = _generateCurves(xFeeMintUnbounded, yFeeMintUnbounded, true, true, _minMintFee, _maxMintFee);
    vm.prank(guardian);
    parallelizer.setFees(collateral, xFeeMint, yFeeMint, true);
  }
}
