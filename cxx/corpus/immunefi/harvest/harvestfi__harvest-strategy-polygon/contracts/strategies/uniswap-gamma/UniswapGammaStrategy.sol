//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../base/upgradability/BaseUpgradeableStrategyV2.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/interface/gamma/IHypervisor.sol";
import "../../base/interface/gamma/IUniProxy.sol";
import "../../base/interface/gamma/IStakingRewards.sol";
import "../../base/interface/gamma/IClearing.sol";
import "../../base/interface/uniswap/IUniswapV3Pool.sol";

contract UniswapGammaStrategy is BaseUpgradeableStrategyV2 {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant harvestMSIG = address(0x39cC360806b385C96969ce9ff26c23476017F652);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _UNIPROXY_SLOT = 0x09ff9720152edb4fad4ed05a0b77258f0fce17715f9397342eb08c8d7f965234;

  // this would be reset on each upgrade
  address[] public rewardTokens;

  constructor() public BaseUpgradeableStrategyV2() {
    assert(_UNIPROXY_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.uniProxy")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _rewardPool,
    address _rewardToken,
    address _uniProxy
  ) public initializer {

    BaseUpgradeableStrategyV2.initialize(
      _storage,
      _underlying,
      _vault,
      _rewardPool,
      _rewardToken,
      harvestMSIG
    );

    address _lpt = IStakingRewards(_rewardPool).stakingToken();
    require(_lpt == underlying(), "Pool Info does not match underlying");
    setAddress(_UNIPROXY_SLOT, _uniProxy);
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function rewardPoolBalance() internal view returns (uint256 bal) {
      bal = IStakingRewards(rewardPool()).balanceOf(address(this));
  }

  function exitRewardPool() internal {
      uint256 bal = rewardPoolBalance();
      if (bal != 0) {
          IStakingRewards(rewardPool()).exit();
      }
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying());
  }

  function enterRewardPool() internal {
    address _underlying = underlying();
    address _rewardPool = rewardPool();
    uint256 entireBalance = IERC20(_underlying).balanceOf(address(this));
    IERC20(_underlying).safeApprove(_rewardPool, 0);
    IERC20(_underlying).safeApprove(_rewardPool, entireBalance);
    IStakingRewards(_rewardPool).stake(entireBalance);
  }

  /*
  *   Resumes the ability to invest into the underlying reward pools
  */
  function continueInvesting() public onlyGovernance {
    _setPausedInvesting(false);
  }

  function addRewardToken(address _token) public onlyGovernance {
    rewardTokens.push(_token);
  }

  // We assume that all the tradings can be done on Uniswap
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

    if (remainingRewardBalance < 1e15) {
      return;
    }

    _depositToGamma();
  }

  function _depositToGamma() internal {
    address _underlying = underlying();
    address _clearing = IUniProxy(uniProxy()).clearance();
    address _token0 = IHypervisor(_underlying).token0();
    address _token1 = IHypervisor(_underlying).token1();
    (uint256 toToken0, uint256 toToken1) = _calculateToTokenAmounts();
    (uint256 amount0, uint256 amount1) = _swapToTokens(_token0, _token1, toToken0, toToken1);
    (uint256 min1, uint256 max1) = IClearing(_clearing).getDepositAmount(_underlying, _token0, amount0);
    if (amount1 < min1) {
      (,uint256 max0) = IClearing(_clearing).getDepositAmount(_underlying, _token1, amount1);
      if (amount0 > max0) {
        amount0 = max0;
      }
    } else if (amount1 > max1) {
      amount1 = max1;
    }

    uint256[4] memory minIn = [uint(0), uint(0), uint(0), uint(0)];

    IERC20(_token0).safeApprove(_underlying, 0);
    IERC20(_token0).safeApprove(_underlying, amount0);
    IERC20(_token1).safeApprove(_underlying, 0);
    IERC20(_token1).safeApprove(_underlying, amount1);
    IUniProxy(uniProxy()).deposit(amount0, amount1, address(this), _underlying, minIn);
  }

  /**
  * @dev Convenience getter for the current sqrtPriceX96 of the Uniswap pool.
  */
  function getSqrtPriceX96() public view returns(uint160) {
    address _underlying = underlying();
    address poolAddr = IHypervisor(_underlying).pool();
    (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddr).slot0();
    return sqrtPriceX96;
  }

  function _calculateToTokenAmounts() internal view returns(uint256, uint256){
    address pool = underlying();
    (uint256 poolBalance0, uint256 poolBalance1) = IHypervisor(pool).getTotalAmounts();
    uint256 sqrtPrice0In1 = uint256(getSqrtPriceX96());
    uint256 price0In1 = sqrtPrice0In1.mul(sqrtPrice0In1).div(uint(2**(96 * 2)).div(1e18));
    uint256 totalPoolBalanceIn1 = poolBalance0.mul(price0In1).div(1e18).add(poolBalance1);
    uint256 poolWeight0 = poolBalance0.mul(price0In1).div(totalPoolBalanceIn1);

    uint256 rewardBalance = IERC20(rewardToken()).balanceOf(address(this));
    uint256 toToken0 = rewardBalance.mul(poolWeight0).div(1e18);
    uint256 toToken1 = rewardBalance.sub(toToken0);
    return (toToken0, toToken1);
  }

  function _swapToTokens(
    address tokenOut0,
    address tokenOut1,
    uint256 toToken0,
    uint256 toToken1
  ) internal returns(uint256, uint256){
    address tokenIn = rewardToken();
    address _universalLiquidator = universalLiquidator();
    uint256 token0Amount;
    if (tokenIn != tokenOut0){
      IERC20(tokenIn).safeApprove(_universalLiquidator, 0);
      IERC20(tokenIn).safeApprove(_universalLiquidator, toToken0);
      IUniversalLiquidator(_universalLiquidator).swap(tokenIn, tokenOut0, toToken0, 1, address(this));
      token0Amount = IERC20(tokenOut0).balanceOf(address(this));
    } else {
      // otherwise we assme token0 is the reward token itself
      token0Amount = toToken0;
    }

    uint256 token1Amount;
    if (tokenIn != tokenOut1){
      IERC20(tokenIn).safeApprove(_universalLiquidator, 0);
      IERC20(tokenIn).safeApprove(_universalLiquidator, toToken1);
      IUniversalLiquidator(_universalLiquidator).swap(tokenIn, tokenOut1, toToken1, 1, address(this));
      token1Amount = IERC20(tokenOut1).balanceOf(address(this));
    } else {
      // otherwise we assme token0 is the reward token itself
      token1Amount = toToken1;
    }
    return (token0Amount, token1Amount);
  }

  /*
  *   Stakes everything the strategy holds into the reward pool
  */
  function investAllUnderlying() internal onlyNotPausedInvesting {
    // this check is needed, because most of the SNX reward pools will revert if
    // you try to stake(0).
    if(IERC20(underlying()).balanceOf(address(this)) > 0) {
      enterRewardPool();
    }
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawAllToVault() public restricted {
    address _underlying = underlying();
    if (address(rewardPool()) != address(0)) {
      exitRewardPool();
    }
    _liquidateReward();
    IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawToVault(uint256 amount) public restricted {
    // Typically there wouldn't be any amount here
    // however, it is possible because of the emergencyExit
    address _underlying = underlying();
    uint256 entireBalance = IERC20(_underlying).balanceOf(address(this));

    if(amount > entireBalance){
      // While we have the check above, we still using SafeMath below
      // for the peace of mind (in case something gets changed in between)
      uint256 needToWithdraw = amount.sub(entireBalance);
      uint256 toWithdraw = Math.min(rewardPoolBalance(), needToWithdraw);
      IStakingRewards(rewardPool()).withdraw(toWithdraw);
    }

    IERC20(_underlying).safeTransfer(vault(), amount);
  }

  /*
  *   Note that we currently do not have a mechanism here to include the
  *   amount of reward that is accrued.
  */
  function investedUnderlyingBalance() external view returns (uint256) {
    address _underlying = underlying();
    if (rewardPool() == address(0)) {
      return IERC20(_underlying).balanceOf(address(this));
    }
    // Adding the amount locked in the reward pool and the amount that is somehow in this contract
    // both are in the units of "underlying"
    // The second part is needed because there is the emergency exit mechanism
    // which would break the assumption that all the funds are always inside of the reward pool
    return rewardPoolBalance().add(IERC20(_underlying).balanceOf(address(this)));
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
    IStakingRewards(rewardPool()).getReward();
    _liquidateReward();
    investAllUnderlying();
  }

  /**
  * Can completely disable claiming rewards and selling. Good for emergency withdraw in the
  * simplest possible way.
  */
  function setSell(bool s) public onlyGovernance {
    _setSell(s);
  }

  function _setUniProxy(address _value) public onlyGovernance {
    setAddress(_UNIPROXY_SLOT, _value);
  }

  function uniProxy() public view returns (address) {
    return getAddress(_UNIPROXY_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }
}
