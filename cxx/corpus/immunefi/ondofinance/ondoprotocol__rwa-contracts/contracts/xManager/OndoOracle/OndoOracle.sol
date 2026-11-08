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

import {IOndoOracle} from "contracts/xManager/interfaces/IOndoOracle.sol";
import {IRWAOracleWrapper} from "contracts/xManager/interfaces/IRWAOracleWrapper.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {AggregatorV3Interface} from "contracts/external/chainlink/AggregatorV3Interface.sol";

/**
 * @title  OndoOracle
 * @author Ondo Finance
 * @notice This contract serves as a single point of access for all token price
 *         data used by the Ondo RWA token platform. It associates each
 *         token address with an oracle type and provides an interface to
 *         the query price of tokens. The contract supports the following oracle types:
 *         1. HARDCODED, where the price is set by admins lives in contract storage
 *         2. TOKENIZED_RWA, where the price is retrieved from an external RWA oracle
 *         3. AGGREGATOR_V3, where the price is retrieved from an AggregatorV3 oracle
 *         Roles:
 *          - HARDCODED_SETTER_ROLE
 *          - RWA_ORACLE_SETTER_ROLE
 *          - AGGREGATOR_V3_ORACLE_SETTER_ROLE
 *
 * @dev    The contract is a slight variation of the FluxOracle contract
 *         (https://etherscan.io/address/0xA42e17F72aEFC6Ae585A08E6058A38ec036D37ec),
 *         with the main difference being that all prices are normalized to 18 decimals.
 */
