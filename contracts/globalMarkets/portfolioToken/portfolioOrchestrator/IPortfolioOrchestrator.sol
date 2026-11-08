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
pragma solidity ^0.8.4;

import {IGMTokenManager} from "contracts/globalMarkets/tokenManager/IGMTokenManager.sol";

/**
 * @title  IPortfolioOrchestrator
 * @author Ondo Finance
 * @notice Interface for interacting with the PortfolioOrchestrator contract
 */
interface IPortfolioOrchestrator {
  // ─────────────────────────────────────────────────────────────────────────────
  // Events
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * @notice Event emitted when an `invest` leg mints a GM token position
   * @param  portfolioToken The portfolio token the investment is for
   * @param  gmToken        The GM token that was minted
   * @param  usdonAmount    The USDon spent on this leg, in USDon's native decimals
   * @param  gmTokenAmount  The amount of GM tokens received, in the GM token's decimals
   */
  event PortfolioInvested(
    address indexed portfolioToken,
    address indexed gmToken,
    uint256 usdonAmount,
    uint256 gmTokenAmount
  );

  /**
   * @notice Event emitted when a `divest` leg redeems a GM token position
   * @param  portfolioToken The portfolio token the divestment is for
   * @param  gmToken        The GM token that was redeemed
   * @param  gmTokenAmount  The amount of GM tokens redeemed, in the GM token's decimals
   * @param  usdonAmount    The USDon received from this leg, in USDon's native decimals
   */
  event PortfolioDivested(
    address indexed portfolioToken,
    address indexed gmToken,
    uint256 gmTokenAmount,
    uint256 usdonAmount
  );

  /**
   * @notice Event emitted when the vault for a portfolio token is set or updated
   * @param  portfolioToken The portfolio token the vault belongs to
   * @param  oldVault       The previous vault address
   * @param  newVault       The new vault address
   */
  event VaultAddressSet(
    address indexed portfolioToken, address indexed oldVault, address indexed newVault
  );

  /**
   * @notice Event emitted when the wallet is set or updated
   * @param  oldWallet The previous wallet address
   * @param  newWallet The new wallet address
   */
  event WalletSet(address indexed oldWallet, address indexed newWallet);

  /**
   * @notice Event emitted when the `GMTokenManager` contract is set or updated
   * @param  oldManager The previous `GMTokenManager` address
   * @param  newManager The new `GMTokenManager` address
   */
  event GMTokenManagerSet(address indexed oldManager, address indexed newManager);

  /**
   * @notice Event emitted when a portfolio token's accepted status is set
   * @param  portfolioToken The portfolio token address
   * @param  accepted       Whether the portfolio token is accepted
   */
  event PortfolioTokenAcceptedSet(address indexed portfolioToken, bool accepted);

  /**
   * @notice Event emitted when tokens are rescued from the contract via `retrieveTokens`
   * @param  token     The address of the token that was retrieved
   * @param  recipient The address that received the tokens
   * @param  amount    The amount of tokens retrieved, in the token's native decimals
   */
  event TokensRetrieved(address indexed token, address indexed recipient, uint256 amount);

  /// Event emitted when the orchestrator is globally paused
  event GlobalPaused();

  /// Event emitted when the orchestrator is globally unpaused
  event GlobalUnpaused();

  /**
   * @notice Event emitted at the end of a successful `rebalance`
   * @param  portfolioToken     The portfolio token that was rebalanced
   * @param  totalUsdonSold     Total USDon received from the divest leg
   * @param  totalUsdonInvested Total USDon spent on the invest leg
   */
  event PortfolioRebalanced(
    address indexed portfolioToken, uint256 totalUsdonSold, uint256 totalUsdonInvested
  );

  /**
   * @notice Event emitted when operations are paused for a specific portfolio token
   * @param  portfolioToken The portfolio token whose operations were paused
   */
  event PortfolioTokenPaused(address indexed portfolioToken);

  /**
   * @notice Event emitted when operations are unpaused for a specific portfolio token
   * @param  portfolioToken The portfolio token whose operations were unpaused
   */
  event PortfolioTokenUnpaused(address indexed portfolioToken);

  // ─────────────────────────────────────────────────────────────────────────────
  // Errors
  // ─────────────────────────────────────────────────────────────────────────────

  /// Error emitted when the portfolio token is not registered as accepted
  error PortfolioTokenNotAccepted();

  /// Error emitted when attempting to set the `GMTokenManager` address to zero
  error GMTokenManagerAddressCantBeZero();

  /// Error emitted when quote and signature array lengths do not match
  error ArrayLengthMismatch();

  /// Error emitted when the orchestrator is globally paused
  error GloballyPaused();

  /// Error emitted when operations are paused for a specific portfolio token
  error PortfolioTokenIsPaused();

  /// Error emitted when the token address provided is zero
  error TokenAddressCantBeZero();

  /// Error emitted when the USDon address provided to `initialize` is zero
  error USDonAddressCantBeZero();

  /// Error emitted when the default admin address provided to `initialize` is zero
  error DefaultAdminZeroAddress();

  /// Error emitted when attempting to set a vault address to zero
  error VaultAddressCantBeZero();

  /// Error emitted when the vault's `portfolioToken()` does not match the portfolio token being configured
  error VaultPortfolioMismatch();

  /// Error emitted when invest / divest / rebalance is called before the vault is configured
  error VaultAddressNotSet();

  /// Error emitted when invest / divest / rebalance is called before the wallet is configured
  error WalletNotSet();

  /// Error emitted when attempting to set the wallet to zero
  error WalletCantBeZero();

  /// Error emitted when divest proceeds are insufficient to cover the invest leg of a rebalance
  error InsufficientDivestProceeds(uint256 required, uint256 available);

  // ─────────────────────────────────────────────────────────────────────────────
  // Core Functions
  // ─────────────────────────────────────────────────────────────────────────────

  function invest(
    address portfolioToken,
    IGMTokenManager.Quote[] calldata quotes,
    bytes[] calldata signatures
  ) external;

  function divest(
    address portfolioToken,
    IGMTokenManager.Quote[] calldata quotes,
    bytes[] calldata signatures
  ) external;

  function rebalance(
    address portfolioToken,
    IGMTokenManager.Quote[] calldata sellQuotes,
    bytes[] calldata sellSignatures,
    IGMTokenManager.Quote[] calldata investQuotes,
    bytes[] calldata investSignatures
  ) external;

  // ─────────────────────────────────────────────────────────────────────────────
  // View Functions
  // ─────────────────────────────────────────────────────────────────────────────

  function portfolioTokenAccepted(address portfolioToken) external view returns (bool);

  function vaultAddress(address portfolioToken) external view returns (address);

  function wallet() external view returns (address);
}
