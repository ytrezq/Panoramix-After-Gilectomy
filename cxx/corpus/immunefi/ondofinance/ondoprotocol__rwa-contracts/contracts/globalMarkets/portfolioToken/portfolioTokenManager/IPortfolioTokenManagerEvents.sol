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

/**
 * @title  IPortfolioTokenManagerEvents
 * @author Ondo Finance
 * @notice Isolated contract for all events emitted by the PortfolioTokenManager contract
 */
interface IPortfolioTokenManagerEvents {
  /**
   * @notice Event emitted when an admin completes a mint for a recipient
   * @param  recipient            The address of the recipient that receives the portfolio tokens
   * @param  recipientId          The user ID of the recipient
   * @param  portfolioToken       The address of the portfolio token being minted
   * @param  portfolioTokenAmount The amount of portfolio tokens minted, in decimals of the token
   * @param  metadata             Additional metadata to associate with the mint
   */
  event AdminMint(
    address indexed recipient,
    bytes32 indexed recipientId,
    address indexed portfolioToken,
    uint256 portfolioTokenAmount,
    bytes32 metadata
  );

  /**
   * @notice Event emitted when the `OndoIDRegistry` contract is set
   * @param  oldRegistry The old `OndoIDRegistry` contract address
   * @param  newRegistry The new `OndoIDRegistry` contract address
   */
  event OndoIDRegistrySet(address indexed oldRegistry, address indexed newRegistry);

  /**
   * @notice Event emitted when the `OndoSanityCheckOracle` contract is set
   * @param  oldOracle The old `OndoSanityCheckOracle` contract address
   * @param  newOracle The new `OndoSanityCheckOracle` contract address
   */
  event OndoSanityCheckOracleSet(address indexed oldOracle, address indexed newOracle);

  /**
   * @notice Event emitted when the `IssuanceHours` contract is set
   * @param  oldHours The old `IssuanceHours` contract address
   * @param  newHours The new `IssuanceHours` contract address
   */
  event IssuanceHoursSet(address indexed oldHours, address indexed newHours);

  /**
   * @notice Event emitted when a portfolio token's registration status is set
   * @param  portfolioToken The address of the portfolio token
   * @param  registered     Whether the portfolio token is registered
   */
  event PortfolioTokenRegistered(address indexed portfolioToken, bool indexed registered);

  /**
   * @notice Event emitted when the subscription minimum is set
   * @param  oldAmount The old subscription minimum, in USD with 18 decimals
   * @param  newAmount The new subscription minimum, in USD with 18 decimals
   */
  event MinimumDepositAmountSet(uint256 indexed oldAmount, uint256 indexed newAmount);

  /**
   * @notice Event emitted when the redemption minimum is set
   * @param  oldAmount The old redemption minimum, in USD with 18 decimals
   * @param  newAmount The new redemption minimum, in USD with 18 decimals
   */
  event MinimumRedemptionAmountSet(uint256 indexed oldAmount, uint256 indexed newAmount);

  /// Event emitted when minting functionality is globally paused
  event GlobalMintingPaused();

  /// Event emitted when minting functionality is globally unpaused
  event GlobalMintingUnpaused();

  /// Event emitted when redemption functionality is globally paused
  event GlobalRedeemingPaused();

  /// Event emitted when redemption functionality is globally unpaused
  event GlobalRedeemingUnpaused();

  /**
   * @notice Event emitted when minting is paused for a specific portfolio token
   * @param  portfolioToken The address of the portfolio token
   */
  event PortfolioTokenMintingPaused(address indexed portfolioToken);

  /**
   * @notice Event emitted when minting is unpaused for a specific portfolio token
   * @param  portfolioToken The address of the portfolio token
   */
  event PortfolioTokenMintingUnpaused(address indexed portfolioToken);

  /**
   * @notice Event emitted when redemption is paused for a specific portfolio token
   * @param  portfolioToken The address of the portfolio token
   */
  event PortfolioTokenRedeemingPaused(address indexed portfolioToken);

  /**
   * @notice Event emitted when redemption is unpaused for a specific portfolio token
   * @param  portfolioToken The address of the portfolio token
   */
  event PortfolioTokenRedeemingUnpaused(address indexed portfolioToken);

  /**
   * @notice Event emitted when the `OndoRateLimiter` contract is set
   * @param  oldRateLimiter The old `OndoRateLimiter` contract address
   * @param  newRateLimiter The new `OndoRateLimiter` contract address
   */
  event OndoRateLimiterSet(address indexed oldRateLimiter, address indexed newRateLimiter);

  /**
   * @notice Event emitted when the `OndoTokenRouter` contract is set
   * @param  oldRouter The old `OndoTokenRouter` contract address
   * @param  newRouter The new `OndoTokenRouter` contract address
   */
  event OndoTokenRouterSet(address indexed oldRouter, address indexed newRouter);

  /**
   * @notice Event emitted when tokens are rescued from the contract via `retrieveTokens`
   * @param  token     The address of the token that was retrieved
   * @param  recipient The address that received the tokens
   * @param  amount    The amount of tokens retrieved, in the token's native decimals
   */
  event TokensRetrieved(address indexed token, address indexed recipient, uint256 amount);
}
