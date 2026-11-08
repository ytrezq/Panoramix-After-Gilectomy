// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../base/interface/uniswap/IUniswapV2Router02.sol";
import "../../base/interface/IVault.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/sushi/IMasterChef.sol";
import "../../base/interface/uniswap/IUniswapV2Pair.sol";

contract YelStrategy is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant sushiswapRouterV2 = address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);
  address public constant multiSigAddr = address(0xF49440C1F012d041802b25A73e5B0B9166a75c02);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _POOLID_SLOT = 0x3fd729bfa2e28b7806b03a6e014729f59477b530f995be4d51defc9dad94810b;

  constructor() BaseUpgradeableStrategy() {
    assert(_POOLID_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.poolId")) - 1));
  }

  function initializeStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _rewardPool,
    address _rewardToken,
    uint256 _poolID
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _rewardPool,
      _rewardToken,
      multiSigAddr
    );

    address _lpt;
    (_lpt,,,) = IMasterChef(_rewardPool).poolInfo(_poolID);
    require(_lpt == _underlying, "Pool Info does not match underlying");
    _setPoolId(_poolID);
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function rewardPoolBalance() internal view returns (uint256 bal) {
    (bal,) = IMasterChef(rewardPool()).userInfo(poolId(), address(this));
  }

  function exitRewardPool() internal {
    uint256 bal = rewardPoolBalance();
    if (bal != 0) {
      IMasterChef(rewardPool()).withdraw(poolId(), bal);
    }
  }

  function emergencyExitRewardPool() internal {
    uint256 bal = rewardPoolBalance();
    if (bal != 0) {
      IMasterChef(rewardPool()).emergencyWithdraw(poolId());
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
    IMasterChef(_rewardPool).deposit(poolId(), entireBalance);
  }

  /*
  *   In case there are some issues discovered about the pool or underlying asset
  *   Governance can exit the pool properly
  *   The function is only used for emergency to exit the pool
  */
  function emergencyExit() public onlyGovernance {
    emergencyExitRewardPool();
    _setPausedInvesting(true);
  }

  /*
  *   Resumes the ability to invest into the underlying reward pools
  */

  function continueInvesting() public onlyGovernance {
    _setPausedInvesting(false);
  }

  // We assume that all the tradings can be done on Uniswap
  function _liquidateReward() internal {
    address _rewardToken = rewardToken();
    uint256 rewardBalanceBefore = IERC20(_rewardToken).balanceOf(address(this));
    IMasterChef(rewardPool()).withdraw(poolId(), 0);
    uint256 rewardBalanceAfter = IERC20(_rewardToken).balanceOf(address(this));
    uint256 claimed = rewardBalanceAfter.sub(rewardBalanceBefore);
    _notifyProfitInRewardToken(_rewardToken, claimed);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance == 0) {
      return;
    }

    address _underlying = underlying();
    address uniLPComponentToken0 = IUniswapV2Pair(_underlying).token0();
    address uniLPComponentToken1 = IUniswapV2Pair(_underlying).token1();

    uint256 toToken0 = remainingRewardBalance.div(2);
    uint256 toToken1 = remainingRewardBalance.sub(toToken0);

    uint256 token0Amount;
    uint256 token1Amount;
    address _universalLiquidator = universalLiquidator();

    if (_rewardToken != uniLPComponentToken0) {
      IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
      IERC20(_rewardToken).safeApprove(_universalLiquidator, toToken0);
      IUniversalLiquidator(_universalLiquidator).swap(_rewardToken, uniLPComponentToken0, toToken0, 1, address(this));
      token0Amount = IERC20(uniLPComponentToken0).balanceOf(address(this));
    } else {
      // otherwise we assme token0 is the reward token itself
      token0Amount = toToken0;
    }

    if (_rewardToken != uniLPComponentToken1) {
      IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
      IERC20(_rewardToken).safeApprove(_universalLiquidator, toToken1);
      IUniversalLiquidator(_universalLiquidator).swap(_rewardToken, uniLPComponentToken1, toToken1, 1, address(this));
      token1Amount = IERC20(uniLPComponentToken1).balanceOf(address(this));
    } else {
      // otherwise we assme token0 is the reward token itself
      token1Amount = toToken1;
    }

    // provide token1 and token2 to SUSHI
    IERC20(uniLPComponentToken0).safeApprove(sushiswapRouterV2, 0);
    IERC20(uniLPComponentToken0).safeApprove(sushiswapRouterV2, token0Amount);

    IERC20(uniLPComponentToken1).safeApprove(sushiswapRouterV2, 0);
    IERC20(uniLPComponentToken1).safeApprove(sushiswapRouterV2, token1Amount);

    // we provide liquidity to sushi
    uint256 liquidity;
    (,,liquidity) = IUniswapV2Router02(sushiswapRouterV2).addLiquidity(
      uniLPComponentToken0,
      uniLPComponentToken1,
      token0Amount,
      token1Amount,
      1,  // we are willing to take whatever the pair gives us
      1,  // we are willing to take whatever the pair gives us
      address(this),
      block.timestamp
    );
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
    if (address(rewardPool()) != address(0)) {
      exitRewardPool();
    }
    address _underlying = underlying();
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
      IMasterChef(rewardPool()).withdraw(poolId(), toWithdraw);
    }

    IERC20(_underlying).safeTransfer(vault(), amount);
  }

  /*
  *   Note that we currently do not have a mechanism here to include the
  *   amount of reward that is accrued.
  */
  function investedUnderlyingBalance() external view returns (uint256) {
    if (rewardPool() == address(0)) {
      return IERC20(underlying()).balanceOf(address(this));
    }
    // Adding the amount locked in the reward pool and the amount that is somehow in this contract
    // both are in the units of "underlying"
    // The second part is needed because there is the emergency exit mechanism
    // which would break the assumption that all the funds are always inside of the reward pool
    return rewardPoolBalance().add(IERC20(underlying()).balanceOf(address(this)));
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
    _liquidateReward();
    investAllUnderlying();
  }

  // masterchef rewards pool ID
  function _setPoolId(uint256 _value) internal {
    setUint256(_POOLID_SLOT, _value);
  }

  function poolId() public view returns (uint256) {
    return getUint256(_POOLID_SLOT);
  }
}