contract OndoOracle is IOndoOracle, AccessControlEnumerable {
  /// Role to set the hardcoded price of a token
  bytes32 public constant HARDCODED_SETTER_ROLE = keccak256("HARDCODED_SETTER_ROLE");

  /// Role to set which IRWAPricer to use for a token with an RWA underlying
  bytes32 public constant RWA_ORACLE_SETTER_ROLE = keccak256("RWA_ORACLE_SETTER_ROLE");

  /// Role to set the AggregatorV3 price feed for a token
  bytes32 public constant AGGREGATOR_V3_ORACLE_SETTER_ROLE =
    keccak256("AGGREGATOR_V3_ORACLE_SETTER_ROLE");

  /**
   * @notice Struct to store AggregatorV3 oracle information
   * @param  oracle                         AggregatorV3 oracle address
   * @param  maxAggregatorV3OracleTimeDelay Max time delay in seconds for aggregatorV3 oracle
   * @param  normalizer                     Normalizer for the precision of the oracle
   */
  struct AggregatorV3OracleInfo {
    AggregatorV3Interface oracle;
    uint256 maxAggregatorV3OracleTimeDelay;
    uint256 normalizer;
  }

  enum OracleType {
    /// Indicates the OracleType is not registered
    UNINITIALIZED,
    /// Indicates that the price is set manually in the contract storage
    HARDCODED,
    /// Indicates that the price is retrieved from an external RWA oracle
    TOKENIZED_RWA,
    /// Indicates that the price is retrieved from a AggregatorV3 oracle
    AGGREGATOR_V3
  }

  /// Token to Oracle Type associations
  mapping(address => OracleType) public tokenToOracleType;

  /// Token to hardcoded price associations
  mapping(address => uint256) public tokenToHardcodedPrice;

  /// Token to RWA Oracle associations
  mapping(address => address) public tokenToRWAOracle;

  /// Token to AggregatorV3 oracle association
  mapping(address => AggregatorV3OracleInfo) public tokenToAggregatorV3Oracle;

  /**
   * @notice Event for when a token is associated to an `OracleType`
   * @param token      The token address
   * @param oracleType The new oracle type
   */
  event TokenToOracleTypeSet(address indexed token, OracleType oracleType);

  /**
   * @notice Event for when a token's hardcoded price is set
   * @param token         The token address
   * @param previousPrice The token's previous hardcoded price
   * @param newPrice      The token's new hardcoded price
   */
  event HardcodedPriceSet(address indexed token, uint256 previousPrice, uint256 newPrice);

  /**
   * @notice Event for when a token is associated with an Tokenized RWA Oracle
   * @param token             The token address
   * @param previousRWAOracle Previous RWA Oracle
   * @param newRWAOracle      New RWA Oracle
   */
  event TokenToRWAOracleSet(address indexed token, address previousRWAOracle, address newRWAOracle);

  /**
   * @notice Event for when AggregatorV3Oracles are set
   * @param token                          The token address
   * @param previousOracle                 The previous `AggregatorV3Oracle`
   * @param newOracle                      The new `AggregatorV3Oracle`
   * @param maxAggregatorV3OracleTimeDelay The max time delay for the
   *                                       `AggregatorV3Oracle` response
   */
  event AggregatorV3OracleSet(
    address indexed token,
    address previousOracle,
    address newOracle,
    uint256 maxAggregatorV3OracleTimeDelay
  );

  /// Error thrown when attempting to pull the price of a token with no associated oracle
  error TokenNotSupported();

  /// Error thrown when attempting to set a token's oracle of the wrong type
  error InvalidOracleType(OracleType expectedOracleType, OracleType actualOracleType);

  /// Error thrown when attempting to associate a token with an oracle that returns a price of zero
  error InvalidRWAOracle();

  /**
   * @notice Error thrown when an oracle returns a price of 0 or attempting to set a hardcoded
   *         price of zero
   */
  error ZeroPrice();

  /// Error thrown when an AggregatorV3 oracle returns corrupted data
  error CorruptedAggregatorV3Response();

  /// Error thrown when an AggregatorV3 oracle price is stale
  error AggregatorV3OraclePriceStale();

  /// Error thrown when attempting to set an oracle for a zero address
  error TokenAddressCantBeZero();

  /// Error thrown when attempting to set a token's oracle to the zero address
  error OracleCantBeZeroAddress();

  /**
   * @param admin The address of the admin who is granted all roles
   */
  constructor(address admin) {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(HARDCODED_SETTER_ROLE, admin);
    _grantRole(RWA_ORACLE_SETTER_ROLE, admin);
    _grantRole(AGGREGATOR_V3_ORACLE_SETTER_ROLE, admin);
  }

  /**
   * @notice Retrieves the price of the provided token
   * @param  token Token contract address to query the price of
   * @dev    This function attempts to retrieve the price based on the associated
   *         `OracleType`. This can mean retrieving from an AggregatorV3 Oracle, an
   *         RWA Oracle, or a price set manually within contract storage.
   *         Returns prices denominated in USD and in 18 decimals.
   */
  function getAssetPrice(address token) external view override returns (uint256 price) {
    // Get price of token depending on OracleType.
    OracleType oracleType = tokenToOracleType[token];
    if (oracleType == OracleType.HARDCODED) {
      // Get price stored in contract storage.
      price = tokenToHardcodedPrice[token];
    } else if (oracleType == OracleType.TOKENIZED_RWA) {
      // Get price from RWA Pricer.
      price = _getTokenizedRWAPrice(token);
    } else if (oracleType == OracleType.AGGREGATOR_V3) {
      // Get price from AggregatorV3 oracle.
      price = _getAggregatorV3OraclePrice(token);
    } else {
      revert TokenNotSupported();
    }

    if (price == 0) {
      revert ZeroPrice();
    }

    return price;
  }

  /*//////////////////////////////////////////////////////////////
                         Oracle Type Setter
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sets the oracle type for the provided token
   * @param  token      Token contract address
   * @param  oracleType `OracleType` to associate with token
   */
  function setTokenToOracleType(address token, OracleType oracleType)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    // Clear out previous token data.
    OracleType previousOracleType = tokenToOracleType[token];
    if (previousOracleType == OracleType.HARDCODED) {
      delete tokenToHardcodedPrice[token];
    } else if (previousOracleType == OracleType.TOKENIZED_RWA) {
      delete tokenToRWAOracle[token];
    } else if (previousOracleType == OracleType.AGGREGATOR_V3) {
      delete tokenToAggregatorV3Oracle[token];
    }

    tokenToOracleType[token] = oracleType;
    emit TokenToOracleTypeSet(token, oracleType);
  }

  /*//////////////////////////////////////////////////////////////
                        Hardcoded Oracle
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sets the price of an token in contract storage
   * @param  token The token contract address
   * @param  price The new price of the token
   */
  function setHardcodedPrice(address token, uint256 price)
    external
    onlyRole(HARDCODED_SETTER_ROLE)
  {
    if (tokenToOracleType[token] != OracleType.HARDCODED) {
      revert InvalidOracleType(OracleType.HARDCODED, tokenToOracleType[token]);
    }
    if (price == 0) {
      revert ZeroPrice();
    }
    uint256 previousPrice = tokenToHardcodedPrice[token];
    tokenToHardcodedPrice[token] = price;
    emit HardcodedPriceSet(token, previousPrice, price);
  }

  /*//////////////////////////////////////////////////////////////
                      Tokenized RWA Oracle
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Associates a custom token with an RWA Oracle
   * @param  token     The token contract address
   * @param  rwaOracle The oracle contract address
   */
  function setTokenToRWAOracle(address token, address rwaOracle)
    external
    onlyRole(RWA_ORACLE_SETTER_ROLE)
  {
    if (token == address(0)) revert TokenAddressCantBeZero();
    if (rwaOracle == address(0)) revert OracleCantBeZeroAddress();
    if (tokenToOracleType[token] != OracleType.TOKENIZED_RWA) {
      revert InvalidOracleType(OracleType.TOKENIZED_RWA, tokenToOracleType[token]);
    }
    // Check that function is implemented and returns a non-zero price
    uint256 price = IRWAOracleWrapper(rwaOracle).getPrice();
    if (price == 0) {
      revert InvalidRWAOracle();
    }

    address previousRwaOracle = tokenToRWAOracle[token];
    tokenToRWAOracle[token] = rwaOracle;
    emit TokenToRWAOracleSet(token, previousRwaOracle, rwaOracle);
  }

  /**
   * @notice Gets the price of an RWA token
   * @param  token The token contract address
   * @return price Price of the token
   */
  function _getTokenizedRWAPrice(address token) private view returns (uint256) {
    IRWAOracleWrapper rwaOracle = IRWAOracleWrapper(tokenToRWAOracle[token]);
    return rwaOracle.getPrice();
  }

  /*//////////////////////////////////////////////////////////////
                          AggregatorV3 Oracle
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Associates a custom token with a AggregatorV3 oracle
   * @param  token                          The token contract address
   * @param  newAggregatorV3Oracle          The AggregatorV3 oracle address
   * @param  maxAggregatorV3OracleTimeDelay The max time delay in seconds for Aggregator V3 oracle
   */
  function setTokenToAggregatorV3Oracle(
    address token,
    address newAggregatorV3Oracle,
    uint256 maxAggregatorV3OracleTimeDelay
  ) external onlyRole(AGGREGATOR_V3_ORACLE_SETTER_ROLE) {
    if (token == address(0)) revert TokenAddressCantBeZero();
    if (newAggregatorV3Oracle == address(0)) revert OracleCantBeZeroAddress();
    address previousAggregatorV3Oracle = address(tokenToAggregatorV3Oracle[token].oracle);
    _setTokenToAggregatorV3Oracle(token, newAggregatorV3Oracle, maxAggregatorV3OracleTimeDelay);
    emit AggregatorV3OracleSet(
      token, previousAggregatorV3Oracle, newAggregatorV3Oracle, maxAggregatorV3OracleTimeDelay
    );
  }

  /**
   * @notice Internal implementation function for setting token to aggregatorV3Oracle
   *         implementation.
   * @param  token                          The token contract address
   * @param  aggregatorV3Oracle             The AggregatorV3 oracle address
   * @param  maxAggregatorV3OracleTimeDelay The max time delay in seconds for the
   *                                        AggregatorV3 oracle
   */
  function _setTokenToAggregatorV3Oracle(
    address token,
    address aggregatorV3Oracle,
    uint256 maxAggregatorV3OracleTimeDelay
  ) private {
    if (tokenToOracleType[token] != OracleType.AGGREGATOR_V3) {
      revert InvalidOracleType(OracleType.AGGREGATOR_V3, tokenToOracleType[token]);
    }
    tokenToAggregatorV3Oracle[token].oracle = AggregatorV3Interface(aggregatorV3Oracle);
    tokenToAggregatorV3Oracle[token].maxAggregatorV3OracleTimeDelay = maxAggregatorV3OracleTimeDelay;
    tokenToAggregatorV3Oracle[token].normalizer =
      10 ** uint256(AggregatorV3Interface(aggregatorV3Oracle).decimals());
  }

  /**
   * @notice Retrieves the token price from an aggregator V3 oracle
   * @param  token The token contract address
   * @return price The price of the token
   */
  function _getAggregatorV3OraclePrice(address token) private view returns (uint256 price) {
    AggregatorV3OracleInfo storage aggregatorV3Info = tokenToAggregatorV3Oracle[token];
    (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
      aggregatorV3Info.oracle.latestRoundData();
    if (
      answer < 0 || roundId < answeredInRound || roundId == 0 || updatedAt == 0
        || updatedAt > block.timestamp
    ) {
      revert CorruptedAggregatorV3Response();
    }

    if (updatedAt < block.timestamp - aggregatorV3Info.maxAggregatorV3OracleTimeDelay) {
      revert AggregatorV3OraclePriceStale();
    }

    // Normalize price to 18 decimals
    // forge-lint: disable-next-line(unsafe-typecast)
    price = (uint256(answer) * 1e18) / aggregatorV3Info.normalizer;
  }
}
