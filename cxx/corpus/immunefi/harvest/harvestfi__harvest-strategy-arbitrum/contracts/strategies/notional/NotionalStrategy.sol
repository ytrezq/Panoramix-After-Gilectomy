//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/notional/IPrimeToken.sol";
import "../../base/interface/notional/INProxy.sol";
import "../../base/interface/weth/IWETH.sol";

contract NotionalStrategy is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);
  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant usdc_bridged = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
  address public constant usdc_native = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _N_PROXY_SLOT = 0x67fd3246a4588df947995025dbc3c07f488375e3daeac5ba64360dc24b94304b;

  // this would be reset on each upgrade
  address[] public rewardTokens;

  constructor() BaseUpgradeableStrategy() {
    assert(_N_PROXY_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.nProxy")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _nProxy,
    address _rewardToken
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _nProxy,
      _rewardToken,
      harvestMSIG
    );

    _setNProxy(_nProxy);
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function _rewardPoolBalance() internal view returns (uint256 balance) {
    balance = IERC20(underlying()).balanceOf(address(this));
  }

  /*
  *   In case there are some issues discovered about the pool or underlying asset
  *   Governance can exit the pool properly
  *   The function is only used for emergency to exit the pool
  */
  function emergencyExit() public onlyGovernance {
    _setPausedInvesting(true);
  }

  /*
  *   Resumes the ability to invest into the underlying reward pools
  */
  function continueInvesting() public onlyGovernance {
    _setPausedInvesting(false);
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying());
  }

  function addRewardToken(address _token) public onlyGovernance {
    rewardTokens.push(_token);
  }

  function _liquidateReward() internal {
    if (!sell()) {
      // Profits can be disabled for possible simplified and rapid exit
      emit ProfitsNotCollected(sell(), false);
      return;
    }
    address _rewardToken = rewardToken();
    address _universalLiquidator = universalLiquidator();
    for(uint256 i = 0; i < rewardTokens.length; i++){
      address token = rewardTokens[i];
      uint256 rewardBalance = IERC20(token).balanceOf(address(this));
      if (rewardBalance == 0) {
        continue;
      }
      if (token != _rewardToken){
          IERC20(token).safeApprove(_universalLiquidator, 0);
          IERC20(token).safeApprove(_universalLiquidator, rewardBalance);
          IUniversalLiquidator(_universalLiquidator).swap(token, _rewardToken, rewardBalance, 1, address(this));
      }
    }

    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    _notifyProfitInRewardToken(_rewardToken, rewardBalance);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance < 1e4) {
      return;
    }

    address _depositToken = IPrimeToken(underlying()).asset();
    if (_depositToken == usdc_bridged) {
      _depositToken = usdc_native;
    }
    if (_depositToken != _rewardToken) {
      IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
      IERC20(_rewardToken).safeApprove(_universalLiquidator, remainingRewardBalance);
      IUniversalLiquidator(_universalLiquidator).swap(_rewardToken, _depositToken, remainingRewardBalance, 1, address(this));
    }

    uint256 tokenBalance = IERC20(_depositToken).balanceOf(address(this));
    if (tokenBalance > 0 && !(_depositToken == underlying())) {
      depositLP(_depositToken, tokenBalance);
    }
  }

  function depositLP(address token, uint256 balance) internal {
    address _nProxy = nProxy();
    uint16 currencyId;
    uint256 value;
    if (token == weth) {
      currencyId = uint16(1);
      IWETH(weth).withdraw(balance);
      value = balance;
    } else if (token == usdc_native) {
      currencyId = uint16(3);
    } else {
      currencyId = INProxy(_nProxy).getCurrencyId(token);
    }

    INProxy.BalanceAction[] memory actions = new INProxy.BalanceAction[](1);
    INProxy.BalanceAction memory action;
    action.actionType = INProxy.DepositActionType.DepositUnderlyingAndMintNToken;
    action.currencyId = currencyId;
    action.depositActionAmount = balance;
    action.withdrawAmountInternalPrecision = 0;
    action.withdrawEntireCashBalance = false;
    action.redeemToUnderlying = true;

    actions[0] = action;
    if (token != weth) {
      IERC20(token).safeApprove(_nProxy, 0);
      IERC20(token).safeApprove(_nProxy, balance);
    }
    INProxy(_nProxy).batchBalanceAction{value: value}(address(this), actions);
  }

  /** Withdraws all the asset to the vault
   */
  function withdrawAllToVault() public restricted {
    address _underlying = underlying();
    _liquidateReward();
    IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
  }

  /** Withdraws specific amount of asset to the vault
   */
  function withdrawToVault(uint256 amount) public restricted {
    IERC20(underlying()).safeTransfer(vault(), amount);
  }

  /*
  *   Note that we currently do not have a mechanism here to include the
  *   amount of reward that is accrued.
  */
  function investedUnderlyingBalance() external view returns (uint256) {
    // Adding the amount locked in the reward pool and the amount that is somehow in this contract
    // both are in the units of "underlying"
    // The second part is needed because there is the emergency exit mechanism
    // which would break the assumption that all the funds are always inside of the reward pool
    return _rewardPoolBalance();
  }

  /*
  *   Governance or Controller can claim coins that are somehow transferred into the contract
  *   Note that they cannot come in take away coins that are used and defined in the strategy itself
  */
  function salvage(address recipient, address token, uint256 amount) external onlyControllerOrGovernance {
     // To make sure that governance cannot come in and take away the coins
    require(!unsalvagableTokens(token), "token is defined as not salvagable");
    IERC20(token).safeTransfer(recipient, amount);
  }

  /*
  *   Get the reward, sell it in exchange for underlying, invest what you got.
  *   It's not much, but it's honest work.
  *
  *   Note that although `onlyNotPausedInvesting` is not added here,
  *   calling `investAllUnderlying()` affectively blocks the usage of `doHardWork`
  *   when the investing is being paused by governance.
  */
  function doHardWork() external onlyNotPausedInvesting restricted {
    INProxy(nProxy()).nTokenClaimIncentives();
    _liquidateReward();
  }

  function _setNProxy(address _value) internal {
    setAddress(_N_PROXY_SLOT, _value);
  }

  function nProxy() public view returns (address) {
    return getAddress(_N_PROXY_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }

  receive() external payable {} // this is needed for the receiving Matic
}
