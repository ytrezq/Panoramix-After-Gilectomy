/**
 * SPDX-License-Identifier: BUSL-1.1
 *       ▄▄█████████▄
 *    ╓██▀└ ,╓▄▄▄, '▀██▄
 *   ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 *  ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
 * ██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
 * ██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
 * ╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 *  ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
 *   ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
 *    ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
 *       ╙▀▀██████R⌐
 */
pragma solidity 0.8.33;

// Proxy admin contract used in OZ upgrades plugin
import {BeaconProxy} from "contracts/external/openzeppelin/contracts/beacon/BeaconProxy.sol";
import {
  UpgradeableBeacon
} from "contracts/external/openzeppelin/contracts/beacon/UpgradeableBeacon.sol";
import {GMToken} from "contracts/globalMarkets/GMToken.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {IRegistrar} from "contracts/globalMarkets/tokenFactory/registrars/IRegistrar.sol";
import {
  ReentrancyGuard
} from "contracts/external/openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "contracts/external/openzeppelin/contracts/security/Pausable.sol";

/**
 * @title  GMTokenFactory
 * @author Ondo Finance
 * @notice This contract serves as a factory for deploying and configuring GM tokens with
 *         built-in compliance and pause management.
 *
 *         This contract allows for:
 *         - Deploying new GM tokens with preconfigured compliance and pause management
 *         - Registering the tokens for use via with bridge and token manager registrars
 *         - Isolated token deployments without registrar integration
 */
