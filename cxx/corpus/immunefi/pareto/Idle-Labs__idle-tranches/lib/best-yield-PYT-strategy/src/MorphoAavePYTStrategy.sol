// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

/**
 * @title: Idle Perpertual Yield Tranches wrapper for senior tranche of the Euler staking PYT
 * @summary: Used for interacting with Idle senior PYTs. Has
 *           a common interface with all other protocol wrappers.
 *           This contract holds assets only during a tx, after tx it should be empty
 * @author: Idle Labs Inc., idle.finance
 */
import "./Contract.sol";

interface IMAToken {
  // aToken address
  function poolToken() external view returns (address);
}

// This contract should be deployed with a minimal proxy factory
contract MorphoAavePYTStrategy is IdlePYT {
  /**
   * Get the underlying balance available on the lending protocol
   *
   * @return underlying tokens available
   */
  function availableLiquidity() external override view returns (uint256) {
    IIdleCDO _idleCDO = idleCDO;
    IERC20Upgradeable _underlyingContract = underlyingContract;
    address aToken = IMAToken(_idleCDO.strategyToken()).poolToken();
    // From Morpho team: Morpho can fulfill withdraws with more than just its aToken balance. 
    // It will, if necessary, borrow the assets to fulfill withdraws. 
    // So here we assume that Morpho have the same available liquidity as Aave
    return _underlyingContract.balanceOf(address(_idleCDO)) + _underlyingContract.balanceOf(aToken);
  }
}
