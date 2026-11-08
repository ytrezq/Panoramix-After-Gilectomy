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
import {PsmLike} from "contracts/external/maker/PsmLike.sol";
import {ITokenSource} from "contracts/xManager/interfaces/ITokenSource.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {PauseManagerClient} from "contracts/xManager/tokenManagers/PauseManagerClient.sol";

/**
 * @title  PSMSource
 * @author Ondo Finance
 * @notice This token source allows for USDC and USDS to be used as backup token sources for each
 *         other via using the Sky PSM contract to convert between the two.
 * @dev    This contract must be granted the WITHDRAWER_ROLE on the USDS and USDC sources to
 *         function properly (assuming those sources properly implement the ITokenSource standard).
 */
contract PSMSource is BaseTokenSource {
  /// Address from which USDS tokens are withdrawn
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  ITokenSource public immutable usdsSource;

  /// Address from which USDC tokens are withdrawn
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  ITokenSource public immutable usdcSource;

  /// The USDS token
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  IERC20 public immutable usds;

  /// The USDC token
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  IERC20 public immutable usdc;

  /// The DAI token
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  IERC20 public immutable dai;

  /// The address of the PSM contract
  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  PsmLike public immutable psm;

  /// Constant used to normalize between USDC and USDS decimals
  // forge-lint: disable-next-line(screaming-snake-case-const)
  uint256 public constant usdcToUsdsDecimalConversionRate = 1e12;

  /// Error thrown if the PSM fee isn't zero as expected
  error FeeNotZero();

  /// Error thrown when the PSM swap doesn't increase the USDC balance as expected
  error InvalidPSMSwap();

  /**
   * @param  _defaultAdmin Address granted the admin role
   * @param  _usdsSource   Address of the USDS source
   * @param  _usdcSource   Address of the USDC source
   * @param  _usds         Address of the USDS token
   * @param  _usdc         Address of the USDC token
   * @param  _psm          Address of the PSM contract
   * @param  _pauseManager Address of the pause manager contract
   */
  constructor(
    address _defaultAdmin,
    address _usdsSource,
    address _usdcSource,
    address _usds,
    address _usdc,
    address _dai,
    address _psm,
    address _pauseManager
  ) PauseManagerClient(_pauseManager) {
    // Set the default admin role
    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);

    // Ensure the withdraw and token addresses are valid
    if (_usdsSource == address(0)) revert ZeroAddressNotAllowed();
    if (_usdcSource == address(0)) revert ZeroAddressNotAllowed();
    if (_usds == address(0)) revert ZeroAddressNotAllowed();
    if (_usdc == address(0)) revert ZeroAddressNotAllowed();
    if (_dai == address(0)) revert ZeroAddressNotAllowed();
    if (_psm == address(0)) revert ZeroAddressNotAllowed();

    usdsSource = ITokenSource(_usdsSource);
    usdcSource = ITokenSource(_usdcSource);
    usds = IERC20(_usds);
    usdc = IERC20(_usdc);
    dai = IERC20(_dai);
    psm = PsmLike(_psm);
  }

  /**
   * @notice Withdraws USDS or USDC and converts to the other token
   * @param  tokenToWithdraw         Address of the token to withdraw (must be USDS or USDC)
   * @param  requestedWithdrawAmount Amount of token to withdraw, denominated in decimals of
   *                                 `tokenToWithdraw`
   */
  function withdrawToken(address tokenToWithdraw, uint256 requestedWithdrawAmount)
    external
    override
    onlyRole(WITHDRAWER_ROLE)
    whenSourceNotPaused
  {
    // Withdraw the requested amount of tokens
    if (tokenToWithdraw == address(usds)) {
      _handleWithdrawUSDS(requestedWithdrawAmount);
    } else if (tokenToWithdraw == address(usdc)) {
      _handleWithdrawUSDC(requestedWithdrawAmount);
    } else {
      revert InvalidTokenAddressForTokenSource();
    }

    emit TokensWithdrawn(
      msg.sender,
      tokenToWithdraw == address(usds) ? address(usdcSource) : address(usdsSource),
      tokenToWithdraw,
      requestedWithdrawAmount
    );
  }

  /**
   * @notice Handles the withdraw of USDC by pulling USDS from the USDS source and converting to USDC
   * @param  usdcAmountNeeded Amount of USDC to withdraw
   * @dev    This function will revert if the PSM fee is not zero or the swap does not increase the
   *         USDC balance as expected.
   */
  function _handleWithdrawUSDC(uint256 usdcAmountNeeded) internal {
    // Ensure that the fee is zero for buyGem
    if (psm.tout() != 0) revert FeeNotZero();

    uint256 usdsAmountToSwap = usdcAmountNeeded * usdcToUsdsDecimalConversionRate;
    // Pull USDS from the USDS source into this contract
    usdsSource.withdrawToken(address(usds), usdsAmountToSwap);

    usds.approve(address(psm), usdsAmountToSwap);

    // USDC amount will be received directly by the withdrawer
    uint256 usdcBalanceBefore = usdc.balanceOf(msg.sender);
    // PSM expects buyGem to be called with the USDC amount, not the USDS amount
    psm.buyGem(msg.sender, usdcAmountNeeded);

    // Assert that the USDC balance of the withdrawer has increased by the expected amount
    if (usdc.balanceOf(msg.sender) - usdcBalanceBefore < usdcAmountNeeded) {
      revert InvalidPSMSwap();
    }
  }

  /**
   * @notice Handles the withdraw of USDS by pulling USDC from the USDC source and converting to USDS
   * @param  usdsAmountNeeded Amount of USDS to withdraw
   * @dev    This function will revert if the PSM fee is not zero or the swap does not increase the
   *         USDS balance as expected.
   */
  function _handleWithdrawUSDS(uint256 usdsAmountNeeded) internal {
    // Check that the fee is zero for sellGem
    if (psm.tin() != 0) revert FeeNotZero();

    // The smallest unit of USDC is 1e-6 while USDS is 1e-18, so this will ensure enough USDC is
    // pulled to cover the USDS amount by rounding up
    // ref: https://github.com/balancer/balancer-v2-monorepo/blob/master/pkg/solidity-utils/contracts/math/FixedPoint.sol#L61-L64
    // divUp(x, y) := (x + y - 1) / y
    uint256 usdcAmountNeeded =
      (usdsAmountNeeded + usdcToUsdsDecimalConversionRate - 1) / usdcToUsdsDecimalConversionRate;

    // Pull USDC from the USDC source
    usdcSource.withdrawToken(address(usdc), usdcAmountNeeded);

    usdc.approve(address(psm), usdcAmountNeeded);

    uint256 usdsBalanceBefore = usds.balanceOf(address(this));
    // USDS amount will be received here so that the exact amount can be transferred to the
    // and dust can be left in this contract
    psm.sellGem(address(this), usdcAmountNeeded);
    // Assert that the USDS balance of the contract has increased by the expected amount
    if (usds.balanceOf(address(this)) - usdsBalanceBefore < usdsAmountNeeded) {
      revert InvalidPSMSwap();
    }

    // Transfer the exact amount of USDS to the withdraw address
    // forge-lint: disable-next-line(erc20-unchecked-transfer)
    usds.transfer(msg.sender, usdsAmountNeeded);
  }

  /**
   * @notice Retrieves the available USDS or USDC for withdrawal
   * @param  tokenToWithdraw Address of the token to check (must be USDS or USDC)
   * @return The total amount of `tokenToWithdraw` available for withdrawal
   * @dev    Considers both the source balances and PSM balances as needed
   */
  function availableToWithdraw(address tokenToWithdraw) public view override returns (uint256) {
    // If this source is paused, 0 tokens are available for withdrawal.
    // We don't revert so other sources can still be queried.
    if (pauseManager.isTokenSourcePaused(address(this))) return 0;

    if (tokenToWithdraw == address(usds)) {
      // The USDS PSM pulls DAI from the DAI PSM, so we must consider the DAI balance of the PSM
      uint256 psmDaiBalance = dai.balanceOf(psm.psm());
      uint256 usdcSourceBalance =
        usdcSource.availableToWithdraw(address(usdc)) * usdcToUsdsDecimalConversionRate;

      return usdcSourceBalance < psmDaiBalance ? usdcSourceBalance : psmDaiBalance;
    } else if (tokenToWithdraw == address(usdc)) {
      // For USDC, the USDC available via the PSM also needs to be considered
      uint256 usdsAvailableFromSourceScaledToUSDC =
        usdsSource.availableToWithdraw(address(usds)) / usdcToUsdsDecimalConversionRate;
      uint256 usdcBalanceOfPsm = usdc.balanceOf(psm.pocket());

      // Take the lesser of the two
      return usdsAvailableFromSourceScaledToUSDC < usdcBalanceOfPsm
        ? usdsAvailableFromSourceScaledToUSDC
        : usdcBalanceOfPsm;
    } else {
      revert InvalidTokenAddressForTokenSource();
    }
  }
}
