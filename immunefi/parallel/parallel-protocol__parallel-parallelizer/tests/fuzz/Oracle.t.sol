// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { stdError } from "@forge-std/Test.sol";

import { IParallelizerOracle, MockExternalOracle } from "../mock/MockExternalOracle.sol";
import { MockMorphoOracle } from "../mock/MockMorphoOracle.sol";
import "../Fixture.sol";
import "../utils/FunctionUtils.sol";
import "contracts/parallelizer/Storage.sol" as Storage;
import "contracts/utils/Errors.sol" as Errors;

contract OracleTest is Fixture, FunctionUtils {
  using SafeERC20 for IERC20;

  uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
  uint256 internal _minOracleValue = 10 ** 3; // 10**(-5)
  uint256 internal _maxOracleValue = BASE_18 / 100;
  uint256 internal _minWallet = 10 ** 18; // in base 18
  uint256 internal _maxWallet = 10 ** (18 + 12); // in base 18

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
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         TESTS                                                      
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function test_RevertWhen_OracleReadMintStale(
    uint256[3] memory latestOracleValue,
    uint32[3] memory newStalePeriods,
    uint256 elapseTimestamp,
    uint256 stableAmount,
    uint256 fromToken
  )
    public
  {
    // fr the stale periods in Chainlink
    elapseTimestamp = bound(elapseTimestamp, 1, 365 days);
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);

    _updateOracleValues(latestOracleValue);
    _updateOracleStalePeriods(newStalePeriods);
    skip(elapseTimestamp);

    if (newStalePeriods[fromToken] < elapseTimestamp) vm.expectRevert(Errors.InvalidChainlinkRate.selector);
    parallelizer.quoteOut(stableAmount, _collaterals[fromToken], address(tokenP));
  }

  function test_RevertWhen_OracleReadBurnStale(
    uint256[3] memory initialAmounts,
    uint256[3] memory latestOracleValue,
    uint32[3] memory newStalePeriods,
    uint256 elapseTimestamp,
    uint256 stableAmount,
    uint256 fromToken
  )
    public
  {
    // fr the stale periods in Chainlink
    elapseTimestamp = bound(elapseTimestamp, 1, 365 days);
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);

    _loadReserves(alice, alice, initialAmounts, 0);
    _updateOracleValues(latestOracleValue);
    uint256 minStalePeriod = _updateOracleStalePeriods(newStalePeriods);
    skip(elapseTimestamp);
    deal(_collaterals[fromToken], address(parallelizer), _maxTokenAmount[fromToken]);

    if (minStalePeriod < elapseTimestamp) vm.expectRevert(Errors.InvalidChainlinkRate.selector);
    parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]);
  }

  function test_RevertWhen_OracleReadRedemptionStale(
    uint256[3] memory initialAmounts,
    uint256[3] memory latestOracleValue,
    uint32[3] memory newStalePeriods,
    uint256 elapseTimestamp,
    uint256 stableAmount,
    uint256 fromToken
  )
    public
  {
    // fr the stale periods in Chainlink
    elapseTimestamp = bound(elapseTimestamp, 1, 365 days);
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);

    _loadReserves(alice, alice, initialAmounts, 0);
    _updateOracleValues(latestOracleValue);
    uint256 minStalePeriod = _updateOracleStalePeriods(newStalePeriods);
    skip(elapseTimestamp);

    if (minStalePeriod < elapseTimestamp) vm.expectRevert(Errors.InvalidChainlinkRate.selector);
    parallelizer.getCollateralRatio();
  }

  function test_RevertWhen_OracleTargetStale(
    uint256[3] memory initialAmounts,
    uint256[3] memory latestOracleValue,
    uint32[3] memory newStalePeriods,
    uint256 elapseTimestamp,
    uint256 stableAmount,
    uint256 fromToken
  )
    public
  {
    // fr the stale periods in Chainlink
    elapseTimestamp = bound(elapseTimestamp, 1, 365 days);
    fromToken = bound(fromToken, 0, _collaterals.length - 1);
    stableAmount = bound(stableAmount, 2, _maxAmountWithoutDecimals * BASE_18);

    _loadReserves(alice, alice, initialAmounts, 0);
    _updateOracleValues(latestOracleValue);
    uint256 minStalePeriod = _updateTargetOracleStalePeriods(newStalePeriods);
    skip(elapseTimestamp);

    if (minStalePeriod < elapseTimestamp) vm.expectRevert(Errors.InvalidChainlinkRate.selector);
    parallelizer.getCollateralRatio();

    deal(_collaterals[fromToken], address(parallelizer), _maxTokenAmount[fromToken]);

    if (minStalePeriod < elapseTimestamp) vm.expectRevert(Errors.InvalidChainlinkRate.selector);
    parallelizer.quoteIn(stableAmount, address(tokenP), _collaterals[fromToken]);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       GETORACLE                                                    
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_GetOracle(
    uint8[3] memory newChainlinkDecimals,
    uint8[3] memory newCircuitChainIsMultiplied,
    uint8[3] memory newQuoteType,
    uint8[3] memory newReadType,
    uint8[3] memory newTargetType,
    uint256[4] memory latestExchangeRateStakeETH
  )
    public
  {
    for (uint256 i; i < _collaterals.length; i++) {
      bytes memory oracleData;
      bytes memory targetData;
      {
        Storage.OracleReadType readType;
        Storage.OracleReadType targetType;
        uint256 userFirewall;
        uint256 burnFirewall;
        {
          bytes memory hyperparameters;
          (readType, targetType, oracleData, targetData, hyperparameters) =
            parallelizer.getOracle(address(_collaterals[i]));
          (userFirewall, burnFirewall) = abi.decode(hyperparameters, (uint128, uint128));
        }

        assertEq(uint256(readType), uint256(Storage.OracleReadType.CHAINLINK_FEEDS));
        assertEq(uint256(targetType), uint256(Storage.OracleReadType.STABLE));
        assertEq(userFirewall, 0);
        assertEq(burnFirewall, 0);
      }

      (
        AggregatorV3Interface[] memory circuitChainlink,
        uint32[] memory stalePeriods,
        uint8[] memory circuitChainIsMultiplied,
        uint8[] memory chainlinkDecimals,
        Storage.OracleQuoteType quoteType
      ) = abi.decode(oracleData, (AggregatorV3Interface[], uint32[], uint8[], uint8[], Storage.OracleQuoteType));
      assertEq(circuitChainlink.length, 1);
      assertEq(circuitChainIsMultiplied.length, 1);
      assertEq(chainlinkDecimals.length, 1);
      assertEq(stalePeriods.length, 1);
      assertEq(address(circuitChainlink[0]), address(_oracles[i]));
      assertEq(circuitChainIsMultiplied[0], 1);
      assertEq(chainlinkDecimals[0], 8);
      assertEq(uint256(quoteType), uint256(Storage.OracleQuoteType.UNIT));
    }

    _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
    address[] memory externalOracles =
      _updateOracles(newChainlinkDecimals, newCircuitChainIsMultiplied, newQuoteType, newReadType, newTargetType);

    for (uint256 i; i < _collaterals.length; i++) {
      {
        bytes memory data;
        {
          bytes memory targetData;
          Storage.OracleReadType readType;
          Storage.OracleReadType targetType;
          (readType, targetType, data, targetData,) = parallelizer.getOracle(address(_collaterals[i]));

          assertEq(uint8(readType), newReadType[i]);
          assertEq(uint8(targetType), newTargetType[i]);
        }
        if (newReadType[i] == 1) {
          IParallelizerOracle externalOracle = abi.decode(data, (IParallelizerOracle));
          assertEq(address(externalOracle), externalOracles[i]);
        } else {
          (
            AggregatorV3Interface[] memory circuitChainlink,
            uint32[] memory stalePeriods,
            uint8[] memory circuitChainIsMultiplied,
            uint8[] memory chainlinkDecimals,
            Storage.OracleQuoteType quoteType
          ) = abi.decode(data, (AggregatorV3Interface[], uint32[], uint8[], uint8[], Storage.OracleQuoteType));
          assertEq(circuitChainlink.length, 1);
          assertEq(circuitChainIsMultiplied.length, 1);
          assertEq(chainlinkDecimals.length, 1);
          assertEq(stalePeriods.length, 1);
          assertEq(address(circuitChainlink[0]), address(_oracles[i]));
          assertEq(circuitChainIsMultiplied[0], newCircuitChainIsMultiplied[i]);
          assertEq(chainlinkDecimals[0], newChainlinkDecimals[i]);
          assertEq(uint8(quoteType), newQuoteType[i]);
        }
      }

      if (newTargetType[i] == 0) {
        bytes memory targetData;
        (,,, targetData,) = parallelizer.getOracle(address(_collaterals[i]));
        (
          AggregatorV3Interface[] memory circuitChainlink,
          uint32[] memory stalePeriods,
          uint8[] memory circuitChainIsMultiplied,
          uint8[] memory chainlinkDecimals,
          Storage.OracleQuoteType quoteType
        ) = abi.decode(targetData, (AggregatorV3Interface[], uint32[], uint8[], uint8[], Storage.OracleQuoteType));
        assertEq(circuitChainlink.length, 1);
        assertEq(circuitChainIsMultiplied.length, 1);
        assertEq(chainlinkDecimals.length, 1);
        assertEq(stalePeriods.length, 1);
        assertEq(address(circuitChainlink[0]), address(_oracles[i]));
        assertEq(circuitChainIsMultiplied[0], newCircuitChainIsMultiplied[i]);
        assertEq(chainlinkDecimals[0], newChainlinkDecimals[i]);
        assertEq(uint8(quoteType), newQuoteType[i]);
      }
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    READREDEMPTION                                                  
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_OracleReadRedemption_Success(
    uint8[3] memory newChainlinkDecimals,
    uint8[3] memory newCircuitChainIsMultiplied,
    uint8[3] memory newQuoteType,
    uint8[3] memory newReadType,
    uint8[3] memory newTargetType,
    uint256[3] memory latestOracleValue,
    uint256[4] memory latestExchangeRateStakeETH
  )
    public
  {
    _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
    _updateOracleValues(latestOracleValue);
    _updateOracles(newChainlinkDecimals, newCircuitChainIsMultiplied, newQuoteType, newReadType, newTargetType);

    for (uint256 i; i < _collaterals.length; i++) {
      (,,,, uint256 redemption) = parallelizer.getOracleValues(address(_collaterals[i]));
      uint256 oracleRedemption;
      uint256 targetPrice;
      if (newTargetType[i] == 0) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        targetPrice = newCircuitChainIsMultiplied[i] == 1
          ? (BASE_18 * uint256(value)) / 10 ** (newChainlinkDecimals[i])
          : (BASE_18 * 10 ** (newChainlinkDecimals[i])) / uint256(value);
      } else if (newTargetType[i] == 1 || newTargetType[i] == 2 || newTargetType[i] == 3) {
        targetPrice = BASE_18;
      } else {
        targetPrice = latestExchangeRateStakeETH[newTargetType[i] - 4];
      }

      uint256 quoteAmount = newQuoteType[i] == 0 ? BASE_18 : targetPrice;

      if (newReadType[i] == 0) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        oracleRedemption = newCircuitChainIsMultiplied[i] == 1
          ? (quoteAmount * uint256(value)) / 10 ** (newChainlinkDecimals[i])
          : (quoteAmount * 10 ** (newChainlinkDecimals[i])) / uint256(value);
      } else if (newReadType[i] == 1) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        oracleRedemption = uint256(value) * 1e12;
      } else if (newReadType[i] == 2) {
        oracleRedemption = targetPrice;
      } else if (newReadType[i] == 3) {
        oracleRedemption = BASE_18;
      } else {
        oracleRedemption = latestExchangeRateStakeETH[newReadType[i] - 4];
      }
      assertEq(redemption, oracleRedemption);
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       READMINT                                                     
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_OracleReadMint_Success(
    uint8[3] memory newChainlinkDecimals,
    uint8[3] memory newCircuitChainIsMultiplied,
    uint8[3] memory newQuoteType,
    uint8[3] memory newReadType,
    uint8[3] memory newTargetType,
    uint256[3] memory latestOracleValue,
    uint256[4] memory latestExchangeRateStakeETH
  )
    public
  {
    _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
    _updateOracleValues(latestOracleValue);
    _updateOracles(newChainlinkDecimals, newCircuitChainIsMultiplied, newQuoteType, newReadType, newTargetType);

    for (uint256 i; i < _collaterals.length; i++) {
      (uint256 mint,,,,) = parallelizer.getOracleValues(address(_collaterals[i]));
      uint256 oracleMint;
      uint256 targetPrice;
      if (newTargetType[i] == 0) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        targetPrice = newCircuitChainIsMultiplied[i] == 1
          ? (BASE_18 * uint256(value)) / 10 ** (newChainlinkDecimals[i])
          : (BASE_18 * 10 ** (newChainlinkDecimals[i])) / uint256(value);
      } else if (newTargetType[i] == 1 || newTargetType[i] == 2 || newTargetType[i] == 3) {
        targetPrice = BASE_18;
      } else {
        targetPrice = latestExchangeRateStakeETH[newTargetType[i] - 4];
      }

      uint256 quoteAmount = newQuoteType[i] == 0 ? BASE_18 : targetPrice;

      if (newReadType[i] == 0) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        oracleMint = newCircuitChainIsMultiplied[i] == 1
          ? (quoteAmount * uint256(value)) / 10 ** (newChainlinkDecimals[i])
          : (quoteAmount * 10 ** (newChainlinkDecimals[i])) / uint256(value);
      } else if (newReadType[i] == 1) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        oracleMint = uint256(value) * 1e12;
      } else if (newReadType[i] == 2) {
        oracleMint = targetPrice;
      } else if (newReadType[i] == 3) {
        oracleMint = BASE_18;
      } else {
        oracleMint = latestExchangeRateStakeETH[newReadType[i] - 4];
      }

      if (newReadType[i] != 1 && targetPrice < oracleMint) oracleMint = targetPrice;
      assertEq(mint, oracleMint);
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       READBURN                                                     
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_OracleReadBurn_Success(
    uint8[3] memory newChainlinkDecimals,
    uint8[3] memory newCircuitChainIsMultiplied,
    uint8[3] memory newQuoteType,
    uint8[3] memory newReadType,
    uint8[3] memory newTargetType,
    uint256[3] memory latestOracleValue,
    uint256[4] memory latestExchangeRateStakeETH
  )
    public
  {
    _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
    _updateOracleValues(latestOracleValue);
    _updateOracles(newChainlinkDecimals, newCircuitChainIsMultiplied, newQuoteType, newReadType, newTargetType);

    uint256 minDeviation;
    uint256 minRatio;
    for (uint256 i; i < _collaterals.length; i++) {
      uint256 burn;
      uint256 deviation;
      (, burn, deviation, minRatio,) = parallelizer.getOracleValues(address(_collaterals[i]));
      if (i == 0) minDeviation = deviation;
      if (deviation < minDeviation) minDeviation = deviation;

      uint256 targetPrice;
      if (newTargetType[i] == 0) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        targetPrice = newCircuitChainIsMultiplied[i] == 1
          ? (BASE_18 * uint256(value)) / 10 ** (newChainlinkDecimals[i])
          : (BASE_18 * 10 ** (newChainlinkDecimals[i])) / uint256(value);
      } else if (newTargetType[i] == 1 || newTargetType[i] == 2 || newTargetType[i] == 3) {
        targetPrice = BASE_18;
      } else {
        targetPrice = latestExchangeRateStakeETH[newTargetType[i] - 4];
      }

      uint256 oracleBurn;
      if (newReadType[i] == 0) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        if (newQuoteType[i] == 0) {
          if (newCircuitChainIsMultiplied[i] == 1) {
            oracleBurn = (BASE_18 * uint256(value)) / 10 ** (newChainlinkDecimals[i]);
          } else {
            oracleBurn = (BASE_18 * 10 ** (newChainlinkDecimals[i])) / uint256(value);
          }
        } else {
          if (newCircuitChainIsMultiplied[i] == 1) {
            oracleBurn = (targetPrice * uint256(value)) / 10 ** (newChainlinkDecimals[i]);
          } else {
            oracleBurn = (targetPrice * 10 ** (newChainlinkDecimals[i])) / uint256(value);
          }
        }
      } else if (newReadType[i] == 1) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        oracleBurn = uint256(value) * 1e12;
      } else if (newReadType[i] == 2) {
        oracleBurn = targetPrice;
      } else if (newReadType[i] == 3) {
        oracleBurn = BASE_18;
      } else {
        oracleBurn = latestExchangeRateStakeETH[newReadType[i] - 4];
      }

      {
        uint256 oracleDeviation = BASE_18;
        if (newReadType[i] != 1 && targetPrice > oracleBurn) {
          oracleDeviation = (oracleBurn * BASE_18) / targetPrice;
        }
        assertEq(deviation, oracleDeviation);
      }
      assertEq(burn, oracleBurn);
    }
    assertEq(minDeviation, minRatio);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        MORPHO                                                      
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_ReadMorphoFeed(uint256[3] memory baseValues, uint256[3] memory normalizers) public {
    vm.startPrank(governor);
    for (uint256 i; i < _collaterals.length; i++) {
      baseValues[i] = uint256(bound(baseValues[i], 100, 1e5));
      normalizers[i] = uint256(bound(normalizers[i], 1, 18));
      MockMorphoOracle morphoOracle = new MockMorphoOracle(baseValues[i] * 1e36);
      {
        Storage.OracleReadType readType = Storage.OracleReadType.MORPHO_ORACLE;
        Storage.OracleReadType targetType = Storage.OracleReadType.MAX;
        bytes memory readData = abi.encode(address(morphoOracle), 10 ** normalizers[i]);
        bytes memory targetData = abi.encode((baseValues[i] * 1e36) / 10 ** normalizers[i]);
        parallelizer.setOracle(
          _collaterals[i], abi.encode(readType, targetType, readData, targetData, abi.encode(uint128(0), uint128(0)))
        );
      }
      (uint256 mint, uint256 burn, uint256 ratio, uint256 minRatio, uint256 redemption) =
        parallelizer.getOracleValues(address(_collaterals[i]));
      assertEq(mint, (baseValues[i] * 1e36) / 10 ** normalizers[i]);
      assertEq(burn, (baseValues[i] * 1e36) / 10 ** normalizers[i]);
      assertEq(ratio, BASE_18);
      assertEq(minRatio, BASE_18);
      assertEq(redemption, (baseValues[i] * 1e36) / 10 ** normalizers[i]);
      if (i == 2) {
        morphoOracle.setValue((baseValues[i] * 1e36 * 9) / 10);
        (mint, burn, ratio, minRatio, redemption) = parallelizer.getOracleValues(address(_collaterals[i]));
        assertEq(mint, ((baseValues[i] * 1e36) * 9) / 10 ** normalizers[i] / 10);
        assertEq(burn, ((baseValues[i] * 1e36) * 9) / 10 ** normalizers[i] / 10);
        assertEq(ratio, (BASE_18 * 9) / 10);
        assertEq(minRatio, (BASE_18 * 9) / 10);
        assertEq(redemption, ((baseValues[i] * 1e36) * 9) / 10 ** normalizers[i] / 10);
      }
    }
    vm.stopPrank();
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       FIREWALL                                                     
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_OracleReadMint_WithFirewall_Success(
    uint8[3] memory newChainlinkDecimals,
    uint8[3] memory newCircuitChainIsMultiplied,
    uint8[3] memory newQuoteType,
    uint8[3] memory newReadType,
    uint8[3] memory newTargetType,
    uint128[6] memory userAndBurnFirewall,
    uint256[3] memory latestOracleValue,
    uint256[4] memory latestExchangeRateStakeETH
  )
    public
  {
    _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
    _updateOracleValues(latestOracleValue);
    _updateOracles(newChainlinkDecimals, newCircuitChainIsMultiplied, newQuoteType, newReadType, newTargetType);
    userAndBurnFirewall = _updateOracleFirewalls(userAndBurnFirewall);

    for (uint256 i; i < _collaterals.length; i++) {
      (uint256 mint,,,,) = parallelizer.getOracleValues(address(_collaterals[i]));
      uint256 oracleMint;
      uint256 targetPrice;
      if (newTargetType[i] == 0) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        targetPrice = newCircuitChainIsMultiplied[i] == 1
          ? (BASE_18 * uint256(value)) / 10 ** (newChainlinkDecimals[i])
          : (BASE_18 * 10 ** (newChainlinkDecimals[i])) / uint256(value);
      } else if (newTargetType[i] == 1 || newTargetType[i] == 2 || newTargetType[i] == 3) {
        targetPrice = BASE_18;
      } else {
        targetPrice = latestExchangeRateStakeETH[newTargetType[i] - 4];
      }

      uint256 quoteAmount = newQuoteType[i] == 0 ? BASE_18 : targetPrice;

      if (newReadType[i] == 0) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        oracleMint = newCircuitChainIsMultiplied[i] == 1
          ? (quoteAmount * uint256(value)) / 10 ** (newChainlinkDecimals[i])
          : (quoteAmount * 10 ** (newChainlinkDecimals[i])) / uint256(value);
      } else if (newReadType[i] == 1) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        oracleMint = uint256(value) * 1e12;
      } else if (newReadType[i] == 2) {
        oracleMint = targetPrice;
      } else if (newReadType[i] == 3) {
        oracleMint = BASE_18;
      } else {
        oracleMint = latestExchangeRateStakeETH[newReadType[i] - 4];
      }

      if (newReadType[i] != 1) {
        if (
          targetPrice * (BASE_18 - userAndBurnFirewall[i]) < oracleMint * BASE_18
            && targetPrice * (BASE_18 + userAndBurnFirewall[i]) > oracleMint * BASE_18
        ) oracleMint = targetPrice;
        if (targetPrice < oracleMint) oracleMint = targetPrice;
      }
      assertEq(mint, oracleMint);
    }
  }

  function testFuzz_OracleReadBurn_WithFirewall_Success(
    uint8[3] memory newCircuitChainIsMultiplied,
    uint8[3] memory newQuoteType,
    uint8[3] memory newReadType,
    uint8[3] memory newTargetType,
    uint128[6] memory userAndBurnFirewall,
    uint256[3] memory latestOracleValue,
    uint256[4] memory latestExchangeRateStakeETH
  )
    public
  {
    _updateStakeETHExchangeRates(latestExchangeRateStakeETH);
    _updateOracleValues(latestOracleValue);
    {
      uint8[3] memory newChainlinkDecimals = [8, 8, 8];
      _updateOracles(newChainlinkDecimals, newCircuitChainIsMultiplied, newQuoteType, newReadType, newTargetType);
    }
    userAndBurnFirewall = _updateOracleFirewalls(userAndBurnFirewall);

    uint256 minDeviation;
    uint256 minRatio;
    for (uint256 i; i < _collaterals.length; i++) {
      uint256 burn;
      uint256 deviation;
      (, burn, deviation, minRatio,) = parallelizer.getOracleValues(address(_collaterals[i]));
      if (i == 0) minDeviation = deviation;
      if (deviation < minDeviation) minDeviation = deviation;

      uint256 targetPrice;
      if (newTargetType[i] == 0) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        targetPrice = newCircuitChainIsMultiplied[i] == 1
          ? (BASE_18 * uint256(value)) / 10 ** 8
          : (BASE_18 * 10 ** 8) / uint256(value);
      } else if (newTargetType[i] == 1 || newTargetType[i] == 2 || newTargetType[i] == 3) {
        targetPrice = BASE_18;
      } else {
        targetPrice = latestExchangeRateStakeETH[newTargetType[i] - 4];
      }

      uint256 oracleBurn;
      if (newReadType[i] == 0) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        if (newQuoteType[i] == 0) {
          if (newCircuitChainIsMultiplied[i] == 1) {
            oracleBurn = (BASE_18 * uint256(value)) / 10 ** 8;
          } else {
            oracleBurn = (BASE_18 * 10 ** 8) / uint256(value);
          }
        } else {
          if (newCircuitChainIsMultiplied[i] == 1) {
            oracleBurn = (targetPrice * uint256(value)) / 10 ** 8;
          } else {
            oracleBurn = (targetPrice * 10 ** 8) / uint256(value);
          }
        }
      } else if (newReadType[i] == 1) {
        (, int256 value,,,) = _oracles[i].latestRoundData();
        oracleBurn = uint256(value) * 1e12;
      } else if (newReadType[i] == 2) {
        oracleBurn = targetPrice;
      } else if (newReadType[i] == 3) {
        oracleBurn = BASE_18;
      } else {
        oracleBurn = latestExchangeRateStakeETH[newReadType[i] - 4];
      }

      {
        uint256 oracleDeviation = BASE_18;
        if (newReadType[i] != 1) {
          if (
            targetPrice * (BASE_18 - userAndBurnFirewall[i]) < oracleBurn * BASE_18
              && targetPrice * (BASE_18 + userAndBurnFirewall[i]) > oracleBurn * BASE_18
          ) oracleBurn = targetPrice;
          if (oracleBurn * BASE_18 < targetPrice * (BASE_18 - userAndBurnFirewall[i + 3])) {
            oracleDeviation = (oracleBurn * BASE_18) / targetPrice;
          } else if (oracleBurn < targetPrice) {
            oracleBurn = targetPrice;
          }
          assertEq(deviation, oracleDeviation);
        }
      }
      assertEq(burn, oracleBurn);
    }
    assertEq(minDeviation, minRatio);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 UPDATE ORACLE STORAGE                                              
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function testFuzz_revertWhen_updateOracle_NotAuthorized() public {
    vm.startPrank(alice);
    vm.expectRevert(Errors.NotTrusted.selector);
    parallelizer.updateOracle(_collaterals[0]);
  }

  function testFuzz_revertWhen_updateOracle_NotACollateral(address fakeCollat) public {
    for (uint256 i; i < _collaterals.length; i++) {
      vm.assume(fakeCollat != _collaterals[i]);
    }
    vm.prank(governor);
    parallelizer.toggleTrusted(alice, Storage.TrustedType.Seller);

    vm.prank(alice);
    vm.expectRevert(Errors.NotCollateral.selector);
    parallelizer.updateOracle(fakeCollat);
  }

  function testFuzz_revertWhen_updateOracle_NotMax() public {
    vm.prank(governor);
    parallelizer.toggleTrusted(alice, Storage.TrustedType.Seller);

    (,,, bytes memory targetData,) = parallelizer.getOracle(_collaterals[0]);
    assertEq(targetData.length, 0);

    vm.prank(alice);
    vm.expectRevert(Errors.OracleUpdateFailed.selector);
    parallelizer.updateOracle(_collaterals[0]);
  }

  function testFuzz_revertWhen_updateOracle_NoUpdate() public {
    vm.prank(governor);
    parallelizer.toggleTrusted(alice, Storage.TrustedType.Seller);

    address collateral = _collaterals[0];

    (
      Storage.OracleReadType readType,
      Storage.OracleReadType targetType,
      bytes memory data,
      bytes memory targetData,
      bytes memory hyperparameters
    ) = parallelizer.getOracle(address(collateral));
    (uint256 oracleValue,,,,) = parallelizer.getOracleValues(collateral);

    vm.prank(governor);
    parallelizer.setOracle(
      collateral, abi.encode(readType, Storage.OracleReadType.MAX, data, abi.encode(oracleValue), hyperparameters)
    );

    vm.prank(alice);
    vm.expectRevert(Errors.OracleUpdateFailed.selector);
    parallelizer.updateOracle(collateral);
  }

  function test_revertWhen_updateOracle_AboveRatchetStep() public {
    vm.prank(governor);
    parallelizer.toggleTrusted(alice, Storage.TrustedType.Seller);

    address collateral = _collaterals[0];
    (Storage.OracleReadType readType,, bytes memory data,,) = parallelizer.getOracle(collateral);
    (uint256 oracleValue,,,,) = parallelizer.getOracleValues(collateral);

    vm.prank(governor);
    bytes memory hyperparameters = abi.encode(uint128(0), uint128(0));
    parallelizer.setOracle(
      collateral,
      abi.encode(readType, Storage.OracleReadType.MAX, data, abi.encode(oracleValue), hyperparameters)
    );

    (, int256 currentValue,,,) = _oracles[0].latestRoundData();
    // One wei above the largest increase a single ratchet may apply
    uint256 aboveCap = (uint256(currentValue) * (BASE_18 + MAX_ORACLE_RATCHET_STEP)) / BASE_18 + 1;
    MockChainlinkOracle(address(_oracles[0])).setLatestAnswer(int256(aboveCap));

    vm.prank(alice);
    vm.expectRevert(Errors.OracleUpdateFailed.selector);
    parallelizer.updateOracle(collateral);
  }

  function test_updateOracle_CannotLiftATargetLeftAtZero() public {
    vm.prank(governor);
    parallelizer.toggleTrusted(alice, Storage.TrustedType.Seller);

    address collateral = _collaterals[0];
    (Storage.OracleReadType readType,, bytes memory data,,) = parallelizer.getOracle(collateral);

    // A MAX target seeded with 0, which is what the deployment script encoded before the initializer seeded spot
    vm.prank(governor);
    parallelizer.setOracle(
      collateral,
      abi.encode(
        readType, Storage.OracleReadType.MAX, data, abi.encode(uint256(0)), abi.encode(uint128(0), uint128(0))
      )
    );

    // Every positive spot is above 0 by more than the ratchet step, so the target can never be raised
    vm.prank(alice);
    vm.expectRevert(Errors.OracleUpdateFailed.selector);
    parallelizer.updateOracle(collateral);
  }

  function testFuzz_updateOracle_Success(uint256 updateOracleValue, uint32 heartbeat) public {
    vm.prank(governor);
    parallelizer.toggleTrusted(alice, Storage.TrustedType.Seller);

    uint256 indexCollat = 0;
    address collateral = _collaterals[indexCollat];

    {
      (Storage.OracleReadType readType,, bytes memory data,,) = parallelizer.getOracle(address(collateral));
      (uint256 oracleValue,,,,) = parallelizer.getOracleValues(collateral);

      vm.prank(governor);
      parallelizer.setOracle(
        collateral,
        abi.encode(
          readType, Storage.OracleReadType.MAX, data, abi.encode(oracleValue), abi.encode(uint128(0), uint128(0))
        )
      );
    }

    vm.warp(block.timestamp + heartbeat);

    // Update the oracles
    uint256 newOracleValue;
    {
      (, int256 oracleValueTmp,,,) = _oracles[indexCollat].latestRoundData();
      uint256 currentValue = uint256(oracleValueTmp);
      // A single ratchet cannot lift the target by more than `MAX_ORACLE_RATCHET_STEP`
      uint256 upperBound = (currentValue * (BASE_18 + MAX_ORACLE_RATCHET_STEP)) / BASE_18;
      if (upperBound > _maxOracleValue) upperBound = _maxOracleValue;
      uint256 lowerBound = currentValue + 1;
      if (lowerBound < _minOracleValue * 10) lowerBound = _minOracleValue * 10;
      if (lowerBound > upperBound) return;
      updateOracleValue = bound(updateOracleValue, lowerBound, upperBound);

      uint256[3] memory latestOracleValue = [updateOracleValue, BASE_8, BASE_8];
      latestOracleValue = _updateOracleValues(latestOracleValue);
      newOracleValue = latestOracleValue[indexCollat];
    }

    vm.prank(alice);
    parallelizer.updateOracle(collateral);

    (,,, bytes memory targetData,) = parallelizer.getOracle(address(collateral));
    uint256 maxValue = abi.decode(targetData, (uint256));

    assertEq(maxValue, (newOracleValue * BASE_18) / BASE_8);
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
        parallelizer.swapExactInput(initialAmounts[i], 0, _collaterals[i], address(tokenP), owner, block.timestamp * 2);
      mintedStables += collateralMintedStables[i];
    }

    // Send a proportion of these to another account user just to complexify the case
    transferProportion = bound(transferProportion, 0, BASE_9);
    if (receiver != address(0)) tokenP.transfer(receiver, (mintedStables * transferProportion) / BASE_9);
    vm.stopPrank();
  }

  function _getReadType(uint8 newReadType) internal pure returns (Storage.OracleReadType readType) {
    readType = newReadType == 0
      ? Storage.OracleReadType.CHAINLINK_FEEDS
      : newReadType == 1
        ? Storage.OracleReadType.EXTERNAL
        : newReadType == 2
          ? Storage.OracleReadType.NO_ORACLE
          : newReadType == 3
            ? Storage.OracleReadType.STABLE
            : newReadType == 4
              ? Storage.OracleReadType.WSTETH
              : newReadType == 5
                ? Storage.OracleReadType.CBETH
                : newReadType == 6 ? Storage.OracleReadType.RETH : Storage.OracleReadType.SFRXETH;
  }

  function _updateOracles(
    uint8[3] memory newChainlinkDecimals,
    uint8[3] memory newCircuitChainIsMultiplied,
    uint8[3] memory newQuoteType,
    uint8[3] memory newReadType,
    uint8[3] memory newTargetType
  )
    internal
    returns (address[] memory externalOracles)
  {
    externalOracles = new address[](3);
    vm.startPrank(governor);
    for (uint256 i; i < _collaterals.length; i++) {
      newChainlinkDecimals[i] = uint8(bound(newChainlinkDecimals[i], 2, 18));
      newCircuitChainIsMultiplied[i] = uint8(bound(newCircuitChainIsMultiplied[i], 0, 1));
      newQuoteType[i] = uint8(bound(newQuoteType[i], 0, 1));
      newReadType[i] = uint8(bound(newReadType[i], 0, 7));
      newTargetType[i] = uint8(bound(newTargetType[i], 0, 7));

      Storage.OracleReadType readType = _getReadType(newReadType[i]);
      Storage.OracleReadType targetType = _getReadType(newTargetType[i]);

      Storage.OracleQuoteType quoteType =
        newQuoteType[i] == 0 ? Storage.OracleQuoteType.UNIT : Storage.OracleQuoteType.TARGET;

      bytes memory readData;
      bytes memory targetData;
      if (readType == Storage.OracleReadType.EXTERNAL) {
        MockExternalOracle newOracle = new MockExternalOracle(_oracles[i]);
        externalOracles[i] = address(newOracle);
        readData = abi.encode(IParallelizerOracle(address(externalOracles[i])));
      }
      {
        AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
        uint32[] memory stalePeriods = new uint32[](1);
        uint8[] memory circuitChainIsMultiplied = new uint8[](1);
        uint8[] memory chainlinkDecimals = new uint8[](1);
        circuitChainlink[0] = AggregatorV3Interface(_oracles[i]);
        stalePeriods[0] = 1 hours;
        circuitChainIsMultiplied[0] = newCircuitChainIsMultiplied[i];
        chainlinkDecimals[0] = newChainlinkDecimals[i];
        bytes memory data =
          abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals, quoteType);
        if (readType != Storage.OracleReadType.EXTERNAL) readData = data;
        if (targetType == Storage.OracleReadType.CHAINLINK_FEEDS) targetData = data;
      }
      parallelizer.setOracle(
        _collaterals[i], abi.encode(readType, targetType, readData, targetData, abi.encode(uint128(0), uint128(0)))
      );
    }
    vm.stopPrank();
  }

  function _updateOracleValues(uint256[3] memory latestOracleValue) internal returns (uint256[3] memory) {
    for (uint256 i; i < _collaterals.length; i++) {
      latestOracleValue[i] = bound(latestOracleValue[i], _minOracleValue * 10, _maxOracleValue);
      MockChainlinkOracle(address(_oracles[i])).setLatestAnswer(int256(latestOracleValue[i]));
    }
    return latestOracleValue;
  }

  function _updateStakeETHExchangeRates(uint256[4] memory latestExchangeRateStakeETH) internal {
    for (uint256 i; i < latestExchangeRateStakeETH.length; i++) {
      latestExchangeRateStakeETH[i] = bound(latestExchangeRateStakeETH[i], _minOracleValue * BASE_12, BASE_27);
    }
    vm.mockCall(
      address(STETH),
      abi.encodeWithSelector(IStETH.getPooledEthByShares.selector),
      abi.encode(latestExchangeRateStakeETH[0])
    );
    vm.mockCall(
      address(CBETH), abi.encodeWithSelector(ICbETH.exchangeRate.selector), abi.encode(latestExchangeRateStakeETH[1])
    );
    vm.mockCall(
      address(RETH), abi.encodeWithSelector(IRETH.getExchangeRate.selector), abi.encode(latestExchangeRateStakeETH[2])
    );
    vm.mockCall(
      address(SFRXETH),
      abi.encodeWithSelector(ISfrxETH.pricePerShare.selector),
      abi.encode(latestExchangeRateStakeETH[3])
    );
  }

  function _updateOracleStalePeriods(uint32[3] memory newStalePeriods) internal returns (uint256 minStalePeriod) {
    minStalePeriod = type(uint256).max;
    vm.startPrank(governor);
    for (uint256 i; i < _collaterals.length; i++) {
      newStalePeriods[i] = uint32(bound(newStalePeriods[i], 0, 365 days));

      if (minStalePeriod > newStalePeriods[i]) minStalePeriod = newStalePeriods[i];
      AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
      uint32[] memory stalePeriods = new uint32[](1);
      uint8[] memory circuitChainIsMultiplied = new uint8[](1);
      uint8[] memory chainlinkDecimals = new uint8[](1);
      circuitChainlink[0] = AggregatorV3Interface(_oracles[i]);
      stalePeriods[0] = newStalePeriods[i];
      circuitChainIsMultiplied[0] = 1;
      chainlinkDecimals[0] = 8;
      Storage.OracleQuoteType quoteType = Storage.OracleQuoteType.UNIT;
      bytes memory readData =
        abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals, quoteType);
      bytes memory targetData;
      (,,,, bytes memory hyperparameters) = parallelizer.getOracle(address(_collaterals[i]));
      parallelizer.setOracle(
        _collaterals[i],
        abi.encode(
          Storage.OracleReadType.CHAINLINK_FEEDS, Storage.OracleReadType.STABLE, readData, targetData, hyperparameters
        )
      );
    }
    vm.stopPrank();
  }

  function _updateTargetOracleStalePeriods(uint32[3] memory newStalePeriods) internal returns (uint256 minStalePeriod) {
    minStalePeriod = type(uint256).max;
    vm.startPrank(governor);
    for (uint256 i; i < _collaterals.length; i++) {
      newStalePeriods[i] = uint32(bound(newStalePeriods[i], 0, 365 days));
      if (minStalePeriod > newStalePeriods[i]) minStalePeriod = newStalePeriods[i];
      AggregatorV3Interface[] memory circuitChainlink = new AggregatorV3Interface[](1);
      uint32[] memory stalePeriods = new uint32[](1);
      uint8[] memory circuitChainIsMultiplied = new uint8[](1);
      uint8[] memory chainlinkDecimals = new uint8[](1);
      circuitChainlink[0] = AggregatorV3Interface(_oracles[i]);
      stalePeriods[0] = newStalePeriods[i];
      circuitChainIsMultiplied[0] = 1;
      chainlinkDecimals[0] = 8;
      Storage.OracleQuoteType quoteType = Storage.OracleQuoteType.UNIT;
      bytes memory readData;
      bytes memory targetData =
        abi.encode(circuitChainlink, stalePeriods, circuitChainIsMultiplied, chainlinkDecimals, quoteType);
      (,,,, bytes memory hyperparameters) = parallelizer.getOracle(address(_collaterals[i]));
      parallelizer.setOracle(
        _collaterals[i],
        abi.encode(
          Storage.OracleReadType.STABLE, Storage.OracleReadType.CHAINLINK_FEEDS, readData, targetData, hyperparameters
        )
      );
    }
    vm.stopPrank();
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
      (Storage.OracleReadType readType, Storage.OracleReadType targetType, bytes memory data, bytes memory targetData,)
      = parallelizer.getOracle(address(_collaterals[i]));
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
}
