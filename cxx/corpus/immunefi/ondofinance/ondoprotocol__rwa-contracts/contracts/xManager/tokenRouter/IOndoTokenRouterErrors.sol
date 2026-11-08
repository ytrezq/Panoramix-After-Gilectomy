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

interface IOndoTokenRouterErrors {
  /// Error thrown when attempting to set a recipient or source with a zero address for the RWA token.
  error RwaTokenCantBeZero();

  /// Error thrown when attempting to set a recipient with a zero address for the token.
  error DepositTokenCantBeZero();

  /// Error thrown when attempting to set a source with a zero address for the token.
  error WithdrawTokenCantBeZero();

  /// Error thrown when attempting to set the oracle or minimum price for a token with a zero address.
  error TokenAddressCantBeZero();

  /// Error thrown when calling `setMinimumTokenPriceAndOracle` with only some of the parameters set.
  error InconsistentMinimumTokenPriceParameters();

  /// Error thrown when the price pulled from a token's oracle is outdated.
  error OraclePriceOutdated();

  /// Error thrown a token's price is below the minimum.
  error TokenPriceBelowMinimum();

  /// Error thrown when a deposit token doesn't have a recipient set.
  error TokenRecipientNotSet();

  /// Error thrown when there aren't enough withdraw tokens available.
  error InsufficientWithdrawTokens();

  /// Error thrown when attempting to set a user ID to the zero bytes32 value.
  error UserIDCantBeZero();
}
