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

import {IGMTokenManager} from "contracts/globalMarkets/tokenManager/IGMTokenManager.sol";
import {
  IPortfolioOrchestrator
} from "contracts/globalMarkets/portfolioToken/portfolioOrchestrator/IPortfolioOrchestrator.sol";
import {
  IPortfolioVault
} from "contracts/globalMarkets/portfolioToken/portfolioVault/IPortfolioVault.sol";
import {
  ReentrancyGuardTransient
} from "contracts/external/openzeppelin/contracts/security/ReentrancyGuardTransient.sol";
import {
  Initializable
} from "contracts/external/openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import {
  AccessControlEnumerableUpgradeable
} from "contracts/external/openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";

/**
 * @title  PortfolioOrchestrator
 * @author Ondo Finance
 * @notice Stateless execution engine that the off-chain orchestrator calls to
 *         invest, divest, and rebalance underlying GM token positions for
 *         portfolio tokens. Per-portfolio custody is handled by an
 *         IPortfolioVault contract; the orchestrator only holds tokens
 *         transiently within a single transaction.
 *
 *         Fund flows:
 *          - invest()    pulls the exact USDon needed from the wallet, mints GM
 *                        tokens, approves the vault for the minted GM tokens, then
 *                        calls vault.deposit() — the vault pulls and forwards the
 *                        tokens to its custody destination in a single step.
 *          - divest()    calls vault.withdraw() to pull GM tokens back from
 *                        the vault, redeems them for USDon, and sends the
 *                        proceeds to the wallet
 *          - rebalance() runs a divest leg then an invest leg, keeping USDon
 *                        in the orchestrator between the two; sends only the
 *                        surplus (sold − invested) to the wallet. Reverts if the
 *                        divest proceeds don't fully cover the invest leg.
 */
