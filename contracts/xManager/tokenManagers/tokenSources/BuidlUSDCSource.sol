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

import {BaseTokenSource} from "contracts/xManager/tokenManagers/tokenSources/BaseTokenSource.sol";
import {IERC20Metadata} from "contracts/external/openzeppelin/contracts/token/IERC20Metadata.sol";
import {IRedemption} from "contracts/external/circle/IRedemption.sol";
import {ISettlement} from "contracts/external/circle/ISettlement.sol";
import {PauseManagerClient} from "contracts/xManager/tokenManagers/PauseManagerClient.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";

/**
 * @title  BuidlUSDCSource
 * @author Ondo Finance
 * @notice This contract manages withdrawals of USDC sourced from this contract's balance or
 *         through redeeming the BUIDL token.
 * @dev    Off-chain processes ensure that sufficient USDC and/or BUIDL are available for
 *         withdrawal operations.
 */
contract BuidlUSDCSource is BaseTokenSource {
  /// Address of the USDC token
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable usdcTokenAddress;

  /// Address of the BUIDL token
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable buidlTokenAddress;

  /// Address of the BUIDLRedeemer contract
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  IRedemption public immutable buidlRedeemer;

  /// Minimum amount of BUIDL required to perform a BUIDL redemption
  uint256 public minBUIDLRedeemAmount;

  /// Expected number of decimals for USDC (used to detect token upgrades)
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  uint8 public immutable usdcDecimalsExpected;

  /// Expected number of decimals for BUIDL (used to detect token upgrades)
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  uint8 public immutable buidlDecimalsExpected;

  /**
   * @notice Emitted when the minimum BUIDL redemption amount is updated
   * @param oldMinBUIDLRedemptionAmount The previous minimum redemption amount
   * @param newMinBUIDLRedemptionAmount The updated minimum redemption amount
   */
  event MinimumBUIDLRedemptionAmountSet(
    uint256 oldMinBUIDLRedemptionAmount, uint256 newMinBUIDLRedemptionAmount
  );

  /**
   * @notice Emitted when a BUIDL redemption is unnecessary due to sufficient USDC in the contract
   * @param usdcAmountRedeemed  Amount of USDC sent back to the caller
   * @param usdcAmountRemaining Amount of USDC remaining in the contract
   */
  event BUIDLRedemptionSkipped(uint256 usdcAmountRedeemed, uint256 usdcAmountRemaining);

  /**
   * @notice Emitted when the minimum BUIDL redemption amount is redeemed
   * @param buidlAmountRedeemed Amount of BUIDL redeemed
   * @param usdcAmountKept      Amount of USDC retained in the contract
   */
  event MinimumBUIDLRedemption(uint256 buidlAmountRedeemed, uint256 usdcAmountKept);

  /**
   * @notice Error thrown when the amount of USDC received after a BUIDL redemption is less than
   *         expected.
   * @param tokenSource Address of the token source contract
   * @param amountExpected The amount of USDC expected to be received
   * @param amountReceived The actual amount of USDC received
   */
  error InvalidRedemptionRatio(address tokenSource, uint256 amountExpected, uint256 amountReceived);

  /**
   * @notice Error thrown when the token metadata does not match the expected decimals
   * @param tokenSource  Address of the token source contract
   * @param tokenAddress Address of the token with mismatched metadata
   */
  error UnexpectedTokenMetadata(address tokenSource, address tokenAddress);

  /**
   * @notice Error thrown when there isn't enough BUIDL in the contract to process a redemption
   * @param  tokenSource    Address of the token source contract
   * @param  availableBuidl The amount of BUIDL available for redemption
   */
  error InsufficientBuidlBalance(address tokenSource, uint256 availableBuidl);

  /**
   * @param _defaultAdmin         The address to be assigned the admin role
   * @param _usdcTokenAddress     The address of the USDC token
   * @param _buidlTokenAddress    The address of the BUIDL token
   * @param _minBUIDLRedeemAmount The minimum BUIDL amount required for redemption
   * @param _buidlRedeemer        The address of the BUIDLRedeemer contract
   * @param _pauseManager         The address of the pause manager
   * @dev   Ensures all critical addresses are non-zero and stores expected token decimals
   */
  constructor(
    address _defaultAdmin,
    address _usdcTokenAddress,
    address _buidlTokenAddress,
    uint256 _minBUIDLRedeemAmount,
    address _buidlRedeemer,
    address _pauseManager
  ) PauseManagerClient(_pauseManager) {
    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);

    if (_usdcTokenAddress == address(0)) revert ZeroAddressNotAllowed();
    if (_buidlTokenAddress == address(0)) revert ZeroAddressNotAllowed();
    if (_buidlRedeemer == address(0)) revert ZeroAddressNotAllowed();

    usdcTokenAddress = _usdcTokenAddress;
    buidlTokenAddress = _buidlTokenAddress;
    minBUIDLRedeemAmount = _minBUIDLRedeemAmount;
    buidlRedeemer = IRedemption(_buidlRedeemer);

    usdcDecimalsExpected = IERC20Metadata(_usdcTokenAddress).decimals();
    buidlDecimalsExpected = IERC20Metadata(_buidlTokenAddress).decimals();
  }

  /**
   * @notice Withdraws USDC, optionally redeeming BUIDL if necessary
   * @param  tokenToWithdraw         Address of the token to withdraw (must be USDC)
   * @param  requestedWithdrawAmount Amount of USDC to withdraw, in USDC's decimals
   */
  function withdrawToken(address tokenToWithdraw, uint256 requestedWithdrawAmount)
    external
    override
    onlyRole(WITHDRAWER_ROLE)
    whenSourceNotPaused
  {
    if (tokenToWithdraw != usdcTokenAddress) {
      revert InvalidTokenAddressForTokenSource();
    }

    assertTokenDecimalsMetaData();

    uint256 usdcBalanceBefore = IERC20(usdcTokenAddress).balanceOf(address(this));

    if (requestedWithdrawAmount <= usdcBalanceBefore) {
      emit BUIDLRedemptionSkipped(
        requestedWithdrawAmount, usdcBalanceBefore - requestedWithdrawAmount
      );
    } else if (requestedWithdrawAmount - usdcBalanceBefore >= minBUIDLRedeemAmount) {
      _redeemBUIDL(requestedWithdrawAmount - usdcBalanceBefore);
    } else {
      _redeemBUIDL(minBUIDLRedeemAmount);
      emit MinimumBUIDLRedemption(
        minBUIDLRedeemAmount, usdcBalanceBefore + minBUIDLRedeemAmount - requestedWithdrawAmount
      );
    }

    // forge-lint: disable-next-line(erc20-unchecked-transfer)
    IERC20(usdcTokenAddress).transfer(msg.sender, requestedWithdrawAmount);
    emit TokensWithdrawn(msg.sender, address(this), tokenToWithdraw, requestedWithdrawAmount);
  }

  /**
   * @notice Retrieves the available USDC for withdrawal
   * @param  tokenToWithdraw Address of the token to check (must be USDC)
   * @return The total amount of USDC available for withdrawal
   * @dev    Considers both the USDC balance and redeemable BUIDL
   */
  function availableToWithdraw(address tokenToWithdraw) public view override returns (uint256) {
    if (tokenToWithdraw != usdcTokenAddress) {
      revert InvalidTokenAddressForTokenSource();
    }
    // If this source is paused, 0 tokens are available for withdrawal.
    // We don't revert so other sources can still be queried.
    if (pauseManager.isTokenSourcePaused(address(this))) return 0;

    uint256 currentUSDCBalance = IERC20(usdcTokenAddress).balanceOf(address(this));

    uint256 currentBuidlBalance = IERC20(buidlTokenAddress).balanceOf(address(this));

    // If the BUIDL balance is below the minimum redemption amount, only USDC is available
    if (currentBuidlBalance < minBUIDLRedeemAmount) return currentUSDCBalance;

    uint256 availableRedeemerLiquidity =
      ISettlement(buidlRedeemer.settlement()).availableLiquidity();

    uint256 availableBuidlRedemptionTotal = currentBuidlBalance > availableRedeemerLiquidity
      ? availableRedeemerLiquidity
      : currentBuidlBalance;

    return currentUSDCBalance + availableBuidlRedemptionTotal;
  }

  /**
   * @notice Redeems BUIDL for USDC
   * @param  buidlAmountToRedeem The amount of BUIDL to redeem
   * @dev    Reverts if BUIDL redemption rate with USDC is worse than 1:1
   */
  function _redeemBUIDL(uint256 buidlAmountToRedeem) internal {
    uint256 buidlBalance = IERC20(buidlTokenAddress).balanceOf(address(this));
    if (buidlBalance < buidlAmountToRedeem) {
      revert InsufficientBuidlBalance(address(this), buidlBalance);
    }

    uint256 usdcBalanceBefore = IERC20(usdcTokenAddress).balanceOf(address(this));
    IERC20(buidlTokenAddress).approve(address(buidlRedeemer), buidlAmountToRedeem);

    buidlRedeemer.redeem(buidlAmountToRedeem);

    uint256 newUSDCBalance = IERC20(usdcTokenAddress).balanceOf(address(this));
    if (newUSDCBalance < usdcBalanceBefore + buidlAmountToRedeem) {
      revert InvalidRedemptionRatio(
        address(this), buidlAmountToRedeem, newUSDCBalance - usdcBalanceBefore
      );
    }
  }

  /**
   * @notice Validates that token decimals match expected metadata
   * @dev    Protects against token upgrades that alter decimals
   */
  function assertTokenDecimalsMetaData() internal view {
    if (IERC20Metadata(usdcTokenAddress).decimals() != usdcDecimalsExpected) {
      revert UnexpectedTokenMetadata(address(this), usdcTokenAddress);
    }
    if (IERC20Metadata(buidlTokenAddress).decimals() != buidlDecimalsExpected) {
      revert UnexpectedTokenMetadata(address(this), buidlTokenAddress);
    }
  }

  /**
   * @notice Updates the minimum BUIDL redemption amount
   * @param  _minimumBUIDLRedemptionAmount The new minimum redemption amount
   * @dev    Emits `MinimumBUIDLRedemptionAmountSet` event
   */
  function setMinimumBUIDLRedemptionAmount(uint256 _minimumBUIDLRedemptionAmount)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    emit MinimumBUIDLRedemptionAmountSet(minBUIDLRedeemAmount, _minimumBUIDLRedemptionAmount);
    minBUIDLRedeemAmount = _minimumBUIDLRedemptionAmount;
  }
}