contract GMTokenFactory is AccessControlEnumerable, ReentrancyGuard, Pausable {
  /// Role used for deploying new tokens
  bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
  /// Role used for configuring the factory
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");
  /// Role used to pause the factory
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  /// Role used to unpause the factory
  bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
  /// Address of the beacon contract used for proxy deployments
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable beacon;
  /// Address of the OndoComplianceGMView contract
  address public compliance;
  /// Address of the token pause manager contract
  address public tokenPauseManager;
  /// Address of the token registrar contract
  IRegistrar public tokenManagerRegistrar;
  /// Address of the bridge manager registrar contract
  IRegistrar public bridgeRegistrar;
  /// Indicates if a token with the same ticker already exists
  mapping(string => bool) public tickerExists;

  /**
   * @notice Emitted when a new OndoComplianceGMView contract is set
   * @param  oldCompliance The old compliance contract address
   * @param  newCompliance The new compliance contract address
   */
  event NewComplianceSet(address indexed oldCompliance, address indexed newCompliance);

  /**
   * @notice Emitted when a new token pause manager contract is set
   * @param  oldTokenPauseManager The old token pause manager address
   * @param  newTokenPauseManager The new token pause manager address
   */
  event NewTokenPauseManagerSet(
    address indexed oldTokenPauseManager, address indexed newTokenPauseManager
  );

  /**
   * @notice Emitted when a new token manager registrar contract is set
   * @param  oldTokenManagerRegistrar The old token manager registrar address
   * @param  newTokenManagerRegistrar The new token manager registrar address
   */
  event NewTokenManagerRegistrarSet(
    address indexed oldTokenManagerRegistrar, address indexed newTokenManagerRegistrar
  );

  /**
   * @notice Emitted when a new bridge registrar contract is set
   * @param  oldBridgeRegistrar The old bridge registrar address
   * @param  newBridgeRegistrar The new bridge registrar address
   */
  event NewBridgeRegistrarSet(
    address indexed oldBridgeRegistrar, address indexed newBridgeRegistrar
  );

  /**
   * @notice Emitted when a new GM token is deployed (regardless of registration)
   * @param  proxy             The address of the deployed token proxy
   * @param  beacon            The address of the beacon contract
   * @param  name              The name of the token
   * @param  ticker            The token symbol
   * @param  compliance        The address of the OndoComplianceGMView contract
   * @param  tokenPauseManager The address of the token pause manager contract
   */
  event NewGMTokenDeployed(
    address indexed proxy,
    address indexed beacon,
    string name,
    string ticker,
    address compliance,
    address tokenPauseManager
  );

  /**
   * @notice Emitted when a ticker is set or cleared
   * @param  ticker  The ticker that was set or cleared
   * @param  status  The status of the ticker (true if set, false if cleared)
   */
  event TickerSet(string indexed ticker, bool status);

  /// Error thrown when attempting to set the compliance contract to zero address
  error ComplianceCantBeZero();

  /// Error thrown when attempting to set the token pause manager to zero address
  error TokenPauseManagerCantBeZero();

  /// Error thrown when attempting to set the token manager registrar to zero address
  error TokenManagerRegistrarCantBeZero();

  /// Error thrown when attempting to set the bridge registrar to zero address
  error BridgeRegistrarCantBeZero();

  /// Error thrown when attempting to deploy a token with an already existing ticker
  error TickerAlreadyExists();

  /**
   * @notice Initializes the factory with required addresses and sets up roles
   * @param  guardian               The address to receive admin roles (expected to be a multisig)
   * @param  _compliance            The address of the OndoComplianceGMView contract
   * @param  _tokenPauseManager     The address of the token pause manager
   * @param  _tokenManagerRegistrar The address of the token manager registrar
   * @param  _bridgeRegistrar       The address of the bridge registrar
   */
  constructor(
    address guardian,
    address _compliance,
    address _tokenPauseManager,
    address _tokenManagerRegistrar,
    address _bridgeRegistrar
  ) {
    if (_compliance == address(0)) {
      revert ComplianceCantBeZero();
    }
    if (_tokenPauseManager == address(0)) revert TokenPauseManagerCantBeZero();
    if (_tokenManagerRegistrar == address(0)) {
      revert TokenManagerRegistrarCantBeZero();
    }
    if (_bridgeRegistrar == address(0)) revert BridgeRegistrarCantBeZero();

    _grantRole(DEFAULT_ADMIN_ROLE, guardian);
    _grantRole(DEPLOYER_ROLE, guardian);
    _grantRole(CONFIGURER_ROLE, guardian);
    _grantRole(PAUSER_ROLE, guardian);
    _grantRole(UNPAUSER_ROLE, guardian);

    address gmTokenImplementation = address(new GMToken());
    UpgradeableBeacon _beaconContract = new UpgradeableBeacon(gmTokenImplementation);
    _beaconContract.transferOwnership(guardian);
    beacon = address(_beaconContract);

    compliance = _compliance;
    tokenPauseManager = _tokenPauseManager;
    tokenManagerRegistrar = IRegistrar(_tokenManagerRegistrar);
    bridgeRegistrar = IRegistrar(_bridgeRegistrar);
  }

  /**
   * @notice Pauses the factory, disabling new deployments
   */
  function pause() external onlyRole(PAUSER_ROLE) {
    _pause();
  }

  /**
   * @notice Unpauses the factory, enabling new deployments
   */
  function unpause() external onlyRole(UNPAUSER_ROLE) {
    _unpause();
  }

  /**
   * @notice Deploys a new GM token and registers it with both bridge and token manager
   * @param  name       The name of the token
   * @param  ticker     The token symbol
   * @param  tokenAdmin The address that will receive admin rights on the token
   * @return            The address of the deployed token proxy
   */
  function deployAndRegisterToken(string calldata name, string calldata ticker, address tokenAdmin)
    public
    nonReentrant
    onlyRole(DEPLOYER_ROLE)
    whenNotPaused
    returns (address)
  {
    GMToken gmToken = GMToken(_deployGmToken(name, ticker));

    gmToken.grantRole(DEFAULT_ADMIN_ROLE, address(bridgeRegistrar));
    bridgeRegistrar.register(address(gmToken));
    gmToken.revokeRole(DEFAULT_ADMIN_ROLE, address(bridgeRegistrar));

    gmToken.grantRole(DEFAULT_ADMIN_ROLE, address(tokenManagerRegistrar));
    tokenManagerRegistrar.register(address(gmToken));
    gmToken.revokeRole(DEFAULT_ADMIN_ROLE, address(tokenManagerRegistrar));

    gmToken.grantRole(DEFAULT_ADMIN_ROLE, tokenAdmin);
    gmToken.renounceRole(DEFAULT_ADMIN_ROLE, address(this));

    return address(gmToken);
  }

  /**
   * @notice Deploys a new GM token without registering it anywhere
   * @param  name       The name of the token
   * @param  ticker     The token symbol
   * @param  tokenAdmin The address that will receive admin rights on the token
   * @return            The address of the deployed token proxy
   */
  function deployGmTokenIsolated(string calldata name, string calldata ticker, address tokenAdmin)
    external
    nonReentrant
    onlyRole(DEPLOYER_ROLE)
    whenNotPaused
    returns (address)
  {
    GMToken gmToken = GMToken(_deployGmToken(name, ticker));

    gmToken.grantRole(DEFAULT_ADMIN_ROLE, tokenAdmin);
    gmToken.renounceRole(DEFAULT_ADMIN_ROLE, address(this));

    return address(gmToken);
  }

  /**
   * @notice Internal function to deploy a new GM token
   * @param  name   The name of the token
   * @param  ticker The token symbol
   * @return        The address of the deployed token proxy
   */
  function _deployGmToken(string calldata name, string calldata ticker) internal returns (address) {
    if (tickerExists[ticker]) revert TickerAlreadyExists();
    BeaconProxy gmTokenProxy = new BeaconProxy(beacon, "");
    GMToken gmTokenProxied = GMToken(address(gmTokenProxy));
    gmTokenProxied.initialize(name, ticker, compliance, tokenPauseManager);
    tickerExists[ticker] = true;
    emit TickerSet(ticker, true);

    emit NewGMTokenDeployed(
      address(gmTokenProxied), beacon, name, ticker, compliance, tokenPauseManager
    );

    return address(gmTokenProxied);
  }

  /**
   * @notice Updates the compliance contract address
   * @param  _compliance The new compliance contract address
   */
  function setCompliance(address _compliance) external onlyRole(CONFIGURER_ROLE) {
    if (_compliance == address(0)) {
      revert ComplianceCantBeZero();
    }
    address oldCompliance = compliance;
    compliance = _compliance;
    emit NewComplianceSet(oldCompliance, compliance);
  }

  /**
   * @notice Updates the token pause manager address
   * @param  _tokenPauseManager The new token pause manager address
   */
  function setTokenPauseManager(address _tokenPauseManager) external onlyRole(CONFIGURER_ROLE) {
    if (_tokenPauseManager == address(0)) {
      revert TokenPauseManagerCantBeZero();
    }
    address oldTokenPauseManager = tokenPauseManager;
    tokenPauseManager = _tokenPauseManager;
    emit NewTokenPauseManagerSet(oldTokenPauseManager, tokenPauseManager);
  }

  /**
   * @notice Updates the bridge registrar address
   * @param  _bridgeRegistrar The new bridge registrar address
   */
  function setBridgeRegistrar(address _bridgeRegistrar) external onlyRole(CONFIGURER_ROLE) {
    if (_bridgeRegistrar == address(0)) {
      revert BridgeRegistrarCantBeZero();
    }
    emit NewBridgeRegistrarSet(address(bridgeRegistrar), _bridgeRegistrar);
    bridgeRegistrar = IRegistrar(_bridgeRegistrar);
  }

  /**
   * @notice Updates the token manager registrar address
   * @param  _tokenManagerRegistrar The new token manager registrar address
   */
  function setTokenManagerRegistrar(address _tokenManagerRegistrar)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    if (_tokenManagerRegistrar == address(0)) {
      revert TokenManagerRegistrarCantBeZero();
    }
    emit NewTokenManagerRegistrarSet(address(tokenManagerRegistrar), _tokenManagerRegistrar);
    tokenManagerRegistrar = IRegistrar(_tokenManagerRegistrar);
  }

  /**
   * @notice Clears a ticker in the edge case where we need to deploy a token
   *         with the same ticker as a previously deployed token
   * @param  ticker The ticker to clear
   */
  function clearTicker(string calldata ticker) external onlyRole(CONFIGURER_ROLE) {
    tickerExists[ticker] = false;
    emit TickerSet(ticker, false);
  }
}
