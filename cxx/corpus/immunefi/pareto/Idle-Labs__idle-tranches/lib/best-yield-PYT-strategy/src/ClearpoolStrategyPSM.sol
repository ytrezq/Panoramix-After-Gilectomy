// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

/**
 * @title: Idle Perpertual Yield Tranches wrapper for senior tranche
 * @summary: Used for interacting with Idle senior PYTs. Has
 *           a common interface with all other protocol wrappers.
 *           This contract holds assets only during a tx, after tx it should be empty
 * @author: Idle Labs Inc., idle.finance
 */
import "@oz-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@oz-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./Contract.sol";
import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IIdleCDOStrategyClear.sol";
import "./interfaces/IPoolMaster.sol";

// This contract should be deployed with a minimal proxy factory
contract IdlePYTClearPSM is IdlePYT {
  uint256 public constant SCALE_FACTOR = 1e12; // diff betweet USDC and DAI decimals

  /**
   * Get the underlying balance available on the lending protocol
   *
   * @return underlying tokens available
   */
  function availableLiquidity() external override view returns (uint256) {
    IIdleCDO _cdo = idleCDO;
    IPoolMaster cpToken = IPoolMaster(IIdleCDOStrategyClear(_cdo.strategy()).cpToken());
    return underlyingContract.balanceOf(address(_cdo)) + 
      // availableToWithdraw is in USDC
      cpToken.availableToWithdraw() * SCALE_FACTOR;
  }
}
