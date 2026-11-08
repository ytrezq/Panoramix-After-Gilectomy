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
  ReentrancyGuardTransient
} from "contracts/external/openzeppelin/contracts/security/ReentrancyGuardTransient.sol";
import {Pausable} from "contracts/external/openzeppelin/contracts/security/Pausable.sol";

/**
 * @title  PortfolioTokenFactory
 * @author Ondo Finance
 * @notice Factory for deploying and configuring portfolio tokens with built-in compliance
 *         and pause management. Portfolio tokens reuse the GMToken implementation via
 *         a separate BeaconProxy, allowing independent upgrades.
 *
 *         This contract allows for:
 *         - Deploying new portfolio tokens with preconfigured compliance and pause management
 *         - Registering tokens with PortfolioTokenManager and PortfolioOrchestrator via a unified registrar
 *         - Registering tokens with the bridge via a bridge registrar
 *         - Isolated token deployments without registrar integration
 */
contract PortfolioTokenFactory is AccessControlEnumerable, ReentrancyGuardTransient, Pausable {
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

  /// Address of the portfolio token registrar (handles PTM + orchestrator registration)
  IRegistrar public portfolioTokenRegistrar;

  /// Address of the bridge registrar contract
  IRegistrar public bridgeRegistrar;

  /// Indicates if a token with the same ticker already exists
  mapping(string => bool) public tickerExists;

  /**
   * @notice Emitted when a new compliance contract is set
   * @param  oldCompliance The old compliance contract address
   * @param  newCompliance The new compliance contract address
   */
  event NewComplianceSet(address indexed oldCompliance, address indexed newCompliance);

  /**
   * @notice Emitted when a new token pause manager is set
   * @param  oldTokenPauseManager The old token pause manager address
   * @param  newTokenPauseManager The new token pause manager address
   */
  event NewTokenPauseManagerSet(
    address indexed oldTokenPauseManager, address indexed newTokenPauseManager
  );

  /**
   * @notice Emitted when a new portfolio token registrar is set
   * @param  oldRegistrar The old registrar address
   * @param  newRegistrar The new registrar address
   */
  event NewPortfolioTokenRegistrarSet(address indexed oldRegistrar, address indexed newRegistrar);

  /**
   * @notice Emitted when a new bridge registrar is set
   * @param  oldRegistrar The old registrar address
   * @param  newRegistrar The new registrar address
   */
  event NewBridgeRegistrarSet(address indexed oldRegistrar, address indexed newRegistrar);

  /**
   * @notice Emitted when a new portfolio token is deployed
   * @param  proxy             The address of the deployed token proxy
   * @param  beacon            The address of the beacon contract
   * @param  name              The name of the token
   * @param  ticker            The token symbol
   * @param  compliance        The compliance contract address
   * @param  tokenPauseManager The token pause manager address
   */
  event NewPortfolioTokenDeployed(
    address indexed proxy,
    address indexed beacon,
    string name,
    string ticker,
    address compliance,
    address tokenPauseManager
  );

  /**
   * @notice Emitted when a ticker is set or cleared
   * @param  ticker The ticker that was set or cleared
   * @param  status The status of the ticker
   */
  event TickerSet(string indexed ticker, bool status);

  /// Error thrown when compliance address is zero
  error ComplianceCantBeZero();
  /// Error thrown when token pause manager address is zero
  error TokenPauseManagerCantBeZero();
  /// Error thrown when portfolio token registrar address is zero
  error PortfolioTokenRegistrarCantBeZero();
  /// Error thrown when bridge registrar address is zero
  error BridgeRegistrarCantBeZero();
  /// Error thrown when guardian address is zero
  error GuardianCantBeZero();
  /// Error thrown when deploying a token with an existing ticker
  error TickerAlreadyExists();

  /**
   * @param guardian                  The address to receive admin roles (expected to be a multisig)
   * @param _compliance               The address of the OndoComplianceGMView contract
   * @param _tokenPauseManager        The address of the token pause manager
   * @param _portfolioTokenRegistrar  The address of the portfolio token registrar
   * @param _bridgeRegistrar          The address of the bridge registrar
   */
  constructor(
    address guardian,
    address _compliance,
    address _tokenPauseManager,
    address _portfolioTokenRegistrar,
    address _bridgeRegistrar
  ) {
    if (guardian == address(0)) revert GuardianCantBeZero();
    if (_compliance == address(0)) revert ComplianceCantBeZero();
    if (_tokenPauseManager == address(0)) revert TokenPauseManagerCantBeZero();
    if (_portfolioTokenRegistrar == address(0)) revert PortfolioTokenRegistrarCantBeZero();
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
    portfolioTokenRegistrar = IRegistrar(_portfolioTokenRegistrar);
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
   * @notice Deploys a new portfolio token and registers it with the PortfolioTokenManager,
   *         PortfolioOrchestrator, and bridge
   * @param  name       The name of the token
   * @param  ticker     The token symbol
   * @param  tokenAdmin The address that will receive admin rights on the token
   * @return            The address of the deployed token proxy
   */
  function deployAndRegisterToken(string calldata name, string calldata ticker, address tokenAdmin)
    external
    nonReentrant
    onlyRole(DEPLOYER_ROLE)
    whenNotPaused
    returns (address)
  {
    GMToken portfolioToken = GMToken(_deployPortfolioToken(name, ticker));

    // Register with PortfolioTokenManager + PortfolioOrchestrator via the unified registrar
    portfolioToken.grantRole(DEFAULT_ADMIN_ROLE, address(portfolioTokenRegistrar));
    portfolioTokenRegistrar.register(address(portfolioToken));
    portfolioToken.revokeRole(DEFAULT_ADMIN_ROLE, address(portfolioTokenRegistrar));

    // Register with the bridge registrar
    portfolioToken.grantRole(DEFAULT_ADMIN_ROLE, address(bridgeRegistrar));
    bridgeRegistrar.register(address(portfolioToken));
    portfolioToken.revokeRole(DEFAULT_ADMIN_ROLE, address(bridgeRegistrar));

    // Transfer admin to the token admin and renounce factory's role
    portfolioToken.grantRole(DEFAULT_ADMIN_ROLE, tokenAdmin);
    portfolioToken.renounceRole(DEFAULT_ADMIN_ROLE, address(this));

    return address(portfolioToken);
  }

  /**
   * @notice Deploys a new portfolio token without registering it anywhere
   * @param  name       The name of the token
   * @param  ticker     The token symbol
   * @param  tokenAdmin The address that will receive admin rights on the token
   * @return            The address of the deployed token proxy
   */
  function deployPortfolioTokenIsolated(
    string calldata name,
    string calldata ticker,
    address tokenAdmin
  ) external nonReentrant onlyRole(DEPLOYER_ROLE) whenNotPaused returns (address) {
    GMToken portfolioToken = GMToken(_deployPortfolioToken(name, ticker));

    portfolioToken.grantRole(DEFAULT_ADMIN_ROLE, tokenAdmin);
    portfolioToken.renounceRole(DEFAULT_ADMIN_ROLE, address(this));

    return address(portfolioToken);
  }

  /**
   * @notice Internal function to deploy a new portfolio token via BeaconProxy
   * @param  name   The name of the token
   * @param  ticker The token symbol
   * @return        The address of the deployed token proxy
   */
  function _deployPortfolioToken(string calldata name, string calldata ticker)
    internal
    returns (address)
  {
    if (tickerExists[ticker]) revert TickerAlreadyExists();
    BeaconProxy portfolioTokenProxy = new BeaconProxy(beacon, "");
    GMToken portfolioTokenProxied = GMToken(address(portfolioTokenProxy));
    portfolioTokenProxied.initialize(name, ticker, compliance, tokenPauseManager);
    tickerExists[ticker] = true;
    emit TickerSet(ticker, true);

    emit NewPortfolioTokenDeployed(
      address(portfolioTokenProxied), beacon, name, ticker, compliance, tokenPauseManager
    );

    return address(portfolioTokenProxied);
  }

  /*//////////////////////////////////////////////////////////////
                      Configuration
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sets the compliance contract address
   * @param  _compliance The new compliance contract address
   */
  function setCompliance(address _compliance) external onlyRole(CONFIGURER_ROLE) {
    if (_compliance == address(0)) revert ComplianceCantBeZero();
    address oldCompliance = compliance;
    compliance = _compliance;
    emit NewComplianceSet(oldCompliance, compliance);
  }

  /**
   * @notice Sets the token pause manager address
   * @param  _tokenPauseManager The new token pause manager address
   */
  function setTokenPauseManager(address _tokenPauseManager) external onlyRole(CONFIGURER_ROLE) {
    if (_tokenPauseManager == address(0)) revert TokenPauseManagerCantBeZero();
    address oldTokenPauseManager = tokenPauseManager;
    tokenPauseManager = _tokenPauseManager;
    emit NewTokenPauseManagerSet(oldTokenPauseManager, tokenPauseManager);
  }

  /**
   * @notice Sets the portfolio token registrar address
   * @param  _registrar The new registrar address
   */
  function setPortfolioTokenRegistrar(address _registrar) external onlyRole(CONFIGURER_ROLE) {
    if (_registrar == address(0)) revert PortfolioTokenRegistrarCantBeZero();
    address oldRegistrar = address(portfolioTokenRegistrar);
    portfolioTokenRegistrar = IRegistrar(_registrar);
    emit NewPortfolioTokenRegistrarSet(oldRegistrar, _registrar);
  }

  /**
   * @notice Sets the bridge registrar address
   * @param  _registrar The new bridge registrar address
   */
  function setBridgeRegistrar(address _registrar) external onlyRole(CONFIGURER_ROLE) {
    if (_registrar == address(0)) revert BridgeRegistrarCantBeZero();
    address oldRegistrar = address(bridgeRegistrar);
    bridgeRegistrar = IRegistrar(_registrar);
    emit NewBridgeRegistrarSet(oldRegistrar, _registrar);
  }

  /**
   * @notice Clears a ticker so it can be reused for a new token deployment
   * @param  ticker The ticker to clear
   */
  function clearTicker(string calldata ticker) external onlyRole(CONFIGURER_ROLE) {
    tickerExists[ticker] = false;
    emit TickerSet(ticker, false);
  }
}
