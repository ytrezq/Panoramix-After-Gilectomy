// SPDX-License-Identifier: BUSL-1.1
/*
      ▄▄█████████▄
   ╓██▀└ ,╓▄▄▄, '▀██▄
  ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
  ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
   ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
      ╙▀▀██████R⌐
 */
pragma solidity 0.8.33;

import {IUSDonManager} from "contracts/globalMarkets/USDonManager/IUSDonManager.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";
import {AggregatorV3Interface} from "contracts/external/chainlink/AggregatorV3Interface.sol";
import {IERC20Metadata} from "contracts/external/openzeppelin/contracts/token/IERC20Metadata.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";

/**
 * @title  USDonConverter
 * @author Ondo Finance
 * @notice This contract manages USDon<>Stablecoin swaps for the GMTokenManager.
 * @dev    This is a basic swap implementation that provides 1:1 swaps between a stablecoin
 *         and USDon (accounting for decimal differences). The contract maintains forward
 *         compatibility by conforming to the IUSDonManager interface for the subscribe
 *         and redeem functions, even though this implementation only supports a single
 *         stablecoin/USDon pair. This design allows for future expansion to support additional
 *         token pairs.
 */
contract USDonConverter is IUSDonManager {
  using SafeERC20 for IERC20;
  // Minimum stablecoin price from Chainlink oracle to allow subscribe/redeem
  uint256 public constant MINIMUM_STABLECOIN_PRICE = 0.98e8; // $0.98 with 8 decimals

  // Maximum oracle data age before being considered outdated
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  uint256 public immutable maxOracleDataAge;
  // Normalizer for USDon precision adjustment (1e18)
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  uint256 public immutable usdonNormalizer;
  // Normalizer for stablecoin precision adjustment
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  uint256 public immutable stablecoinNormalizer;
  /// The GMTokenManager contract authorized to call subscribe/redeem
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable gmTokenManager;
  /// The wallet that holds both stablecoin and USDon reserves
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable wallet;
  /// The USDon token
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  IERC20 public immutable usdon;
  /// The stablecoin token
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  IERC20 public immutable stablecoin;
  /// The stablecoin Chainlink price feed
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  AggregatorV3Interface public immutable stablecoinOracle;

  /// Thrown when the stablecoin oracle does not have 8 decimals as assumed
  error InvalidOracleDecimals();
  /// Thrown when attempting to initialize with zero max oracle data age
  error InvalidMaxOracleDataAge();
  /// Thrown when attempting to initialize with zero address
  error ZeroAddress();
  /// Thrown when caller is not the authorized GMTokenManager
  error OnlyGMTokenManager();
  /// Thrown when deposit token is not the set stablecoin
  error InvalidDepositToken();
  /// Thrown when receiving token is not the set stablecoin
  error InvalidReceivingToken();
  /// Thrown when USDon received is below minimum threshold
  error InsufficientUSDonReceived();
  /// Thrown when stablecoin received is below minimum threshold
  error InsufficientStablecoinReceived();
  /// Thrown when oracle price is outdated
  error OraclePriceOutdated();
  /// Thrown when stablecoin price is below minimum threshold
  error StablecoinPriceBelowMinimum();

  /**
   * @notice Constructs the USDonConverter contract
   * @param _gmTokenManager   The GMTokenManager address authorized to call functions
   * @param _wallet           The wallet address that holds token reserves
   * @param _usdon            The USDon token address
   * @param _stablecoin       The stablecoin token address
   * @param _stablecoinOracle The stablecoin Chainlink price feed address
   * @param _maxOracleDataAge The maximum age of oracle data before being considered outdated
   */
  constructor(
    address _gmTokenManager,
    address _wallet,
    address _usdon,
    address _stablecoin,
    address _stablecoinOracle,
    uint256 _maxOracleDataAge
  ) {
    if (
      _gmTokenManager == address(0) || _wallet == address(0) || _usdon == address(0)
        || _stablecoin == address(0) || _stablecoinOracle == address(0)
    ) revert ZeroAddress();
    if (AggregatorV3Interface(_stablecoinOracle).decimals() != 8) {
      revert InvalidOracleDecimals();
    }
    if (_maxOracleDataAge == 0) revert InvalidMaxOracleDataAge();

    gmTokenManager = _gmTokenManager;
    wallet = _wallet;

    usdonNormalizer = 10 ** (IERC20Metadata(_usdon).decimals());
    stablecoinNormalizer = 10 ** (IERC20Metadata(_stablecoin).decimals());
    usdon = IERC20(_usdon);
    stablecoin = IERC20(_stablecoin);
    stablecoinOracle = AggregatorV3Interface(_stablecoinOracle);
    maxOracleDataAge = _maxOracleDataAge;
  }

  /**
   * @notice Swaps a stablecoin for USDon at a 1:1 rate (accounting for decimal differences)
   * @param  depositToken         The address of token to deposit (must match configured stablecoin)
   * @param  depositAmount        The amount of stablecoin to deposit (6 decimals)
   * @param  minimumUSDonReceived The minimum USDon to receive (18 decimals)
   * @return rwaAmountOut         The amount of USDon received (18 decimals)
   * @dev    This function has some effectively unused parameters to conform to the
   *         IUSDonManager interface. `depositToken` and `minimumUSDonReceived` are used
   *         purely for validation, but will be important in a multi-token implementation.
   */
  function subscribe(address depositToken, uint256 depositAmount, uint256 minimumUSDonReceived)
    external
    override
    returns (uint256 rwaAmountOut)
  {
    if (msg.sender != gmTokenManager) revert OnlyGMTokenManager();
    if (depositToken != address(stablecoin)) revert InvalidDepositToken();
    _assertTokenMinimumStablecoinPrice();

    stablecoin.safeTransferFrom(gmTokenManager, wallet, depositAmount);
    rwaAmountOut = (depositAmount * usdonNormalizer) / stablecoinNormalizer;

    if (rwaAmountOut < minimumUSDonReceived) {
      revert InsufficientUSDonReceived();
    }
    usdon.safeTransferFrom(wallet, gmTokenManager, rwaAmountOut);
  }

  /**
   * @notice Swaps USDon for a stablecoin at a 1:1 rate (accounting for decimal differences)
   * @param  rwaAmount            The amount of USDon to redeem (18 decimals)
   * @param  receivingToken       The address of token to receive (must match configured stablecoin)
   * @param  minimumTokenReceived The minimum stablecoin to receive (6 decimals)
   * @return receiveTokenAmount   The amount of stablecoin received (6 decimals)
   * @dev    This function has some effectively unused parameters to conform to the
   *         IUSDonManager interface. `receivingToken` and `minimumTokenReceived` are used
   *         purely for validation, but will be important in a multi-token implementation.
   */
  function redeem(uint256 rwaAmount, address receivingToken, uint256 minimumTokenReceived)
    external
    override
    returns (uint256 receiveTokenAmount)
  {
    if (msg.sender != gmTokenManager) revert OnlyGMTokenManager();
    if (receivingToken != address(stablecoin)) revert InvalidReceivingToken();
    _assertTokenMinimumStablecoinPrice();

    usdon.safeTransferFrom(gmTokenManager, wallet, rwaAmount);
    receiveTokenAmount = (rwaAmount * stablecoinNormalizer) / usdonNormalizer;

    if (receiveTokenAmount < minimumTokenReceived) {
      revert InsufficientStablecoinReceived();
    }
    stablecoin.safeTransferFrom(wallet, gmTokenManager, receiveTokenAmount);
  }

  /**
   * @notice Asserts that the stablecoin price from the Chainlink oracle is valid
   * @dev    Reverts if the oracle data is outdated or if the price is below the minimum
   *         in order to protect against stablecoin depegging events
   */
  function _assertTokenMinimumStablecoinPrice() internal view {
    (, int256 price,, uint256 updatedAt,) = stablecoinOracle.latestRoundData();
    if (updatedAt < block.timestamp - maxOracleDataAge) {
      revert OraclePriceOutdated();
    }

    if (price < 0) revert StablecoinPriceBelowMinimum();
    // forge-lint: disable-next-line(unsafe-typecast)
    if (uint256(price) < MINIMUM_STABLECOIN_PRICE) {
      revert StablecoinPriceBelowMinimum();
    }
  }
}
