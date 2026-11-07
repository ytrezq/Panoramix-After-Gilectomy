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
 * @title  IGMTokenManagerEvents
 * @author Ondo Finance
 * @notice Isolated contract for all events emitted by the GMTokenManager contract
 */
interface IGMTokenManagerEvents {
  /**
   * @notice Event emitted when an admin completes a mint for a recipient
   * @param  recipient    The address of the recipient that receives the RWA tokens
   * @param  recipientId  The user ID of the recipient
   * @param  rwaToken     The address of the RWA token being minted
   * @param  rwaAmount    The amount of RWA tokens minted in decimals of the RWA token
   * @param  metadata     Additional metadata to associate with the mint
   */
  event AdminMint(
    address indexed recipient,
    bytes32 indexed recipientId,
    address indexed rwaToken,
    uint256 rwaAmount,
    bytes32 metadata
  );

  /**
   * @notice Event emitted when the `OndoIDRegistry` contract is set
   * @param  oldOndoIDRegistry The old `OndoIDRegistry` contract address
   * @param  newOndoIDRegistry The new `OndoIDRegistry` contract address
   */
  event OndoIDRegistrySet(address indexed oldOndoIDRegistry, address indexed newOndoIDRegistry);

  /**
   * @notice Event emitted when the `OndoRateLimiter` contract is set
   * @param  oldOndoRateLimiter The old `OndoRateLimiter` contract address
   * @param  newOndoRateLimiter The new `OndoRateLimiter` contract address
   */
  event OndoRateLimiterSet(address indexed oldOndoRateLimiter, address indexed newOndoRateLimiter);

  /**
   * @notice Event emitted when subscription minimum is set
   * @param  oldMinDepositAmount Old subscription minimum
   * @param  newMinDepositAmount New subscription minimum
   */
  event MinimumDepositAmountSet(
    uint256 indexed oldMinDepositAmount, uint256 indexed newMinDepositAmount
  );

  /**
   * @notice Event emitted when redeem minimum is set
   * @param  oldMinRedemptionAmount Old redeem minimum
   * @param  newMinRedemptionAmount New redeem minimum
   */
  event MinimumRedemptionAmountSet(
    uint256 indexed oldMinRedemptionAmount, uint256 indexed newMinRedemptionAmount
  );

  /**
   * @notice Event emitted when the `OndoSanityCheckOracle` contract is set
   * @param  oldOndoSanityCheckOracle The old `OndoSanityCheckOracle` contract address
   * @param  newOndoSanityCheckOracle The new `OndoSanityCheckOracle` contract address
   */
  event OndoSanityCheckOracleSet(
    address indexed oldOndoSanityCheckOracle, address indexed newOndoSanityCheckOracle
  );

  /**
   * @notice Event emitted when the `IssuanceHours` contract is set
   * @param  oldIssuanceHours The old `IssuanceHours` contract address
   * @param  newIssuanceHours The new `IssuanceHours` contract address
   */
  event IssuanceHoursSet(address indexed oldIssuanceHours, address indexed newIssuanceHours);

  /**
   * @notice Event emitted when the `USDonManager` contract is set
   * @param  oldUSDonManager The old `USDonManager` contract address
   * @param  newUSDonManager The new `USDonManager` contract address
   */
  event USDonManagerSet(address indexed oldUSDonManager, address indexed newUSDonManager);

  /**
   * @notice Event emitted when the accepted GM token is set
   * @param  gmToken    The address of the GM token
   * @param  registered Whether the GM token is registered
   */
  event GMTokenRegistered(address indexed gmToken, bool indexed registered);

  /// Event emitted when minting functionality is paused
  event GlobalMintingPaused();

  /// Event emitted when minting functionality is unpaused
  event GlobalMintingUnpaused();

  /// Event emitted when redeem functionality is paused
  event GlobalRedeemingPaused();

  /// Event emitted when redeem functionality is unpaused
  event GlobalRedeemingUnpaused();

  /**
   * @notice Event emitted when minting is paused for a specific GM token
   * @param gmToken The address of the GM token
   */
  event GMTokenMintingPaused(address indexed gmToken);

  /**
   * @notice Event emitted when minting is unpaused for a specific GM token
   * @param gmToken The address of the GM token
   */
  event GMTokenMintingUnpaused(address indexed gmToken);

  /**
   * @notice Event emitted when redemption is paused for a specific GM token
   * @param gmToken The address of the GM token
   */
  event GMTokenRedeemingPaused(address indexed gmToken);

  /**
   * @notice Event emitted when redemption is unpaused for a specific GM token
   * @param gmToken The address of the GM token
   */
  event GMTokenRedeemingUnpaused(address indexed gmToken);
}
