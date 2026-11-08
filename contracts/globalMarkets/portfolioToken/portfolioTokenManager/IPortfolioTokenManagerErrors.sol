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
 * @title  IPortfolioTokenManagerErrors
 * @author Ondo Finance
 * @notice Isolated contract for all errors emitted by the PortfolioTokenManager contract
 */
interface IPortfolioTokenManagerErrors {
  /// Error emitted when the token address is zero
  error TokenAddressCantBeZero();

  /// Error emitted when the deposit amount is too small
  error DepositAmountTooSmall();

  /// Error emitted when the user is not registered with the ID registry
  error UserNotRegistered();

  /// Error emitted when the redemption amount is too small
  error RedemptionAmountTooSmall();

  /// Error emitted when attempting to set the `OndoIDRegistry` address to zero
  error IDRegistryAddressCantBeZero();

  /// Error emitted when the minting functionality is paused
  error GlobalMintsPaused();

  /// Error emitted when the redemption functionality is paused
  error GlobalRedemptionsPaused();

  /// Error emitted when the minting functionality is paused for a specific portfolio token
  error PortfolioTokenMintsPaused();

  /// Error emitted when the redemption functionality is paused for a specific portfolio token
  error PortfolioTokenRedemptionsPaused();

  /// Error emitted when attempting to set the `OndoSanityCheckOracle` address to zero
  error SanityCheckOracleAddressCantBeZero();

  /// Error emitted when the attestation has expired
  error AttestationExpired();

  /// Error emitted when the attestation is signed by an unverified signer
  error InvalidAttestationSigner();

  /// Error emitted when the chain ID in the quote does not match `block.chainid`
  error InvalidChainId();

  /// Error emitted when the quote side does not match the operation being performed
  error InvalidQuoteSide();

  /// Error emitted when the user ID resolved for `msg.sender` differs from the quote's `userId`
  error UserIdMismatch(bytes32 expected, bytes32 actual);

  /// Error emitted when an attestation ID has already been used
  error AttestationAlreadyExecuted();

  /// Error emitted when attempting to set the `IssuanceHours` address to zero
  error IssuanceHoursAddressCantBeZero();

  /// Error emitted when the portfolio token is not registered for minting/redemption
  error PortfolioTokenNotRegistered();

  /// Error emitted when attempting to set the `OndoRateLimiter` address to zero
  error RateLimiterAddressCantBeZero();

  /// Error emitted when the default admin address provided to `initialize` is zero
  error DefaultAdminZeroAddress();

  /// Error emitted when the stablecoin address provided to the constructor is zero
  error StablecoinAddressCantBeZero();

  /// Error emitted when attempting to set the `OndoTokenRouter` address to zero
  error OndoTokenRouterAddressCantBeZero();
}