contract PortfolioOrchestrator is
  IPortfolioOrchestrator,
  Initializable,
  ReentrancyGuardTransient,
  AccessControlEnumerableUpgradeable
{
  using SafeERC20 for IERC20;

  /// Role for the off-chain operator that drives invest / divest / rebalance.
  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

  /// Role to configure the contract
  bytes32 public constant CONFIGURER_ROLE = keccak256("CONFIGURER_ROLE");

  /// Role to pause the orchestrator
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /// Role to unpause the orchestrator
  bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

  /// The decimals normalizer for price calculations
  uint256 public constant PRICE_NORMALIZER = 1e18;

  /// The USDon token address
  address public usdon;

  /// The GMTokenManager contract
  IGMTokenManager public gmTokenManager;

  /// Whether the orchestrator is globally paused
  bool public globalPaused;

  /// Whether a specific portfolio token is paused
  mapping(address => bool) public portfolioTokenPaused;

  /// Whether a portfolio token is accepted for rebalancing
  mapping(address => bool) public portfolioTokenAccepted;

  /// IPortfolioVault contract address per portfolio token
  mapping(address => address) public vaultAddress;

  /// The wallet that holds USDon liquidity
  address public wallet;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @param _defaultAdmin   The default admin role for the contract
   * @param _usdon          The address of the USDon token
   * @param _gmTokenManager The address of the GMTokenManager contract
   */
  function initialize(address _defaultAdmin, address _usdon, address _gmTokenManager)
    external
    initializer
  {
    __AccessControlEnumerable_init();
    if (_defaultAdmin == address(0)) revert DefaultAdminZeroAddress();
    if (_usdon == address(0)) revert USDonAddressCantBeZero();
    if (_gmTokenManager == address(0)) revert GMTokenManagerAddressCantBeZero();

    usdon = _usdon;
    gmTokenManager = IGMTokenManager(_gmTokenManager);
    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
  }

  /*//////////////////////////////////////////////////////////////
                      Invest / Divest / Rebalance
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Invest USDon into GM token positions. USDon is pulled from the
   *         wallet, used to mint GM tokens, and the GM tokens are deposited
   *         into the portfolio's vault.
   * @param  portfolioToken The portfolio token the investment is for
   * @param  quotes         Array of GM token quotes to execute
   * @param  signatures     Array of signatures corresponding to each quote
   */
  function invest(
    address portfolioToken,
    IGMTokenManager.Quote[] calldata quotes,
    bytes[] calldata signatures
  ) external nonReentrant onlyRole(OPERATOR_ROLE) whenNotPaused(portfolioToken) {
    if (!portfolioTokenAccepted[portfolioToken]) revert PortfolioTokenNotAccepted();
    address vault = vaultAddress[portfolioToken];
    if (vault == address(0)) revert VaultAddressNotSet();
    if (wallet == address(0)) revert WalletNotSet();

    uint256 totalUsdon = _sumUsdonCost(quotes);

    // Pull the exact USDon needed from the wallet; _invest consumes from the local balance.
    IERC20(usdon).safeTransferFrom(wallet, address(this), totalUsdon);

    _invest(portfolioToken, vault, totalUsdon, quotes, signatures);
  }

  /**
   * @notice Divests GM token positions for USDon and send the proceeds to the wallet.
   * @param  portfolioToken The portfolio token the divestment is for
   * @param  quotes         Array of GM token quotes to execute
   * @param  signatures     Array of signatures corresponding to each quote
   */
  function divest(
    address portfolioToken,
    IGMTokenManager.Quote[] calldata quotes,
    bytes[] calldata signatures
  ) external nonReentrant onlyRole(OPERATOR_ROLE) whenNotPaused(portfolioToken) {
    if (!portfolioTokenAccepted[portfolioToken]) revert PortfolioTokenNotAccepted();
    address vault = vaultAddress[portfolioToken];
    if (vault == address(0)) revert VaultAddressNotSet();
    if (wallet == address(0)) revert WalletNotSet();

    uint256 totalUsdon = _divest(portfolioToken, vault, quotes, signatures);

    // Send divest proceeds out to the wallet.
    if (totalUsdon > 0) IERC20(usdon).safeTransfer(wallet, totalUsdon);
  }

  /**
   * @notice Batch sell and invest in a single transaction for rebalancing.
   * @param  portfolioToken   The portfolio token to rebalance
   * @param  sellQuotes       Array of GM token sell quotes to execute
   * @param  sellSignatures   Array of signatures for sell quotes
   * @param  investQuotes     Array of GM token invest quotes to execute
   * @param  investSignatures Array of signatures for invest quotes
   */
  function rebalance(
    address portfolioToken,
    IGMTokenManager.Quote[] calldata sellQuotes,
    bytes[] calldata sellSignatures,
    IGMTokenManager.Quote[] calldata investQuotes,
    bytes[] calldata investSignatures
  ) external nonReentrant onlyRole(OPERATOR_ROLE) whenNotPaused(portfolioToken) {
    if (!portfolioTokenAccepted[portfolioToken]) revert PortfolioTokenNotAccepted();
    address vault = vaultAddress[portfolioToken];
    if (vault == address(0)) revert VaultAddressNotSet();
    if (wallet == address(0)) revert WalletNotSet();

    uint256 totalUsdonSold = _divest(portfolioToken, vault, sellQuotes, sellSignatures);
    uint256 totalUsdonInvested = _sumUsdonCost(investQuotes);

    if (totalUsdonSold < totalUsdonInvested) {
      revert InsufficientDivestProceeds(totalUsdonInvested, totalUsdonSold);
    }

    _invest(portfolioToken, vault, totalUsdonInvested, investQuotes, investSignatures);

    // Forward surplus from this rebalance back to the wallet
    uint256 surplus = totalUsdonSold - totalUsdonInvested;
    if (surplus > 0) IERC20(usdon).safeTransfer(wallet, surplus);

    emit PortfolioRebalanced(portfolioToken, totalUsdonSold, totalUsdonInvested);
  }

  /*//////////////////////////////////////////////////////////////
                        Internal Helpers
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Internal invest logic — consumes `totalUsdon` of the orchestrator's
   *         local USDon balance to mint GM tokens via GMTokenManager, then
   *         deposits them into the vault.
   * @param  portfolioToken The portfolio token the investment is for
   * @param  vault          The vault to receive GM tokens
   * @param  totalUsdon     Total USDon to spend (also used to pre-approve GMTM)
   * @param  quotes         Array of GM token quotes to execute
   * @param  signatures     Array of signatures corresponding to each quote
   */
  function _invest(
    address portfolioToken,
    address vault,
    uint256 totalUsdon,
    IGMTokenManager.Quote[] calldata quotes,
    bytes[] calldata signatures
  ) internal {
    if (quotes.length != signatures.length) {
      revert ArrayLengthMismatch();
    }

    IERC20(usdon).forceApprove(address(gmTokenManager), totalUsdon);

    for (uint256 i = 0; i < quotes.length; ++i) {
      uint256 usdonAmount = (quotes[i].quantity * quotes[i].price) / PRICE_NORMALIZER;

      uint256 gmTokensReceived =
        gmTokenManager.mintWithAttestation(quotes[i], signatures[i], usdon, usdonAmount);

      address gmToken = quotes[i].asset;
      IERC20(gmToken).forceApprove(vault, gmTokensReceived);
      IPortfolioVault(vault).deposit(gmToken, gmTokensReceived);

      emit PortfolioInvested(portfolioToken, gmToken, usdonAmount, gmTokensReceived);
    }
  }

  /**
   * @notice Internal divest logic — pulls GM tokens from the vault via
   *         vault.withdraw() and redeems them via GMTokenManager. The
   *         resulting USDon is left in the orchestrator; the caller is
   *         responsible for sending it onwards (typically to the wallet).
   * @param  portfolioToken The portfolio token the divestment is for
   * @param  vault          The vault holding the GM tokens
   * @param  quotes         Array of GM token quotes to execute
   * @param  signatures     Array of signatures corresponding to each quote
   * @return totalUsdon     Total USDon received
   */
  function _divest(
    address portfolioToken,
    address vault,
    IGMTokenManager.Quote[] calldata quotes,
    bytes[] calldata signatures
  ) internal returns (uint256 totalUsdon) {
    if (quotes.length != signatures.length) {
      revert ArrayLengthMismatch();
    }

    for (uint256 i = 0; i < quotes.length; ++i) {
      address gmToken = quotes[i].asset;
      uint256 gmTokenAmount = quotes[i].quantity;

      IPortfolioVault(vault).withdraw(gmToken, gmTokenAmount);
      IERC20(gmToken).forceApprove(address(gmTokenManager), gmTokenAmount);

      uint256 usdonReceived =
        gmTokenManager.redeemWithAttestation(quotes[i], signatures[i], usdon, 0);

      totalUsdon += usdonReceived;

      emit PortfolioDivested(portfolioToken, gmToken, gmTokenAmount, usdonReceived);
    }
  }

  /**
   * @notice Sum the USDon cost across a quote array
   * @param  quotes         Array of GM token quotes to sum
   * @return total          Total USDon cost
   */
  function _sumUsdonCost(IGMTokenManager.Quote[] calldata quotes)
    internal
    pure
    returns (uint256 total)
  {
    for (uint256 i = 0; i < quotes.length; ++i) {
      total += (quotes[i].quantity * quotes[i].price) / PRICE_NORMALIZER;
    }
  }

  /*//////////////////////////////////////////////////////////////
                      Admin Configuration
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sets the GMTokenManager contract
   * @param  _gmTokenManager The GMTokenManager address
   */
  function setGMTokenManager(address _gmTokenManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_gmTokenManager == address(0)) revert GMTokenManagerAddressCantBeZero();
    emit GMTokenManagerSet(address(gmTokenManager), _gmTokenManager);
    gmTokenManager = IGMTokenManager(_gmTokenManager);
  }

  /**
   * @notice Sets the wallet that holds USDon liquidity
   * @param  _wallet The wallet address
   */
  function setWallet(address _wallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_wallet == address(0)) revert WalletCantBeZero();
    emit WalletSet(wallet, _wallet);
    wallet = _wallet;
  }

  /**
   * @notice Sets the IPortfolioVault address for a specific portfolio token
   * @param  portfolioToken The portfolio token address
   * @param  _vaultAddress  The vault contract address
   */
  function setVaultAddress(address portfolioToken, address _vaultAddress)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (_vaultAddress == address(0)) revert VaultAddressCantBeZero();
    if (IPortfolioVault(_vaultAddress).portfolioToken() != portfolioToken) {
      revert VaultPortfolioMismatch();
    }
    emit VaultAddressSet(portfolioToken, vaultAddress[portfolioToken], _vaultAddress);
    vaultAddress[portfolioToken] = _vaultAddress;
  }

  /**
   * @notice Sets whether a portfolio token is accepted for rebalancing
   * @param  portfolioToken The portfolio token address
   * @param  accepted       Whether the token is accepted
   */
  function setPortfolioTokenAccepted(address portfolioToken, bool accepted)
    external
    onlyRole(CONFIGURER_ROLE)
  {
    if (portfolioToken == address(0)) revert TokenAddressCantBeZero();
    portfolioTokenAccepted[portfolioToken] = accepted;
    emit PortfolioTokenAcceptedSet(portfolioToken, accepted);
  }

  /**
   * @notice Rescue and transfer tokens locked in this contract
   * @param  token  The address of the token
   * @param  to     The address of the recipient
   * @param  amount The amount of token to transfer
   */
  function retrieveTokens(address token, address to, uint256 amount)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    IERC20(token).safeTransfer(to, amount);
    emit TokensRetrieved(token, to, amount);
  }

  /*//////////////////////////////////////////////////////////////
                          Pause/Unpause
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Globally pause all orchestrator operations
   */
  function pauseGlobal() external onlyRole(PAUSER_ROLE) {
    globalPaused = true;
    emit GlobalPaused();
  }

  /**
   * @notice Globally unpause all orchestrator operations
   */
  function unpauseGlobal() external onlyRole(UNPAUSER_ROLE) {
    globalPaused = false;
    emit GlobalUnpaused();
  }

  /**
   * @notice Pause operations for a specific portfolio token
   * @param  portfolioToken The address of the portfolio token
   */
  function pausePortfolioToken(address portfolioToken) external onlyRole(PAUSER_ROLE) {
    portfolioTokenPaused[portfolioToken] = true;
    emit PortfolioTokenPaused(portfolioToken);
  }

  /**
   * @notice Unpause operations for a specific portfolio token
   * @param  portfolioToken The address of the portfolio token
   */
  function unpausePortfolioToken(address portfolioToken) external onlyRole(UNPAUSER_ROLE) {
    portfolioTokenPaused[portfolioToken] = false;
    emit PortfolioTokenUnpaused(portfolioToken);
  }

  /*//////////////////////////////////////////////////////////////
                          Modifiers
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Ensure that the orchestrator is not paused
   * @param  portfolioToken The address of the portfolio token to check
   * @dev    Reverts if either globally paused or the specific portfolio token is paused
   */
  modifier whenNotPaused(address portfolioToken) {
    if (globalPaused) revert GloballyPaused();
    if (portfolioTokenPaused[portfolioToken]) revert PortfolioTokenIsPaused();
    _;
  }

  /**
   * @dev Reserved storage gap for future upgrades.
   */
  uint256[50] private __gap;
}
