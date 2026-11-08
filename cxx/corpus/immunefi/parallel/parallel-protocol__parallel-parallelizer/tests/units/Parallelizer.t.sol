// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { ITokenP } from "contracts/interfaces/ITokenP.sol";
import { AggregatorV3Interface } from "contracts/interfaces/external/chainlink/AggregatorV3Interface.sol";

import { MockAccessControlManager } from "tests/mock/MockAccessControlManager.sol";
import { MockChainlinkOracle } from "tests/mock/MockChainlinkOracle.sol";
import { MockTokenPermit } from "tests/mock/MockTokenPermit.sol";
import { MockMorphoOracle } from "tests/mock/MockMorphoOracle.sol";
import { MockManager } from "tests/mock/MockManager.sol";
import { IGetters } from "contracts/interfaces/IGetters.sol";

import { Test } from "contracts/parallelizer/configs/Test.sol";
import { LibGetters } from "contracts/parallelizer/libraries/LibGetters.sol";
import "contracts/parallelizer/Storage.sol";
import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol";

import { Fixture } from "../Fixture.sol";

contract TestParallelizer is Fixture {
  function test_FacetsHaveCorrectSelectors() public {
    for (uint256 i = 0; i < facetAddressList.length; ++i) {
      bytes4[] memory fromLoupeFacet = parallelizer.facetFunctionSelectors(facetAddressList[i]);
      bytes4[] memory fromGenSelectors = _generateSelectors(facetNames[i]);
      assertTrue(sameMembers(fromLoupeFacet, fromGenSelectors));
    }
  }

  function test_SelectorsAssociatedWithCorrectFacet() public {
    for (uint256 i = 0; i < facetAddressList.length; ++i) {
      bytes4[] memory fromGenSelectors = _generateSelectors(facetNames[i]);
      for (uint256 j = 0; j < fromGenSelectors.length; j++) {
        assertEq(facetAddressList[i], parallelizer.facetAddress(fromGenSelectors[j]));
      }
    }
  }

  function test_InterfaceCorrectlyImplemented() public {
    bytes4[] memory selectors = _generateSelectors("IParallelizer");
    for (uint256 i = 0; i < selectors.length; ++i) {
      assertEq(parallelizer.isValidSelector(selectors[i]), true);
    }
  }

  // Checks that all implemented selectors are in the interface
  function test_OnlyInterfaceIsImplemented() public {
    bytes4[] memory interfaceSelectors = _generateSelectors("IParallelizer");

    Facet[] memory facets = parallelizer.facets();

    for (uint256 i; i < facetNames.length; ++i) {
      for (uint256 j; j < facets[i].functionSelectors.length; ++j) {
        bool found = false;
        for (uint256 k; k < interfaceSelectors.length; ++k) {
          if (facets[i].functionSelectors[j] == interfaceSelectors[k]) {
            found = true;
            break;
          }
        }
        assert(found);
      }
    }
  }

  function test_QuoteInScenario() public {
    uint256 quote = (parallelizer.quoteIn(BASE_6, address(eurA), address(tokenP)));
    assertEq(quote, BASE_27 / (BASE_9 + BASE_9 / 99));
  }

  function test_SimpleSwapInScenario() public {
    deal(address(eurA), alice, BASE_6);

    startHoax(alice);
    eurA.approve(address(parallelizer), BASE_6);
    parallelizer.swapExactInput(BASE_6, 0, address(eurA), address(tokenP), alice, block.timestamp + 1 hours);

    assertEq(tokenP.balanceOf(alice), BASE_27 / (BASE_9 + BASE_9 / 99));
  }

  function test_QuoteCollateralRatio() public {
    parallelizer.getCollateralRatio();
    assertEq(uint256(0), uint256(0));
  }

  function test_QuoteCollateralRatioDirectCall() public {
    LibGetters.getCollateralRatio();
    assertEq(uint256(0), uint256(0));
  }

  ///---------------------------------
  /// Test ProcessSurplus
  ///---------------------------------

  modifier setSurplusBufferRatio() {
    vm.startPrank(governor);
    parallelizer.updateSurplusBufferRatio(uint64(BASE_9));
    vm.stopPrank();
    _;
  }

  function test_ProcessSurplus_Success()
    public
    swapSomeCollateralToTokenPAndUpdateOracleToMorphoOracle
    updateSlippageToleranceTo1e7
    setSurplusBufferRatio
  {
    vm.startPrank(governor);
    (uint256 collateralSurplus,) = parallelizer.getCollateralSurplus(address(eurA));
    uint256 amountOut = parallelizer.quoteIn(collateralSurplus, address(eurA), address(tokenP));

    parallelizer.processSurplus(address(eurA), 0);
    assertEq(tokenP.balanceOf(address(parallelizer)), amountOut);
  }

  function test_ProcessSurplus_RevertWhen_AmountOutIsTooSmall()
    public
    swapSomeCollateralToTokenPAndUpdateOracleToMorphoOracle
    setSurplusBufferRatio
  {
    vm.startPrank(governor);
    vm.expectRevert(TooSmallAmountOut.selector);
    parallelizer.processSurplus(address(eurA), 0);
  }

  function test_ProcessSurplus_RevertWhen_NoSurplus() public setSurplusBufferRatio {
    vm.startPrank(governor);
    vm.expectRevert(ZeroSurplusAmount.selector);
    parallelizer.processSurplus(address(eurA), 0);
  }

  function test_ProcessSurplus_RevertWhen_SurplusBufferRatioNotSet()
    public
    swapSomeCollateralToTokenPAndUpdateOracleToMorphoOracle
    updateSlippageToleranceTo1e7
  {
    vm.startPrank(governor);
    vm.expectRevert(SurplusBufferRatioNotSet.selector);
    parallelizer.processSurplus(address(eurA), 0);
  }

  function test_ProcessSurplus_WithAmount_CapsCollateralSwapped()
    public
    swapSomeCollateralToTokenPAndUpdateOracleToMorphoOracle
    updateSlippageToleranceTo1e7
    setSurplusBufferRatio
  {
    vm.startPrank(governor);
    (uint256 collateralSurplus,) = parallelizer.getCollateralSurplus(address(eurA));

    // Process only half the surplus
    uint256 halfSurplus = collateralSurplus / 2;
    uint256 amountOut = parallelizer.quoteIn(halfSurplus, address(eurA), address(tokenP));

    (uint256 processedCollateral,, uint256 issuedAmount) = parallelizer.processSurplus(address(eurA), halfSurplus);
    assertEq(processedCollateral, halfSurplus);
    assertEq(issuedAmount, amountOut);
    assertEq(tokenP.balanceOf(address(parallelizer)), amountOut);
  }

  modifier setZeroMintFeesOnAllCollaterals() {
    _setZeroMintFees(address(eurA));
    _setZeroMintFees(address(eurB));
    _setZeroMintFees(address(eurY));
    _;
  }

  modifier mintTokenPFromAllCollaterals() {
    _mintZeroFee(address(eurA), 100 * BASE_6);
    _mintZeroFee(address(eurB), 100 * 1e12);
    _mintZeroFee(address(eurY), 100 * BASE_18);
    _;
  }

  function test_ProcessSurplus_Success_CapsPerCollateralSurplusByGlobalSurplus()
    public
    setZeroMintFeesOnAllCollaterals
    mintTokenPFromAllCollaterals
    setSurplusBufferRatio
  {
    (uint64 crBefore,) = parallelizer.getCollateralRatio();
    assertTrue(crBefore >= BASE_9, "ProcessSurplus: Protocol should be healthy before surplus processing");

    _setSlippageTolerance(address(eurB), 1e8);

    // set eurB is a yield-bearing asset
    _setOracleMaxTarget(address(eurB), address(oracleB), 1.08e18);
    // eurB appreciates to 1.08 to generate surplus
    MockChainlinkOracle(address(oracleB)).setLatestAnswer(int256(1.08e8));
    // eurA depegs to 0.95 to make the protocol at risk
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(0.95e8));

    // Per-collateral eurB surplus = 8, but global surplus ≈ 3, so surplus is capped
    vm.startPrank(governor);
    parallelizer.processSurplus(address(eurB), 0);
    vm.stopPrank();

    (uint64 crAfter,) = parallelizer.getCollateralRatio();
    assertGe(crAfter, uint64(BASE_9), "CR should remain >= surplusBufferRatio after capped surplus processing");
  }

  function test_ProcessSurplus_RevertWhen_CRDropsBelowSurplusBufferRatio()
    public
    setZeroMintFeesOnAllCollaterals
    mintTokenPFromAllCollaterals
  {
    _setSlippageTolerance(address(eurB), 1e8);

    // set eurB as yield-bearing asset
    _setOracleMaxTarget(address(eurB), address(oracleB), 1.08e18);
    // eurB appreciates to 1.08 to generate surplus
    MockChainlinkOracle(address(oracleB)).setLatestAnswer(int256(1.08e8));

    // Set a high buffer ratio (1.05) — CR after surplus will be above 1.0 but below 1.05
    vm.startPrank(governor);
    parallelizer.updateSurplusBufferRatio(uint64(1.05e9));
    // Global CR ≈ 1.027 < surplusBufferRatio (1.05), so no global surplus is extractable
    vm.expectRevert(ZeroSurplusAmount.selector);
    parallelizer.processSurplus(address(eurB), 0);
    vm.stopPrank();
  }

  function test_ProcessSurplus_Success_WithSurplusBufferRatioAbove100()
    public
    setZeroMintFeesOnAllCollaterals
    mintTokenPFromAllCollaterals
  {
    _setSlippageTolerance(address(eurB), 1e8);

    // set eurB as yield-bearing asset with target 1.08
    _setOracleMaxTarget(address(eurB), address(oracleB), 1.08e18);
    // eurB appreciates to 1.08 to generate surplus
    MockChainlinkOracle(address(oracleB)).setLatestAnswer(int256(1.08e8));
    // Appreciate eurA and eurY too so global CR is well above the buffer
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(1.08e8));
    MockChainlinkOracle(address(oracleY)).setLatestAnswer(int256(1.08e8));

    // Set buffer ratio to 1.01 (101%)
    vm.startPrank(governor);
    parallelizer.updateSurplusBufferRatio(uint64(1.01e9));

    (uint64 crBefore,) = parallelizer.getCollateralRatio();
    assertTrue(crBefore > uint64(1.01e9));

    parallelizer.processSurplus(address(eurB), 0);

    (uint64 crAfter,) = parallelizer.getCollateralRatio();
    assertGe(crAfter, uint64(1.01e9));
    assertLe(crAfter, crBefore);
    vm.stopPrank();
  }

  function test_ProcessSurplus_RevertWhen_NormalizerNotBase27_OvercountsSurplus()
    public
    setZeroMintFeesOnAllCollaterals
  {
    _mintZeroFee(address(eurA), 100 * BASE_6);

    // increase normalizer by 10%
    vm.startPrank(governor);
    parallelizer.toggleTrusted(governor, TrustedType.Updater);
    parallelizer.updateNormalizer(10e18, true);
    vm.stopPrank();

    (uint256 actualStables,) = parallelizer.getIssuedByCollateral(address(eurA));
    assertEq(actualStables, 110e18, "ProcessSurplus: denormalized stables should be 110e18");

    // set eurA as yield-bearing asset
    _setOracleMaxTarget(address(eurA), address(oracleA), 1.08e18);
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(1.08e8));
    _setSlippageTolerance(address(eurA), 1e8);

    vm.startPrank(governor);
    parallelizer.updateSurplusBufferRatio(uint64(BASE_9));
    vm.expectRevert();
    parallelizer.processSurplus(address(eurA), 0);
    vm.stopPrank();
  }

  function test_GetCollateralSurplus_RevertWhen_NoSurplus_ZeroSurplusAmount()
    public
    setZeroMintFeesOnAllCollaterals
    setSurplusBufferRatio
  {
    _mintZeroFee(address(eurA), 100 * BASE_6);
    vm.expectRevert(ZeroSurplusAmount.selector);
    parallelizer.getCollateralSurplus(address(eurA));
  }

  function test_GetCollateralSurplus_CapsPerCollateralSurplusByGlobalSurplus() public setZeroMintFeesOnAllCollaterals {
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(0.6667e8));
    _mintZeroFee(address(eurA), 150 * BASE_6);
    _mintZeroFee(address(eurB), 100 * BASE_12);

    vm.startPrank(governor);
    // Set buffer ratio to 1.1 (110%)
    parallelizer.updateSurplusBufferRatio(uint64(1.1e9));
    vm.stopPrank();

    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(1e8));

    // eurA: 150 value, ~100 stables; eurB: 100 value, ~100 stables
    // global CR = 250 / 200 = 1.25 > 1.1, so global surplus is extractable
    // Per-collateral eurA surplus = 150/1.1 - 100 = 36.36
    // Global surplus = 200 * (1.25 - 1.1) / 1.1 = 27.27
    // Capped surplus = min(36.36, 27.27) = 27.27
    (uint256 collateralSurplus, uint256 stableSurplus) = parallelizer.getCollateralSurplus(address(eurA));

    assertApproxEqAbs(stableSurplus, 27.27e18, 0.01e18);
    assertApproxEqAbs(collateralSurplus, 27.27e6, 0.01e6);
  }

  function test_ProcessSurplus_CapsPerCollateralSurplusByGlobalSurplus() public setZeroMintFeesOnAllCollaterals {
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(0.6667e8));
    _mintZeroFee(address(eurA), 150 * BASE_6);
    _mintZeroFee(address(eurB), 100 * BASE_12);

    _setSlippageTolerance(address(eurA), 1e8);

    vm.startPrank(governor);
    parallelizer.updateSurplusBufferRatio(uint64(1.1e9));
    vm.stopPrank();

    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(1e8));

    // eurA: 150 value, ~100 stables; eurB: 100 value, ~100 stables
    // global CR = 250 / 200 = 1.25 > 1.1, so global surplus is extractable
    // Per-collateral eurA surplus = 150/1.1 - 100 = 36.36
    // Global surplus = 200 * (1.25 - 1.1) / 1.1 = 27.27
    // Capped surplus = min(36.36, 27.27) = 27.27
    (uint64 crBefore,) = parallelizer.getCollateralRatio();

    vm.prank(governor);
    (uint256 collateralSurplus, uint256 stableSurplus,) = parallelizer.processSurplus(address(eurA), 0);

    assertApproxEqAbs(stableSurplus, 27.27e18, 0.01e18);
    assertApproxEqAbs(collateralSurplus, 27.27e6, 0.01e6);

    (uint64 crAfter,) = parallelizer.getCollateralRatio();
    assertGe(crAfter, uint64(1.1e9), "CR should remain >= surplusBufferRatio after capped surplus processing");
    assertLt(crAfter, crBefore, "CR should decrease after surplus processing");
  }

  function test_GetCollateralSurplus_RevertWhen_GlobalCRBelowSurplusBufferRatio()
    public
    setZeroMintFeesOnAllCollaterals
  {
    _mintZeroFee(address(eurA), 100 * BASE_6);
    _mintZeroFee(address(eurB), 100 * BASE_12);

    vm.startPrank(governor);
    // Set buffer ratio to 1.1 (110%)
    parallelizer.updateSurplusBufferRatio(uint64(1.1e9));
    vm.stopPrank();

    // Global CR = 200/200 = 1.0 < surplusBufferRatio (1.1)
    // eurA has per-collateral CR = 1.0, no per-collateral surplus either
    vm.expectRevert(ZeroSurplusAmount.selector);
    parallelizer.getCollateralSurplus(address(eurA));

    // eurA appreciates to 1.15 → per-collateral CR = 1.15, surplus exists per-collateral
    // eurB depreciates to 0.9 → global CR = (115 + 90) / 200 = 1.025 < 1.1
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(1.15e8));
    MockChainlinkOracle(address(oracleB)).setLatestAnswer(int256(0.9e8));

    vm.expectRevert(ZeroSurplusAmount.selector);
    parallelizer.getCollateralSurplus(address(eurA));
  }

  function test_GetCollateralSurplus_WorksForManagedCollateral()
    public
    setZeroMintFeesOnAllCollaterals
    setSurplusBufferRatio
  {
    // Set up eurA as managed collateral
    MockManager manager = new MockManager(address(eurA));
    IERC20[] memory subCollaterals = new IERC20[](1);
    subCollaterals[0] = eurA;
    manager.setSubCollaterals(subCollaterals, "");
    ManagerStorage memory managerData = ManagerStorage({
      subCollaterals: subCollaterals, config: abi.encode(ManagerType.EXTERNAL, abi.encode(address(manager)))
    });
    vm.prank(governor);
    parallelizer.setCollateralManager(address(eurA), true, managerData);

    // Mint tokenP from eurA — tokens flow to the manager, not the parallelizer
    _mintZeroFee(address(eurA), 100 * BASE_6);
    assertEq(eurA.balanceOf(address(parallelizer)), 0, "Tokens should be at manager");
    assertGt(eurA.balanceOf(address(manager)), 0, "Manager should hold tokens");

    // set eurA as yield-bearing asset
    _setOracleMaxTarget(address(eurA), address(oracleA), 1.08e18);
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(1.08e8));

    (uint256 collateralSurplus, uint256 stableSurplus) = parallelizer.getCollateralSurplus(address(eurA));
    assertGt(collateralSurplus, 0, "ProcessSurplus: managed collateral should report surplus");
    assertGt(stableSurplus, 0, "ProcessSurplus: managed collateral should report stable surplus");
  }

  function test_ProcessSurplus_Success_ForManagedCollateral()
    public
    setZeroMintFeesOnAllCollaterals
    setSurplusBufferRatio
  {
    // Set up eurA as managed collateral
    MockManager manager = new MockManager(address(eurA));
    IERC20[] memory subCollaterals = new IERC20[](1);
    subCollaterals[0] = eurA;
    manager.setSubCollaterals(subCollaterals, "");
    ManagerStorage memory managerData = ManagerStorage({
      subCollaterals: subCollaterals, config: abi.encode(ManagerType.EXTERNAL, abi.encode(address(manager)))
    });
    vm.prank(governor);
    parallelizer.setCollateralManager(address(eurA), true, managerData);

    // Mint tokenP from eurA — tokens flow to the manager
    _mintZeroFee(address(eurA), 100 * BASE_6);
    uint256 managerBalanceBefore = eurA.balanceOf(address(manager));
    assertEq(eurA.balanceOf(address(parallelizer)), 0, "Tokens should be at manager");
    assertEq(managerBalanceBefore, 100 * BASE_6, "Manager should hold tokens");

    // Set eurA as yield-bearing asset and appreciate to 1.08
    _setOracleMaxTarget(address(eurA), address(oracleA), 1.08e18);
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(1.08e8));
    _setSlippageTolerance(address(eurA), 1e8);

    vm.startPrank(governor);
    (uint256 collateralSurplus,) = parallelizer.getCollateralSurplus(address(eurA));
    uint256 amountOut = parallelizer.quoteIn(collateralSurplus, address(eurA), address(tokenP));

    (uint256 processedCollateral,, uint256 issuedAmount) = parallelizer.processSurplus(address(eurA), 0);
    assertEq(processedCollateral, collateralSurplus, "Should process full surplus");
    assertEq(issuedAmount, amountOut, "Issued amount should match quote");
    assertEq(tokenP.balanceOf(address(parallelizer)), issuedAmount, "Should have minted tokenP");
    assertEq(eurA.balanceOf(address(manager)), managerBalanceBefore, "Manager balance should be unchanged");
    assertEq(eurA.balanceOf(address(parallelizer)), 0, "Parallelizer should have no collateral left");
    vm.stopPrank();
  }

  function test_ProcessSurplus_WithAmount_CapsCollateralSwapped_ForManagedCollateral()
    public
    setZeroMintFeesOnAllCollaterals
  {
    // Set up eurA as managed collateral
    MockManager manager = new MockManager(address(eurA));
    IERC20[] memory subCollaterals = new IERC20[](1);
    subCollaterals[0] = eurA;
    manager.setSubCollaterals(subCollaterals, "");
    ManagerStorage memory managerData = ManagerStorage({
      subCollaterals: subCollaterals, config: abi.encode(ManagerType.EXTERNAL, abi.encode(address(manager)))
    });
    vm.prank(governor);
    parallelizer.setCollateralManager(address(eurA), true, managerData);

    _mintZeroFee(address(eurA), 100 * BASE_6);

    _setOracleMaxTarget(address(eurA), address(oracleA), 1.08e18);
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(1.08e8));
    _setSlippageTolerance(address(eurA), 1e8);

    vm.startPrank(governor);
    parallelizer.updateSurplusBufferRatio(uint64(BASE_9));

    (uint256 collateralSurplus,) = parallelizer.getCollateralSurplus(address(eurA));
    uint256 halfSurplus = collateralSurplus / 2;
    uint256 amountOut = parallelizer.quoteIn(halfSurplus, address(eurA), address(tokenP));

    (uint256 processedCollateral,, uint256 issuedAmount) = parallelizer.processSurplus(address(eurA), halfSurplus);
    assertEq(processedCollateral, halfSurplus, "Should process only half surplus");
    assertEq(issuedAmount, amountOut, "Issued amount should match quote for half");
    vm.stopPrank();
  }

  function test_ProcessSurplus_MaintainsCR_ForManagedCollateral()
    public
    setZeroMintFeesOnAllCollaterals
    mintTokenPFromAllCollaterals
  {
    MockManager manager = new MockManager(address(eurA));
    IERC20[] memory subCollaterals = new IERC20[](1);
    subCollaterals[0] = eurA;
    manager.setSubCollaterals(subCollaterals, "");
    ManagerStorage memory managerData = ManagerStorage({
      subCollaterals: subCollaterals, config: abi.encode(ManagerType.EXTERNAL, abi.encode(address(manager)))
    });
    vm.prank(governor);
    parallelizer.setCollateralManager(address(eurA), true, managerData);

    // Note: eurA tokens are still in parallelizer from prior mint, move them to manager
    uint256 parallelizerBalance = eurA.balanceOf(address(parallelizer));
    vm.prank(address(parallelizer));
    eurA.transfer(address(manager), parallelizerBalance);

    _setOracleMaxTarget(address(eurA), address(oracleA), 1.08e18);
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(1.08e8));
    _setSlippageTolerance(address(eurA), 1e8);

    (uint64 crBefore,) = parallelizer.getCollateralRatio();

    vm.startPrank(governor);
    parallelizer.updateSurplusBufferRatio(uint64(BASE_9));
    parallelizer.processSurplus(address(eurA), 0);
    vm.stopPrank();

    (uint64 crAfter,) = parallelizer.getCollateralRatio();
    assertGe(crAfter, uint64(BASE_9), "CR should remain above surplus buffer ratio");
    assertLe(crAfter, crBefore, "CR should decrease or stay the same after surplus processing");
  }

  ///---------------------------------
  /// Test Release
  ///---------------------------------

  function test_Release_Surplus_Success() public addReleasePayees setSomeSurplus updateSlippageToleranceTo1e7 {
    vm.startPrank(governor);
    uint256 surplus = tokenP.balanceOf(address(parallelizer));
    (address[] memory payees, uint256[] memory amounts) = parallelizer.release();
    assertEq(payees.length, 2);
    assertEq(payees[0], address(0));
    assertEq(payees[1], address(treasury));
    assertEq(amounts[0], surplus * 1 ether / 10 ether);
    assertEq(amounts[1], surplus * 9 ether / 10 ether);
    assertEq(tokenP.balanceOf(address(treasury)), surplus * 9 ether / 10 ether);
    assertEq(tokenP.balanceOf(address(parallelizer)), 0);
  }

  function test_Release_Surplus_RevertWhen_NoIncome() public addReleasePayees {
    vm.startPrank(governor);
    vm.expectRevert(ZeroAmount.selector);
    parallelizer.release();
  }

  function test_ProcessSurplus_Success_SpotBelowTargetWithinDeviation()
    public
    setZeroMintFeesOnAllCollaterals
    setSurplusBufferRatio
  {
    // Mint 100 tokenP at oracle = 1.0 (default STABLE target, userDeviation=0)
    _mintZeroFee(address(eurA), 100 * BASE_6);

    // Reconfigure eurA oracle: MAX target = 1.10, userDeviation = 5%
    AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
    uint32[] memory stalePeriods = new uint32[](1);
    uint8[] memory circuitChainIsMultiplied = new uint8[](1);
    uint8[] memory chainlinkDecimals = new uint8[](1);
    circuitChainlink[0] = AggregatorV3Interface(address(oracleA));
    stalePeriods[0] = 1 hours;
    circuitChainIsMultiplied[0] = 1;
    chainlinkDecimals[0] = 8;
    OracleQuoteType quoteType = OracleQuoteType.UNIT;
    bytes memory readData =
      abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals, quoteType);
    bytes memory targetData = abi.encode(uint256(1.1e18));

    vm.startPrank(governor);
    parallelizer.setOracle(
      address(eurA),
      abi.encode(
        OracleReadType.CHAINLINK_FEEDS,
        OracleReadType.MAX,
        readData,
        targetData,
        abi.encode(uint128(5e16), uint128(5e16)) // userDeviation=5%, burnRatioDeviation=5%
      )
    );
    vm.stopPrank();

    // Drop spot price to 1.07 — below target (1.10) but within 5% deviation
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(1.07e8));

    // Verify surplus exists
    (uint256 collateralSurplus, uint256 stableSurplus) = parallelizer.getCollateralSurplus(address(eurA));
    assertGt(collateralSurplus, 0, "Surplus should exist");
    assertGt(stableSurplus, 0, "Stable surplus should exist");

    // After fix: processSurplus should succeed because _computeCollateralSurplus
    // now uses min(readRedemption, readMint) for conservative sizing
    _setSlippageTolerance(address(eurA), 1e8);
    vm.startPrank(governor);
    parallelizer.processSurplus(address(eurA), 0);
    vm.stopPrank();
  }

  ///---------------------------------
  /// Helpers
  ///---------------------------------

  function _setZeroMintFees(address collateral) internal {
    vm.startPrank(guardian);
    uint64[] memory xMintFee = new uint64[](1);
    xMintFee[0] = uint64(0);
    int64[] memory yMintFee = new int64[](1);
    yMintFee[0] = int64(0);
    parallelizer.setFees(collateral, xMintFee, yMintFee, true);
    vm.stopPrank();
  }

  function _mintZeroFee(address collateral, uint256 amount) internal {
    vm.startPrank(governor);
    deal(collateral, governor, amount);
    IERC20(collateral).approve(address(parallelizer), amount);
    parallelizer.swapExactInput(amount, 0, collateral, address(tokenP), governor, block.timestamp + 1 hours);
    vm.stopPrank();
  }

  function _setOracleMaxTarget(address collateral, address oracle, uint256 maxPrice) internal {
    AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
    uint32[] memory stalePeriods = new uint32[](1);
    uint8[] memory circuitChainIsMultiplied = new uint8[](1);
    uint8[] memory chainlinkDecimals = new uint8[](1);
    circuitChainlink[0] = AggregatorV3Interface(oracle);
    stalePeriods[0] = 1 hours;
    circuitChainIsMultiplied[0] = 1;
    chainlinkDecimals[0] = 8;
    OracleQuoteType quoteType = OracleQuoteType.UNIT;
    bytes memory readData =
      abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals, quoteType);
    bytes memory targetData = abi.encode(maxPrice);
    vm.startPrank(governor);
    parallelizer.setOracle(
      collateral,
      abi.encode(
        OracleReadType.CHAINLINK_FEEDS, OracleReadType.MAX, readData, targetData, abi.encode(uint128(0), uint128(0))
      )
    );
    vm.stopPrank();
  }

  function _setSlippageTolerance(address collateral, uint256 tolerance) internal {
    vm.startPrank(governor);
    parallelizer.updateSlippageTolerance(collateral, tolerance);
    vm.stopPrank();
  }

  modifier swapSomeCollateralToTokenPAndUpdateOracleToMorphoOracle() {
    _swapSomeCollateralToTokenPAndUpdatOracleToMorphoOracle();
    _;
  }

  modifier updateOracleToMorphoOracle(uint256 newPrice) {
    MockMorphoOracle morphoOracle = new MockMorphoOracle(newPrice);
    OracleReadType readType = OracleReadType.MORPHO_ORACLE;
    OracleReadType targetType = OracleReadType.MAX;
    bytes memory readData = abi.encode(address(morphoOracle), 1);
    bytes memory targetData = abi.encode(newPrice);

    parallelizer.setOracle(
      address(eurA), abi.encode(readType, targetType, readData, targetData, abi.encode(uint128(0), uint128(0)))
    );

    _;
  }

  modifier updateSlippageToleranceTo1e7() {
    _setSlippageTolerance(address(eurA), 1e7);
    _;
  }

  modifier setSomeSurplus() {
    _swapSomeCollateralToTokenPAndUpdatOracleToMorphoOracle();
    vm.startPrank(governor);
    parallelizer.updateSlippageTolerance(address(eurA), 1e7);
    parallelizer.updateSurplusBufferRatio(uint64(BASE_9));
    parallelizer.processSurplus(address(eurA), 0);
    _;
  }

  modifier addReleasePayees() {
    _updateReleasePayees();
    _;
  }

  function _swapSomeCollateralToTokenPAndUpdatOracleToMorphoOracle() internal {
    vm.startPrank(guardian);
    // Update fees to 0
    uint64[] memory xMintFee = new uint64[](1);
    xMintFee[0] = uint64(0);
    int64[] memory yMintFee = new int64[](1);
    yMintFee[0] = int64(0);
    parallelizer.setFees(address(eurA), xMintFee, yMintFee, true);

    vm.startPrank(governor);
    // Swap some amount of eurA to tokenP
    uint256 amount = 10 * BASE_6;
    deal(address(eurA), address(governor), amount);
    eurA.approve(address(parallelizer), amount);
    parallelizer.swapExactInput(amount, 0, address(eurA), address(tokenP), governor, block.timestamp + 1 hours);

    // Update oracle to MorphoOracle and set price to 1.08$
    uint256 baseValue = 1.08e18; // 1.08$
    uint256 normalizationFactor = 0;
    MockMorphoOracle morphoOracle = new MockMorphoOracle(baseValue);
    OracleReadType readType = OracleReadType.MORPHO_ORACLE;
    OracleReadType targetType = OracleReadType.MAX;
    bytes memory readData = abi.encode(address(morphoOracle), 10 ** normalizationFactor);
    bytes memory targetData = abi.encode(baseValue);

    parallelizer.setOracle(
      address(eurA), abi.encode(readType, targetType, readData, targetData, abi.encode(uint128(0), uint128(0)))
    );
  }

  function _updateReleasePayees() internal {
    vm.startPrank(governor);
    address[] memory payees = new address[](2);
    payees[0] = address(0);
    payees[1] = address(treasury);
    uint256[] memory shares = new uint256[](2);
    shares[0] = 1 ether;
    shares[1] = 9 ether;
    parallelizer.updatePayees(payees, shares, false);
  }
}
