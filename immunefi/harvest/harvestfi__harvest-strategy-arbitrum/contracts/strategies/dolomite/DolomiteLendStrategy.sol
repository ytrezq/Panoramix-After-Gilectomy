// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/dolomite/IDolomiteMargin.sol";
import "../../base/interface/dolomite/IDepositWithdraw.sol";
import "../../base/interface/dolomite/IRewardsDistributor.sol";

contract DolomiteLendStrategy is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _MARKET_ID_SLOT = 0x54fed29e040f8360ca8b822de4be5728a7f0714b74e8d5dd23a1d1ac0c75c6a7;
  bytes32 internal constant _DOLOMITE_MARGIN_SLOT = 0xeb52083a303441dc22b6905f2ddc3b6ee13a44944ed7f2ebb0bcb3baf59e4e61;
  bytes32 internal constant _DEPOSIT_WITHDRAW_SLOT = 0x096b7d9b1b276278667b14db2373be3a19524b5b48b8b667178d1ae019f52912;
  bytes32 internal constant _STORED_SUPPLIED_SLOT = 0x280539da846b4989609abdccfea039bd1453e4f710c670b29b9eeaca0730c1a2;
  bytes32 internal constant _PENDING_FEE_SLOT = 0x0af7af9f5ccfa82c3497f40c7c382677637aee27293a6243a22216b51481bd97;

  // this would be reset on each upgrade
  address[] public rewardTokens;

  constructor() BaseUpgradeableStrategy() {
    assert(_MARKET_ID_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.marketId")) - 1));
    assert(_DOLOMITE_MARGIN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.dolomiteMargin")) - 1));
    assert(_DEPOSIT_WITHDRAW_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.depositWithdraw")) - 1));
    assert(_STORED_SUPPLIED_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.storedSupplied")) - 1));
    assert(_PENDING_FEE_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.pendingFee")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _dolomiteMargin,
    address _depositWithdraw,
    uint256 _marketId,
    address _rewardToken
  )
  public initializer {
    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _dolomiteMargin,
      _rewardToken,
      harvestMSIG
    );

    require(IDolomiteMargin(_dolomiteMargin).getMarketIdByTokenAddress(_underlying) == _marketId, "Underlying mismatch");
    _setDolomiteMargin(_dolomiteMargin);
    _setDepositWithdraw(_depositWithdraw);
    _setMarketId(_marketId);
  }

  function currentBalance() public view returns (uint256) {
    IDolomiteMargin.Info memory account;
    account.owner = address(this);
    IDolomiteMargin.Wei memory balanceInfo = IDolomiteMargin(dolomiteMargin()).getAccountWei(account, marketId());
    uint256 underlyingBalance = balanceInfo.value;
    return underlyingBalance;
  }

  function storedBalance() public view returns (uint256) {
    return getUint256(_STORED_SUPPLIED_SLOT);
  }

  function _updateStoredBalance() internal {
    uint256 balance = currentBalance();
    setUint256(_STORED_SUPPLIED_SLOT, balance);
  }

  function totalFeeNumerator() public view returns (uint256) {
    return strategistFeeNumerator().add(platformFeeNumerator()).add(profitSharingNumerator());
  }

  function pendingFee() public view returns (uint256) {
    return getUint256(_PENDING_FEE_SLOT);
  }

  function _accrueFee() internal {
    uint256 fee;
    if (currentBalance() > storedBalance()) {
      uint256 balanceIncrease = currentBalance().sub(storedBalance());
      fee = balanceIncrease.mul(totalFeeNumerator()).div(feeDenominator());
    }
    setUint256(_PENDING_FEE_SLOT, pendingFee().add(fee));
    _updateStoredBalance();
  }

  function _handleFee() internal {
    _accrueFee();
    uint256 fee = pendingFee();
    if (fee > 0) {
      uint256 balanceIncrease = fee.mul(feeDenominator()).div(totalFeeNumerator());
      _redeem(fee);
      address _underlying = underlying();
      if (IERC20(_underlying).balanceOf(address(this)) < fee) {
        balanceIncrease = IERC20(_underlying).balanceOf(address(this)).mul(feeDenominator()).div(totalFeeNumerator());
      }
      _notifyProfitInRewardToken(_underlying, balanceIncrease);
      setUint256(_PENDING_FEE_SLOT, 0);
    }
  }

  function depositArbCheck() public pure returns (bool) {
    // there's no arb here.
    return true;
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying());
  }

  /**
  * The strategy invests by supplying the underlying as a collateral.
  */
  function _investAllUnderlying() internal onlyNotPausedInvesting {
    address _underlying = underlying();
    uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
    if (underlyingBalance > 0) {
      _supply(underlyingBalance);
    }
  }

  function withdrawAllToVault() public restricted {
    _liquidateRewards();
    address _underlying = underlying();
    _redeemAll();
    if (IERC20(_underlying).balanceOf(address(this)) > 0) {
      IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
    }
    _updateStoredBalance();
  }

  function emergencyExit() external onlyGovernance {
    _accrueFee();
    _redeemAll();
    _setPausedInvesting(true);
    _updateStoredBalance();
  }

  function continueInvesting() public onlyGovernance {
    _setPausedInvesting(false);
  }

  function withdrawToVault(uint256 amountUnderlying) public restricted {
    _accrueFee();
    address _underlying = underlying();
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    if (amountUnderlying <= balance) {
      IERC20(_underlying).safeTransfer(vault(), amountUnderlying);
      return;
    }
    uint256 toRedeem = amountUnderlying.sub(balance);
    // get some of the underlying
    _redeem(toRedeem);
    balance = IERC20(_underlying).balanceOf(address(this));
    // transfer the amount requested (or the amount we have) back to vault()
    IERC20(_underlying).safeTransfer(vault(), Math.min(amountUnderlying, balance));
    balance = IERC20(_underlying).balanceOf(address(this));
    if (balance > 1e1) {
      _investAllUnderlying();
    }
    _updateStoredBalance();
  }

  /**
  * Withdraws all assets, liquidates XVS, and invests again in the required ratio.
  */
  function doHardWork() public restricted {
    _liquidateRewards();
    _investAllUnderlying();
    _updateStoredBalance();
  }

  /**
  * Salvages a token.
  */
  function salvage(address recipient, address token, uint256 amount) public onlyGovernance {
    // To make sure that governance cannot come in and take away the coins
    require(!unsalvagableTokens(token), "token is defined as not salvagable");
    IERC20(token).safeTransfer(recipient, amount);
  }

  function addRewardToken(address _token) public onlyGovernance {
    rewardTokens.push(_token);
  }

  function _liquidateRewards() internal {
    if (!sell()) {
      // Profits can be disabled for possible simplified and rapid exit
      emit ProfitsNotCollected(sell(), false);
      return;
    }
    _handleFee();
  }

  /**
  * Returns the current balance.
  */
  function investedUnderlyingBalance() public view returns (uint256) {
    return IERC20(underlying()).balanceOf(address(this))
    .add(storedBalance())
    .sub(pendingFee());
  }

  function _supply(uint256 amount) internal {
    address _underlying = underlying();
    address _dolomiteMargin = dolomiteMargin();
    IERC20(_underlying).safeApprove(_dolomiteMargin, 0);
    IERC20(_underlying).safeApprove(_dolomiteMargin, amount);
    IDepositWithdraw(depositWithdraw()).depositWeiIntoDefaultAccount(marketId(), amount);
  }

  function _redeem(uint256 amountUnderlying) internal {
    IDepositWithdraw(depositWithdraw()).withdrawWeiFromDefaultAccount(
      marketId(),
      amountUnderlying,
      IDepositWithdraw.BalanceCheckFlag.From
    );
  }

  function _redeemAll() internal {
    IDepositWithdraw(depositWithdraw()).withdrawWeiFromDefaultAccount(
      marketId(),
      currentBalance(),
      IDepositWithdraw.BalanceCheckFlag.From
    );
  }

  function _setDolomiteMargin (address _target) internal {
    setAddress(_DOLOMITE_MARGIN_SLOT, _target);
  }

  function dolomiteMargin() public view returns (address) {
    return getAddress(_DOLOMITE_MARGIN_SLOT);
  }

  function _setDepositWithdraw (address _target) internal {
    setAddress(_DEPOSIT_WITHDRAW_SLOT, _target);
  }

  function depositWithdraw() public view returns (address) {
    return getAddress(_DEPOSIT_WITHDRAW_SLOT);
  }

  function _setMarketId (uint256 _target) internal {
    setUint256(_MARKET_ID_SLOT, _target);
  }

  function marketId() public view returns (uint256) {
    return getUint256(_MARKET_ID_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }

  function claimRewards(IRewardsDistributor.ClaimInfo[] calldata _claimInfo) external {
    IRewardsDistributor(0x2E3D10CC42227aF0ce908F00C76fFe1dE1728b4B).claim(_claimInfo);
  }

  receive() external payable {}
}