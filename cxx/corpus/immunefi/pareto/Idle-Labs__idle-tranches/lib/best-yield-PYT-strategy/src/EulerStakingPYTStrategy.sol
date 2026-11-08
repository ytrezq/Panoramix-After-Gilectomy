// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

/**
 * @title: Idle Perpertual Yield Tranches wrapper for senior tranche of the Euler staking PYT
 * @summary: Used for interacting with Idle senior PYTs. Has
 *           a common interface with all other protocol wrappers.
 *           This contract holds assets only during a tx, after tx it should be empty
 * @author: Idle Labs Inc., idle.finance
 */
import "@oz-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "@oz-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./Contract.sol";
import "./interfaces/IIdleCDOStrategy.sol";

// This contract should be deployed with a minimal proxy factory
contract EulerStakingPYTStrategy is IdlePYT {
  address internal constant EULER_MAIN = 0x27182842E098f60e3D576794A5bFFb0777E025d3;

  /**
   * Get the underlying balance available on the lending protocol
   *
   * @return underlying tokens available
   */
  function availableLiquidity() external override view returns (uint256) {
    return underlyingContract.balanceOf(address(idleCDO)) + 
           underlyingContract.balanceOf(EULER_MAIN);
  }
}
