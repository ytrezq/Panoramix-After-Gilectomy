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
 * @title  IPortfolioTokenManager
 * @author Ondo Finance
 * @notice Interface for interacting with the PortfolioTokenManager contract
 */
interface IPortfolioTokenManager {
  enum QuoteSide {
    /// Indicates that the user is buying portfolio tokens
    BUY,
    /// Indicates that the user is selling portfolio tokens
    SELL
  }

  /**
   * @notice Quote struct that is signed by the attestation signer
   * @param  chainId        The chain ID the quote is intended for
   * @param  attestationId  The ID of the quote
   * @param  userId         The user ID the quote is intended for
   * @param  asset          The address of the portfolio token being bought or sold
   * @param  price          The price of the portfolio token in USD with 18 decimals
   * @param  quantity       The quantity of portfolio tokens being bought or sold
   * @param  expiration     The expiration of the quote in seconds since the epoch
   * @param  side           The direction of the quote (BUY or SELL)
   * @param  additionalData Any additional data that is needed for the quote
   */
  struct Quote {
    uint256 chainId;
    uint256 attestationId;
    bytes32 userId;
    address asset;
    uint256 price;
    uint256 quantity;
    uint256 expiration;
    QuoteSide side;
    bytes32 additionalData;
  }

  /**
   * @notice Event emitted when a trade is executed with an attestation
   * @param  executionId    The monotonically increasing ID of the trade
   * @param  attestationId  The ID of the quote
   * @param  chainId        The chain ID the quote is intended for
   * @param  userId         The user ID the quote is intended for
   * @param  side           The direction of the quote (BUY or SELL)
   * @param  asset          The address of the portfolio token being bought or sold
   * @param  price          The price of the portfolio token in USD with 18 decimals
   * @param  quantity       The quantity of portfolio tokens being bought or sold
   * @param  expiration     The expiration of the quote in seconds since the epoch
   * @param  additionalData Any additional data that is needed for the quote
   */
  event TradeExecuted(
    uint256 executionId,
    uint256 attestationId,
    uint256 chainId,
    bytes32 userId,
    QuoteSide side,
    address asset,
    uint256 price,
    uint256 quantity,
    uint256 expiration,
    bytes32 additionalData
  );

  function mintWithAttestation(Quote calldata quote, bytes memory signature)
    external
    returns (uint256 portfolioTokenAmount);

  function redeemWithAttestation(Quote calldata quote, bytes memory signature)
    external
    returns (uint256 stablecoinAmount);

  function adminProcessMint(
    address portfolioToken,
    address recipient,
    uint256 portfolioTokenAmount,
    bytes32 metadata
  ) external;

  function portfolioTokenAccepted(address token) external view returns (bool);

  function stablecoin() external view returns (address);

  function setPortfolioTokenRegistrationStatus(address token, bool accepted) external;
}
