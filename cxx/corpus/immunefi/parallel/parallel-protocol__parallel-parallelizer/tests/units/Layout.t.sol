// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import { ITokenP } from "contracts/interfaces/ITokenP.sol";

import { console } from "@forge-std/console.sol";

import { IMockFacet, MockPureFacet } from "tests/mock/MockFacets.sol";

import { Layout } from "contracts/parallelizer/Layout.sol";
import "contracts/parallelizer/Storage.sol";
import { Test } from "contracts/parallelizer/configs/Test.sol";
import { DiamondCut } from "contracts/parallelizer/facets/DiamondCut.sol";
import "contracts/utils/Constants.sol";

import { Fixture } from "../Fixture.sol";

contract Test_Layout is Fixture {
  Layout layout;

  function setUp() public override {
    super.setUp();
    layout = Layout(address(parallelizer));
  }

  /// @dev Read before `_etch()` replaces the diamond's code, kept in storage so `test_Layout`
  /// stays within the EVM stack-depth limit
  uint64 internal _surplusBufferRatio;
  uint256 internal _lastReleasedAt;
  uint256 internal _totalShares;

  /// @dev The tail of `ParallelizerStorage`, added after the initial layout was written down
  function _assertStructTail() internal view {
    assertEq(layout.surplusBufferRatio(), _surplusBufferRatio);
    assertEq(layout.lastReleasedAt(), _lastReleasedAt);
    assertEq(layout.totalShares(), _totalShares);
    assertEq(layout.swapRouter(), address(bob));
  }

  function test_Layout() public {
    address tokenP = address(parallelizer.tokenP());
    uint8 isRedemptionLive = parallelizer.isPaused(address(0), ActionType.Redeem) ? 0 : 1;
    uint256 stablecoinsIssued = parallelizer.getTotalIssued();
    address[] memory collateralList = parallelizer.getCollateralList();
    (uint64[] memory xRedemptionCurve, int64[] memory yRedemptionCurve) = parallelizer.getRedemptionFees();
    Collateral memory collateral = parallelizer.getCollateralInfo(collateralList[0]);
    hoax(governor);
    parallelizer.toggleTrusted(alice, TrustedType.Updater);
    hoax(governor);
    parallelizer.toggleTrusted(alice, TrustedType.Seller);
    address accessManager = parallelizer.accessManager();
    hoax(governor);
    parallelizer.setSwapRouter(address(bob));
    _surplusBufferRatio = parallelizer.getSurplusBufferRatio();
    _lastReleasedAt = parallelizer.getLastReleasedAt();
    _totalShares = parallelizer.getTotalShares();
    hoax(guardian);
    parallelizer.setDummyImplementation(address(alice));
    address implementation = parallelizer.implementation();

    _etch();

    assertEq(layout.tokenP(), tokenP);
    assertEq(layout.isRedemptionLive(), isRedemptionLive);
    assertEq((layout.normalizedStables() * layout.normalizer()) / BASE_27, stablecoinsIssued);
    for (uint256 i; i < collateralList.length; i++) {
      assertEq(layout.collateralList(i), collateralList[i]);
    }
    for (uint256 i; i < xRedemptionCurve.length; i++) {
      assertEq(layout.xRedemptionCurve(i), xRedemptionCurve[i]);
    }
    for (uint256 i; i < yRedemptionCurve.length; i++) {
      assertEq(layout.yRedemptionCurve(i), yRedemptionCurve[i]);
    }
    (
      uint8 isManaged,
      uint8 isMintLive,
      uint8 isBurnLive,
      uint8 decimals,
      uint8 onlyWhitelisted,
      uint216 normalizedStables,
      bytes memory oracleConfig,
      bytes memory whitelistData,,
    ) = layout.collaterals(collateralList[0]);

    assertEq(isManaged, collateral.isManaged);
    assertEq(isMintLive, collateral.isMintLive);
    assertEq(isBurnLive, collateral.isBurnLive);
    assertEq(decimals, collateral.decimals);
    assertEq(onlyWhitelisted, collateral.onlyWhitelisted);
    assertEq(normalizedStables, collateral.normalizedStables);
    assertEq(oracleConfig, collateral.oracleConfig);
    assertEq(whitelistData, collateral.whitelistData);
    assertEq(layout.isTrusted(alice), 1);
    assertEq(layout.isSellerTrusted(alice), 1);
    assertEq(layout.isTrusted(bob), 0);
    assertEq(layout.isSellerTrusted(bob), 0);

    bytes4[] memory selectors = _generateSelectors("IParallelizer");
    for (uint256 i = 0; i < selectors.length; ++i) {
      (address facetAddress, uint16 selectorPosition) = layout.selectorInfo(selectors[i]);
      assertNotEq(facetAddress, address(0));
      assertEq(layout.selectors(selectorPosition), selectors[i]);
    }

    _assertStructTail();

    assertEq(layout.accessManager(), accessManager);
    assertEq(layout.implementation(), implementation);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    INTERNAL
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _etch() internal {
    Layout tempLayout = new Layout();
    vm.etch(address(layout), address(tempLayout).code);
  }
}
