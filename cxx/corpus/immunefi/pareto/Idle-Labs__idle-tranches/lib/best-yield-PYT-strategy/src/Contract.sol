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
import "./interfaces/ILendingProtocol.sol";
import "./interfaces/IIdleCDO.sol";
import "./interfaces/IIdleCDOStrategy.sol";

// This contract should be deployed with a minimal proxy factory
contract IdlePYT is ILendingProtocol {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  address public idleToken;
  // protocol token (AA_tranche_token) address
  address public override token;
  // underlying token (token eg DAI) address
  address public override underlying;
  IERC20Upgradeable public tokenContract;
  IERC20Upgradeable public underlyingContract;

  // contract used for minting/burning tranche tokens
  IIdleCDO public idleCDO;
  // Used for calculating the nextRate
  uint256 internal constant AA_RATIO_LIM_UP = 99000;
  uint256 internal constant AA_RATIO_LIM_DOWN = 50000;
  uint256 internal constant FULL_ALLOC = 100000;
  uint256 internal constant ONE_TRANCHE = 1e18;
  bool public isSenior;

  // Errors
  error Initialized();
  error Unauthorized();

  /**
   * @param _token : tranche token address
   * @param _idleToken : idleToken address
   * @param _cdo : IdleCDO contract address for minting tranche tokens
   */
  function initialize(
    address _token, 
    address _idleToken, 
    address _cdo
  ) external {
    if (address(token) != address(0)) {
      revert Initialized();
    }

    idleCDO = IIdleCDO(_cdo);
    token = _token;
    isSenior = idleCDO.AATranche() == _token;
    tokenContract = IERC20Upgradeable(_token);
    underlying = idleCDO.token();
    underlyingContract = IERC20Upgradeable(idleCDO.token());
    idleToken = _idleToken;
    underlyingContract.safeApprove(_cdo, type(uint256).max);
  }

  /**
   * Throws if called by any account other than IdleToken contract.
   */
  function _onlyIdle() internal view {
    if (msg.sender != idleToken) revert Unauthorized();
  }

  /**
   * Calculate next supply rate for Compound, given an `_amount` supplied
   *
   * @notice this is used for off-chain calculations
   * @param _amount : new underlying amount supplied (eg DAI)
   * @return newAAApr : yearly net rate
   */
  function nextSupplyRate(uint256 _amount)
    external view virtual
    returns (uint256 newAAApr) {
      IERC20Upgradeable _token = IERC20Upgradeable(token);
      IIdleCDO _idleCDO = idleCDO;
      uint256 _tvl = _idleCDO.getContractValue();
      // we use tranchePrice instead of virtualPrice for more efficiency as interest accrued wont 
      // affect too much TVL
      uint256 _tvlAA = _token.totalSupply() * _idleCDO.tranchePrice(address(_token)) / ONE_TRANCHE;
      uint256 _newTvlRatio = (_tvlAA + _amount) * FULL_ALLOC / (_tvl + _amount);
      uint256 _newAprRatio  = _calcNewAPRSplit(_newTvlRatio);
      // we need to get the underlying strategy apr here to calculate the new apr for the tranche
      IIdleCDOStrategy innerStrategy = IIdleCDOStrategy(_idleCDO.strategy());
      // TODO in new CDO strategies we should support a getApr(_amount) similar to nextSupplyRate
      // so to calculate also the impact on the underlying lending protocol used by the PYT. This 
      // can be calculated off-chain in the meantime for the optimal rebalance amount
      newAAApr = innerStrategy.getApr() * _newAprRatio / _newTvlRatio;
      newAAApr = newAAApr * (FULL_ALLOC - idleCDO.fee()) / FULL_ALLOC;
  }

  /**
   * @return current price of tranche token
   */
  function getPriceInToken()
    external view
    returns (uint256) {
      return idleCDO.virtualPrice(address(token));
  }

  /**
   * @return _apr current apr
   */
  function getAPR()
    external view
    returns (uint256 _apr) {
      _apr = idleCDO.getApr(address(token));
      _apr = _apr * (FULL_ALLOC - idleCDO.fee()) / FULL_ALLOC;
  }

  /**
   * Gets all underlying tokens in this contract and mints cTokenLike Tokens
   * tokens are then transferred to msg.sender
   * NOTE: underlying tokens needs to be sent here before calling this
   *
   * @return minted : tranche tokens minted
   */
  function mint()
    external virtual
    returns (uint256 minted) {
      _onlyIdle();
      uint256 balance = underlyingContract.balanceOf(address(this));
      if (balance != 0) {
        if (isSenior) {
          idleCDO.depositAA(balance);
        } else {
          idleCDO.depositBB(balance);
        }
        IERC20Upgradeable _token = tokenContract;
        minted = _token.balanceOf(address(this));
        _token.safeTransfer(msg.sender, minted);
      }
  }

  /**
   * Gets all cTokenLike in this contract and redeems underlying tokens.
   * underlying tokens are then transferred to `_account`
   * NOTE: cTokenLike needs to be sent here before calling this
   *
   * @return tokens underlying tokens redeemd
   */
  function redeem(address _account)
    external virtual
    returns (uint256 tokens) {
      _onlyIdle();
      uint256 _bal = tokenContract.balanceOf(address(this));
      if (isSenior) {
        idleCDO.withdrawAA(_bal);
      } else {
        idleCDO.withdrawBB(_bal);
      }
      IERC20Upgradeable _underlying = underlyingContract;
      tokens = _underlying.balanceOf(address(this));
      _underlying.safeTransfer(_account, tokens);
  }

  /**
   * Get the underlying balance available on the lending protocol
   *
   * @return underlying tokens available
   */
  function availableLiquidity() external virtual view returns (uint256) {
    return idleCDO.getContractValue();
  }

  /**
   * Get the new apr split ratio in IdleCDO. Taken from here https://github.com/Idle-Labs/idle-tranches/blob/448c707a690e20bf2ef3e5a233fa97a329b34eb0/contracts/IdleCDO.sol#L454
   *
   * @return _new new apr split ratio for IdleCDO
   */
  function _calcNewAPRSplit(uint256 ratio) internal pure returns (uint256 _new){
    uint256 aux;
    if (ratio >= AA_RATIO_LIM_UP) {
      aux = AA_RATIO_LIM_UP;
    } else if (ratio > AA_RATIO_LIM_DOWN) {
      aux = ratio;
    } else {
      aux = AA_RATIO_LIM_DOWN;
    }
    _new = aux * ratio / FULL_ALLOC;
  }
}
