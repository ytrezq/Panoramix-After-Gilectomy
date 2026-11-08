// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import { AggregatorV3Interface } from "contracts/interfaces/external/chainlink/AggregatorV3Interface.sol";

import "contracts/utils/Constants.sol";
import "contracts/parallelizer/Storage.sol";
import { CollateralSetup, Fixture, IParallelizer, Test } from "../Fixture.sol";
import { Trader } from "./actors/Trader.t.sol";
import { Governance } from "./actors/Governance.t.sol";
import { MockChainlinkOracle } from "tests/mock/MockChainlinkOracle.sol";

//solhint-disable
import { console } from "@forge-std/console.sol";

contract SurplusInvariants is Fixture {
  uint256 internal constant _NUM_TRADER = 2;

  IParallelizer parallelizerSplit;

  Trader internal _traderHandler;
  Governance internal _governanceHandler;

  address[] internal _collaterals;
  AggregatorV3Interface[] internal _oracles;

  function setUp() public virtual override {
    super.setUp();

    _collaterals.push(address(eurA));
    _collaterals.push(address(eurB));
    _collaterals.push(address(eurY));
    _oracles.push(oracleA);
    _oracles.push(oracleB);
    _oracles.push(oracleY);

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
      AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
      uint32[] memory stalePeriods = new uint32[](1);
      uint8[] memory circuitChainIsMultiplied = new uint8[](1);
      uint8[] memory chainlinkDecimals = new uint8[](1);
      circuitChainlink[0] = oracleB;
      stalePeriods[0] = 1 hours;
      circuitChainIsMultiplied[0] = 1;
      chainlinkDecimals[0] = 8;
      OracleQuoteType quoteType = OracleQuoteType.UNIT;
      bytes memory readData =
        abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals, quoteType);
      bytes memory targetData = abi.encode(uint256(2e18));
      vm.startPrank(governor);
      parallelizer.setOracle(
        address(eurB),
        abi.encode(
          OracleReadType.CHAINLINK_FEEDS, OracleReadType.MAX, readData, targetData, abi.encode(uint128(0), uint128(0))
        )
      );
      vm.stopPrank();
    }

    vm.startPrank(governor);
    parallelizer.updateSlippageTolerance(address(eurA), 1e8);
    parallelizer.updateSlippageTolerance(address(eurB), 1e8);
    parallelizer.updateSlippageTolerance(address(eurY), 1e8);
    parallelizer.updateSurplusBufferRatio(uint64(BASE_9));
    vm.stopPrank();

    {
      vm.startPrank(governor);
      address[] memory payees = new address[](2);
      payees[0] = address(0);
      payees[1] = treasury;
      uint256[] memory shares = new uint256[](2);
      shares[0] = 1 ether;
      shares[1] = 9 ether;
      parallelizer.updatePayees(payees, shares, false);
      vm.stopPrank();
    }

    {
      vm.startPrank(guardian);
      uint64[] memory xMintFee = new uint64[](1);
      xMintFee[0] = uint64(0);
      int64[] memory yMintFee = new int64[](1);
      yMintFee[0] = int64(0);
      parallelizer.setFees(address(eurA), xMintFee, yMintFee, true);
      parallelizer.setFees(address(eurB), xMintFee, yMintFee, true);
      parallelizer.setFees(address(eurY), xMintFee, yMintFee, true);
      vm.stopPrank();

      _seedMint(address(eurA), 100 * BASE_6);
      _seedMint(address(eurB), 100 * 1e12);
      _seedMint(address(eurY), 100 * BASE_18);
    }

    // bump eurB oracle to create surplus, depeg eurA to bring CR close to 1.0
    MockChainlinkOracle(address(oracleB)).setLatestAnswer(int256(1.08e8));
    MockChainlinkOracle(address(oracleA)).setLatestAnswer(int256(0.95e8));

    _traderHandler = new Trader(parallelizer, parallelizerSplit, _collaterals, _oracles, _NUM_TRADER);
    _governanceHandler = new Governance(parallelizer, parallelizerSplit, _collaterals, _oracles);

    vm.startPrank(governor);
    accessManager.grantRole(GOVERNOR_ROLE, _governanceHandler.actors(0), 0);
    accessManager.grantRole(GUARDIAN_ROLE, _governanceHandler.actors(0), 0);
    accessManager.grantRole(KEEPER_ROLE, _governanceHandler.actors(0), 0);
    vm.stopPrank();

    for (uint256 i; i < _NUM_TRADER; i++) {
      vm.label(_traderHandler.actors(i), string.concat("Trader ", Strings.toString(i)));
    }

    targetContract(address(_traderHandler));
    targetContract(address(_governanceHandler));

    {
      bytes4[] memory selectors = new bytes4[](1);
      selectors[0] = Trader.swap.selector;
      targetSelector(FuzzSelector({ addr: address(_traderHandler), selectors: selectors }));
    }
    {
      bytes4[] memory selectors = new bytes4[](3);
      selectors[0] = Governance.updateOracle.selector;
      selectors[1] = Governance.processSurplus.selector;
      selectors[2] = Governance.release.selector;
      targetSelector(FuzzSelector({ addr: address(_governanceHandler), selectors: selectors }));
    }
  }

  function invariant_ProtocolSolvencyAfterSurplus() public view {
    assertFalse(
      _governanceHandler.surplusCausedUndercollateralization(),
      "SurplusInvariants: processSurplus must never leave CR < 1.0"
    );
  }

  function invariant_SurplusOnlyReportsExcess() public view {
    for (uint256 i; i < _collaterals.length; i++) {
      try parallelizer.getCollateralSurplus(_collaterals[i]) returns (uint256, uint256 stableSurplus) {
        (uint256 stablesFromCollateral,) = parallelizer.getIssuedByCollateral(_collaterals[i]);
        (,,,, uint256 redemptionPrice) = parallelizer.getOracleValues(_collaterals[i]);
        uint256 balance = IERC20(_collaterals[i]).balanceOf(address(parallelizer));
        uint8 decimals = IERC20Metadata(_collaterals[i]).decimals();
        uint256 totalCollateralValue = (redemptionPrice * balance) / (10 ** decimals);

        if (totalCollateralValue > stablesFromCollateral) {
          assertLe(
            stableSurplus,
            totalCollateralValue - stablesFromCollateral + 1e6,
            "SurplusInvariants: surplus exceeds excess collateral value"
          );
        }
      } catch { }
    }
  }

  function invariant_ReleaseIsProportional() public view {
    assertTrue(
      _governanceHandler.lastReleaseProportional(),
      "SurplusInvariants: release must distribute proportionally to shares"
    );
  }

  function _seedMint(address collateral, uint256 amount) internal {
    vm.startPrank(governor);
    deal(collateral, governor, amount);
    IERC20(collateral).approve(address(parallelizer), amount);
    parallelizer.swapExactInput(amount, 0, collateral, address(tokenP), governor, block.timestamp + 1 hours);
    vm.stopPrank();
  }
}
