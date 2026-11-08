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

interface IBaseRWAManagerEvents {
  /**
   * @notice Event emitted when a user subscribes to an RWA token
   * @param  subscriber      The address of the subscriber
   * @param  subscriberId    The user ID of the subscriber
   * @param  rwaAmount       The amount of RWA tokens minted and/or transferred, in
   *                         decimals of the RWA token
   * @param  depositToken    The token deposited
   * @param  depositAmount   The amount of tokens deposited, in decimals of the
   *                         token
   * @param  depositUSDValue The USD value of the deposit, in 18 decimals
   * @param  fee             The fee charged for the subscription, in USD with 18 decimals
   */
  event Subscription(
    address indexed subscriber,
    bytes32 indexed subscriberId,
    uint256 rwaAmount,
    address depositToken,
    uint256 depositAmount,
    uint256 depositUSDValue,
    uint256 fee
  );

  /**
   * @notice Event emitted when a user redeems an RWA token
   * @param  redeemer           The address of the redeemer
   * @param  redeemerId         The user ID of the redeemer
   * @param  rwaAmount          The amount of RWA tokens redeemed, in decimals of
   *                            the RWA token
   * @param  receivingToken     The token received
   * @param  receiveTokenAmount The amount of tokens received, in decimals of the
   *                            token
   * @param  redemptionUSDValue The USD value of the redemption, in 18 decimals
   * @param  fee                The fee charged for the redemption, in USD with 18 decimals
   */
  event Redemption(
    address indexed redeemer,
    bytes32 indexed redeemerId,
    uint256 rwaAmount,
    address receivingToken,
    uint256 receiveTokenAmount,
    uint256 redemptionUSDValue,
    uint256 fee
  );

  /**
   * @notice Event emitted when an admin completes a subscription for a recipient
   * @param  adminCaller  The address of the admin account executing the subscription
   * @param  recipient    The address of the recipient that receives the RWA tokens
   * @param  recipientId  The user ID of the recipient
   * @param  rwaAmount    The amount of RWA tokens minted and/or transferred, in
   *                      decimals of the RWA token
   * @param  usdAmount    The USD value of the subscription, in 18 decimals
   * @param  metadata     Additional metadata to associate with the subscription
   */
  event AdminSubscription(
    address indexed adminCaller,
    address indexed recipient,
    bytes32 indexed recipientId,
    uint256 rwaAmount,
    uint256 usdAmount,
    bytes32 metadata
  );

  /**
   * @notice Event emitted when the `OndoTokenRouter` contract is set
   * @param  oldOndoTokenRouter The old `OndoTokenRouter` contract address
   * @param  newOndoTokenRouter The new `OndoTokenRouter` contract address
   */
  event OndoTokenRouterSet(address indexed oldOndoTokenRouter, address indexed newOndoTokenRouter);

  /**
   * @notice Event emitted when the `OndoOracle` contract is set
   * @param  oldOndoOracle The old `OndoOracle` contract address
   * @param  newOndoOracle The new `OndoOracle` contract address
   */
  event OndoOracleSet(address indexed oldOndoOracle, address indexed newOndoOracle);

  /**
   * @notice Event emitted when the `OndoCompliance` contract is set.
   * @param  oldOndoCompliance The old `OndoCompliance` contract address
   * @param  newOndoCompliance The new `OndoCompliance` contract address
   */
  event OndoComplianceSet(address indexed oldOndoCompliance, address indexed newOndoCompliance);

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
   * @notice Event emitted when the `OndoFees` subscription contract is set
   * @param  oldOndoSubscriptionFees The old `OndoFees` contract address for subscriptions
   * @param  newOndoSubscriptionFees The new `OndoFees` contract address for subscriptions
   */
  event OndoSubscriptionFeesSet(
    address indexed oldOndoSubscriptionFees, address indexed newOndoSubscriptionFees
  );

  /**
   * @notice Event emitted when the `OndoFees` redemption contract is set
   * @param  oldOndoRedemptionFees The old `OndoFees` contract address for redemptions
   * @param  newOndoRedemptionFees The new `OndoFees` contract address for redemptions
   */
  event OndoRedemptionFeesSet(
    address indexed oldOndoRedemptionFees, address indexed newOndoRedemptionFees
  );

  /**
   * @notice Event emitted when the `AdminSubscriptionChecker` contract is set
   * @param  oldAdminSubscriptionChecker The old `AdminSubscriptionChecker` contract address
   * @param  newAdminSubscriptionChecker The new `AdminSubscriptionChecker` contract address
   */
  event AdminSubscriptionCheckerSet(
    address indexed oldAdminSubscriptionChecker, address indexed newAdminSubscriptionChecker
  );

  /**
   * @notice Event emitted when a token's supported status is set for subscriptions
   * @param  token    The token address
   * @param  accepted Whether the token is accepted for deposit
   */
  event AcceptedSubscriptionTokenSet(address indexed token, bool indexed accepted);

  /**
   * @notice Event emitted when a token's supported status for redemptions
   * @param  token    The token address
   * @param  accepted Whether the token is accepted for redemption
   */
  event AcceptedRedemptionTokenSet(address indexed token, bool indexed accepted);

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
   * @notice Event emitted when the minimum RWA token price is set
   * @param  oldMinimumRwaPrice Old minimum RWA token price
   * @param  newMinimumRwaPrice New minimum RWA token price
   */
  event MinimumRwaPriceSet(uint256 indexed oldMinimumRwaPrice, uint256 indexed newMinimumRwaPrice);

  /// Event emitted when subscription functionality is paused
  event SubscribePaused();

  /// Event emitted when subscription functionality is unpaused
  event SubscribeUnpaused();

  /// Event emitted when redeem functionality is paused
  event RedeemPaused();

  /// Event emitted when redeem functionality is unpaused
  event RedeemUnpaused();
}
