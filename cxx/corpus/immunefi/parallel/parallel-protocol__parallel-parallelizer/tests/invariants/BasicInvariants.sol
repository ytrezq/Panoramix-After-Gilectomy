// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import { AggregatorV3Interface } from "contracts/interfaces/external/chainlink/AggregatorV3Interface.sol";
import { MockAccessControlManager } from "tests/mock/MockAccessControlManager.sol";

import "contracts/utils/Constants.sol";
import { CollateralSetup, Fixture, IParallelizer, Test } from "../Fixture.sol";
import { Trader } from "./actors/Trader.t.sol";
import { Arbitrager } from "./actors/Arbitrager.t.sol";
import { Governance } from "./actors/Governance.t.sol";

//solhint-disable
import { console } from "@forge-std/console.sol";

contract BasicInvariants is Fixture {
  uint256 internal constant _NUM_TRADER = 2;
  uint256 internal constant _NUM_ARB = 2;

  IParallelizer parallelizerSplit;

  Trader internal _traderHandler;
  Arbitrager internal _arbitragerHandler;
  Governance internal _governanceHandler;

  address[] internal _collaterals;
  AggregatorV3Interface[] internal _oracles;
  uint8[] internal _decimals;

  function setUp() public virtual override {
    super.setUp();

    // Deploy another parallelizer to check the independant path property
    config = address(new Test());
    parallelizerSplit = deployReplicaParallelizer(
      config,
      abi.encodeWithSelector(
        Test.initialize.selector,
        accessManager,
        tokenP,
        CollateralSetup(address(eurA), address(oracleA)),
        CollateralSetup(address(eurB), address(oracleB)),
        CollateralSetup(address(eurY), address(oracleY))
      )
    );

    vm.startPrank(governor);
    accessManager.setTargetFunctionRole(
      address(parallelizerSplit), getParallelizerGovernorSelectorAccess(), GOVERNOR_ROLE
    );
    accessManager.setTargetFunctionRole(
      address(parallelizerSplit), getParallelizerGuardianSelectorAccess(), GUARDIAN_ROLE
    );
    accessManager.setTargetFunctionRole(
      address(parallelizerSplit), getParallelizerKeeperSelectorAccess(), KEEPER_ROLE
    );
    vm.stopPrank();

    {
      // set redemption fees
      uint64[] memory xFeeRedemption = new uint64[](4);
      xFeeRedemption[0] = uint64(0);
      xFeeRedemption[1] = uint64(1e9 / 2);
      xFeeRedemption[2] = uint64((1e9 * 3) / 4);
      xFeeRedemption[3] = uint64(1e9);
      int64[] memory yFeeRedemption = new int64[](4);
      yFeeRedemption[0] = int64(int256(1e9));
      yFeeRedemption[1] = int64(int256(1e9));
      yFeeRedemption[2] = int64(int256((1e9 * 9) / 10));
      yFeeRedemption[3] = int64(int256(1e9));
      vm.startPrank(guardian);
      parallelizer.setRedemptionCurveParams(xFeeRedemption, yFeeRedemption);
      parallelizerSplit.setRedemptionCurveParams(xFeeRedemption, yFeeRedemption);
      vm.stopPrank();
    }

    _collaterals.push(address(eurA));
    _collaterals.push(address(eurB));
    _collaterals.push(address(eurY));
    _decimals.push(IERC20Metadata(address(eurA)).decimals());
    _decimals.push(IERC20Metadata(address(eurB)).decimals());
    _decimals.push(IERC20Metadata(address(eurY)).decimals());
    _oracles.push(oracleA);
    _oracles.push(oracleB);
    _oracles.push(oracleY);

    _traderHandler = new Trader(parallelizer, parallelizerSplit, _collaterals, _oracles, _NUM_TRADER);
    _arbitragerHandler = new Arbitrager(parallelizer, parallelizerSplit, _collaterals, _oracles, _NUM_ARB);
    _governanceHandler = new Governance(parallelizer, parallelizerSplit, _collaterals, _oracles);

    vm.startPrank(governor);
    accessManager.grantRole(GOVERNOR_ROLE, _governanceHandler.actors(0), 0);
    accessManager.grantRole(GUARDIAN_ROLE, _governanceHandler.actors(0), 0);
    vm.stopPrank();

    vm.startPrank(guardian);
    // Label newly created addresses
    vm.label(address(parallelizerSplit), "ParallelizerSplit");
    for (uint256 i; i < _NUM_ARB; i++) {
      vm.label(_arbitragerHandler.actors(i), string.concat("Arbi ", Strings.toString(i)));
    }
    for (uint256 i; i < _NUM_TRADER; i++) {
      vm.label(_traderHandler.actors(i), string.concat("Trader ", Strings.toString(i)));
    }

    targetContract(address(_traderHandler));
    targetContract(address(_arbitragerHandler));
    targetContract(address(_governanceHandler));

    {
      bytes4[] memory selectors = new bytes4[](1);
      selectors[0] = Trader.swap.selector;
      targetSelector(FuzzSelector({ addr: address(_traderHandler), selectors: selectors }));
    }

    {
      bytes4[] memory selectors = new bytes4[](2);
      selectors[0] = Arbitrager.swap.selector;
      selectors[1] = Arbitrager.redeem.selector;
      targetSelector(FuzzSelector({ addr: address(_arbitragerHandler), selectors: selectors }));
    }

    {
      bytes4[] memory selectors = new bytes4[](4);
      selectors[0] = Governance.updateOracle.selector;
      selectors[1] = Governance.updateRedemptionFees.selector;
      selectors[2] = Governance.updateBurnFees.selector;
      selectors[3] = Governance.updateMintFees.selector;
      targetSelector(FuzzSelector({ addr: address(_governanceHandler), selectors: selectors }));
    }
  }

  function systemState() public view {
    console.log("");
    console.log("SYSTEM STATE");
    console.log("");
    console.log("Calls summary:");
    console.log("-------------------");
    console.log("Trader:swap", _traderHandler.calls("swap"));
    console.log("Arbitrager:swap", _arbitragerHandler.calls("swap"));
    console.log("Arbitrager:redeem", _arbitragerHandler.calls("redeem"));
    console.log("oracle", _governanceHandler.calls("oracle"));
    console.log("Mint fees", _governanceHandler.calls("feeMint"));
    console.log("Burn fees", _governanceHandler.calls("feeBurn"));
    console.log("Redeem fees", _governanceHandler.calls("feeRedeem"));
    console.log("Increase time", _governanceHandler.calls("timestamp"));
    console.log("-------------------");
    console.log("");

    (uint256 issuedA, uint256 issued) = parallelizer.getIssuedByCollateral(address(eurA));
    (uint256 issuedB,) = parallelizer.getIssuedByCollateral(address(eurB));
    (uint256 issuedY,) = parallelizer.getIssuedByCollateral(address(eurY));
    console.log("Issued A: ", issuedA);
    console.log("Issued B: ", issuedB);
    console.log("Issued Y: ", issuedY);
    console.log("Issued Total: ", issued);
  }

  function invariant_IssuedCoherent() public {
    (uint256 issuedA, uint256 issued) = parallelizer.getIssuedByCollateral(address(eurA));
    (uint256 issuedB,) = parallelizer.getIssuedByCollateral(address(eurB));
    (uint256 issuedY,) = parallelizer.getIssuedByCollateral(address(eurY));
    assertApproxEqAbs(issued, issuedA + issuedB + issuedY, 3 wei);
  }

  function invariant_Supply() public {
    uint256 stablecoinIssued = parallelizer.getTotalIssued();
    uint256 stablecoinIssuedSplit = parallelizerSplit.getTotalIssued();

    uint256 balance;
    for (uint256 i = 0; i < _traderHandler.nbrActor(); i++) {
      balance += tokenP.balanceOf(_traderHandler.actors(i));
    }
    for (uint256 i = 0; i < _arbitragerHandler.nbrActor(); i++) {
      balance += tokenP.balanceOf(_arbitragerHandler.actors(i));
    }

    assertApproxEqAbs(stablecoinIssued + stablecoinIssuedSplit, balance, BASE_12);
  }

  function invariant_CollateralRatio() public {
    uint256 storedCollatRatio = _governanceHandler.collateralRatio();
    (uint64 collateralRatio,) = parallelizer.getCollateralRatio();
    if (storedCollatRatio <= BASE_9) {
      assertGe(uint256(collateralRatio), storedCollatRatio);
    }
    // if we have a collateral ratio above 100% and without fees, then a mint will decrease the collateral ratio
    // as it will become (a+c)/(b+c) with a>b
    // With fees it is less predictable, but in all cases the collateral ratio should not drop below over
    // collateralise = 100%
    else {
      assertGe(uint256(collateralRatio), BASE_9);
    }

    _governanceHandler.updateCollateralRatio(collateralRatio);
  }

  function invariant_RedeemCollateralRatio() public {
    uint256 storedCollatRatio = _governanceHandler.collateralRatio();
    (uint64 collateralRatio,) = parallelizer.getCollateralRatio();
    if (storedCollatRatio <= BASE_9) assertGe(collateralRatio, storedCollatRatio);
    else assertGe(collateralRatio, BASE_9);

    _governanceHandler.updateCollateralRatio(collateralRatio);
  }

  function invariant_MintReflexivity() public {
    uint256 stablecoinIssued = parallelizer.getTotalIssued();
    uint256 stableAmount;
    {
      // source of randomness
      (uint64 collateralRatio,) = parallelizer.getCollateralRatio();
      uint256 multiplier = bound(collateralRatio, 1, 1e4);
      stableAmount = stablecoinIssued > BASE_18 ? (stablecoinIssued * multiplier) / 1e2 : BASE_18;
    }
    for (uint256 i; i < _collaterals.length; i++) {
      uint256 amountIn = parallelizer.quoteOut(stableAmount, _collaterals[i], address(tokenP));
      uint256 reflexiveStableAmount = parallelizer.quoteIn(amountIn, _collaterals[i], address(tokenP));
      // If amountIn is small then do not check, as in the extreme case amountIn is null and
      // then reflexiveStableAmount is too
      if (amountIn < 10 ** (_decimals[i] - 2) || reflexiveStableAmount == 0) continue;
      assertApproxEqRelDecimal(stableAmount, reflexiveStableAmount, _MAX_PERCENTAGE_DEVIATION * 100, 18);
    }
  }

  function invariant_BurnReflexivity() public {
    uint256 stablecoinIssued = parallelizer.getTotalIssued();
    uint256 stableAmount;
    {
      // source of randomness
      (uint64 collateralRatio,) = parallelizer.getCollateralRatio();
      uint256 multiplier = bound(collateralRatio, 1, 1e2);
      stableAmount = (stablecoinIssued * multiplier) / 1e2;
    }
    if (stableAmount < 10 * BASE_18) return;
    for (uint256 i; i < _collaterals.length; i++) {
      try parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[i]) returns (uint256 amountOut) {
        uint256 reflexiveStableAmount = parallelizer.quoteOut(amountOut, address(tokenP), _collaterals[i]);
        // If amountOut is small then do not check, as in the extreme case amountIn is null and
        // then reflexiveStableAmount is too
        if (amountOut < 10 ** (_decimals[i] - 2) || reflexiveStableAmount == 0) continue;
        assertApproxEqRelDecimal(stableAmount, reflexiveStableAmount, _MAX_PERCENTAGE_DEVIATION * 500, 18);
      } catch { }
    }
  }

  // function invariantSystemState() public view {
  //     systemState();
  // }
}
