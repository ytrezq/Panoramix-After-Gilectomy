// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../base/interface/IVault.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/idle/IdleToken.sol";
import "../../base/interface/idle/IdleTokenHelper.sol";

contract IdleStrategy is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant harvestMSIG = address(0xF49440C1F012d041802b25A73e5B0B9166a75c02);
  address public constant idleTokenHelper = address(0x04Ce60ed10F6D2CfF3AA015fc7b950D13c113be5);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _IDLE_TOKEN_SLOT = 0x13380ba87b49f66bcef8ae788a4167d4f221bf313d7f2247b34cebbade0afeb4;
  bytes32 internal constant _REFERRAL_SLOT = 0x4b6f06a0614ccba013015008af8706cf84e48aa9040cbac7086d10fcb2a4aac3;
  bytes32 internal constant _PROTECTED_SLOT = 0x4d197d446454146eb1952b8116177694336047ced9d933f8a7d486455812af04;
  bytes32 internal constant _STORED_SUPPLIED_SLOT = 0x280539da846b4989609abdccfea039bd1453e4f710c670b29b9eeaca0730c1a2;
  bytes32 internal constant _VIRTUAL_PRICE_SLOT = 0x80497baf3a838caae518facdae57b718fde1de8378282fb04a2e3493e04f052f;

  modifier updateVirtualPrice() {
    if (protected()) {
      require(virtualPrice() <= IdleTokenHelper(idleTokenHelper).getRedeemPrice(idleToken()), "virtual price is higher than needed");
    }
    _;
    _setVirtualPrice(IdleTokenHelper(idleTokenHelper).getRedeemPrice(idleToken()));
  }

  constructor() BaseUpgradeableStrategy() {
    assert(_IDLE_TOKEN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.idleToken")) - 1));
    assert(_REFERRAL_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.referral")) - 1));
    assert(_PROTECTED_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.protected")) - 1));
    assert(_STORED_SUPPLIED_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.storedSupplied")) - 1));
    assert(_VIRTUAL_PRICE_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.virtualPrice")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _idleToken,
    address _rewardToken,
    address _referral,
    bool _protected
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _idleToken,
      _rewardToken,
      harvestMSIG
    );

    address _lpt = IdleToken(_idleToken).token();
    require(_lpt == _underlying, "Underlying mismatch");

    _setIdleToken(_idleToken);
    setAddress(_REFERRAL_SLOT, _referral);
    setBoolean(_PROTECTED_SLOT, _protected);
    _setVirtualPrice(IdleTokenHelper(idleTokenHelper).getRedeemPrice(_idleToken));
  }

  function currentSupplied() public view returns (uint256) {
    address _idleToken = idleToken();
    uint256 balance = IERC20(_idleToken).balanceOf(address(this));
    uint256 redeemPrice = IdleTokenHelper(idleTokenHelper).getRedeemPrice(_idleToken);
    return balance.mul(redeemPrice).div(1e18);
  }

  function storedSupplied() public view returns (uint256) {
    return getUint256(_STORED_SUPPLIED_SLOT);
  }

  function _updateStoredSupplied(bool feeClaimed) internal {
    uint256 balance;
    if (feeClaimed) {
      balance = currentSupplied();
    } else {
      balance = currentSupplied().sub(pendingFee().mul(feeDenominator()).div(totalFeeNumerator()));
    }
    setUint256(_STORED_SUPPLIED_SLOT, balance);
  }

  function totalFeeNumerator() public view returns (uint256) {
    return strategistFeeNumerator().add(platformFeeNumerator()).add(profitSharingNumerator());
  }

  function pendingFee() public view returns (uint256) {
    uint256 fee;
    if (currentSupplied() > storedSupplied()) {
        uint256 balanceIncrease = currentSupplied().sub(storedSupplied());
        fee = balanceIncrease.mul(totalFeeNumerator()).div(feeDenominator());
    }
    return fee;
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function _withdrawUnderlyingFromPool(uint256 amount) internal {
    address _idleToken = idleToken();
    uint256 redeemPrice = IdleTokenHelper(idleTokenHelper).getRedeemPrice(_idleToken);
    uint256 toRedeem = amount.mul(1e18).div(redeemPrice).add(1);
    IdleToken(_idleToken).redeemIdleToken(toRedeem);
  }

  function _withdrawAllUnderlying() internal {
    address _idleToken = idleToken();
    IdleToken(_idleToken).redeemIdleToken(IERC20(_idleToken).balanceOf(address(this)));
  }

  function _enterRewardPool() internal {
    address _underlying = underlying();
    address _idleToken = idleToken();
    uint256 entireBalance = IERC20(_underlying).balanceOf(address(this));
    IERC20(_underlying).safeApprove(_idleToken, 0);
    IERC20(_underlying).safeApprove(_idleToken, entireBalance);
    IdleToken(_idleToken).mintIdleToken(entireBalance, true, referral());
  }

  function _investAllUnderlying() internal onlyNotPausedInvesting {
    // this check is needed, because most of the SNX reward pools will revert if
    // you try to stake(0).
    if(IERC20(underlying()).balanceOf(address(this)) > 0) {
      _enterRewardPool();
    }
    _updateStoredSupplied(true);
  }

  /*
  *   In case there are some issues discovered about the pool or underlying asset
  *   Governance can exit the pool properly
  *   The function is only used for emergency to exit the pool
  */
  function emergencyExit() public onlyGovernance updateVirtualPrice {
    _withdrawAllUnderlying();
    _setPausedInvesting(true);
  }

  /*
  *   Resumes the ability to invest into the underlying reward pools
  */
  function continueInvesting() public onlyGovernance {
    _setPausedInvesting(false);
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying() || token == idleToken());
  }

  function _claimReward() internal {
    IdleToken(idleToken()).redeemIdleToken(0);
  }

  function _liquidateReward() internal {
    if (!sell()) {
      // Profits can be disabled for possible simplified and rapid exit
      emit ProfitsNotCollected(sell(), false);
      return;
    }
    address _rewardToken = rewardToken();
    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    uint256 _pendingFee = pendingFee();
    uint256 convertedFee;
    if (_pendingFee > 0) {
      address _underlying = underlying();
      uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
      address _universalLiquidator = universalLiquidator();
      if (underlyingBalance < _pendingFee) {
        _withdrawUnderlyingFromPool(_pendingFee.sub(underlyingBalance));
      }
      IERC20(_underlying).safeApprove(_universalLiquidator, 0);
      IERC20(_underlying).safeApprove(_universalLiquidator, _pendingFee);
      IUniversalLiquidator(_universalLiquidator).swap(_underlying, _rewardToken, _pendingFee, 1, address(this));
      uint256 rewardAfter = IERC20(_rewardToken).balanceOf(address(this));
      convertedFee = rewardAfter.sub(rewardBalance);
    }

    _notifyProfitInRewardToken(_rewardToken, rewardBalance.add(convertedFee.mul(feeDenominator()).div(totalFeeNumerator())));
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance < 1e15) {
      return;
    }

    address _underlying = underlying();
    if (_underlying != _rewardToken) {
      address _universalLiquidator = universalLiquidator();
      IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
      IERC20(_rewardToken).safeApprove(_universalLiquidator, remainingRewardBalance);
      IUniversalLiquidator(_universalLiquidator).swap(_rewardToken, _underlying, remainingRewardBalance, 1, address(this));
    }
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawAllToVault() public restricted updateVirtualPrice {
    _claimReward();
    _liquidateReward();
    _withdrawAllUnderlying();
    address underlying_ = underlying();
    IERC20(underlying_).safeTransfer(vault(), IERC20(underlying_).balanceOf(address(this)));
    _updateStoredSupplied(true);
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawToVault(uint256 _amount) public restricted updateVirtualPrice {
    // Typically there wouldn't be any amount here
    // however, it is possible because of the emergencyExit
    address underlying_ = underlying();
    uint256 entireBalance = IERC20(underlying_).balanceOf(address(this));

    if(_amount > entireBalance){
      // While we have the check above, we still using SafeMath below
      // for the peace of mind (in case something gets changed in between)
      uint256 needToWithdraw = _amount.sub(entireBalance);
      uint256 toWithdraw = Math.min(currentSupplied(), needToWithdraw);
      _withdrawUnderlyingFromPool(toWithdraw);
    }
    IERC20(underlying_).safeTransfer(vault(), _amount);
    _updateStoredSupplied(false);
  }

  /*
  *   Note that we currently do not have a mechanism here to include the
  *   amount of reward that is accrued.
  */
  function investedUnderlyingBalance() external view returns (uint256) {
    if (rewardPool() == address(0)) {
      return IERC20(underlying()).balanceOf(address(this));
    }
    if (protected()) {
      require(virtualPrice() <= IdleTokenHelper(idleTokenHelper).getRedeemPrice(idleToken()), "virtual price is higher than needed");
    }
    // Adding the amount locked in the reward pool and the amount that is somehow in this contract
    // both are in the units of "underlying"
    // The second part is needed because there is the emergency exit mechanism
    // which would break the assumption that all the funds are always inside of the reward pool
    return IERC20(underlying()).balanceOf(address(this))
    .add(currentSupplied())
    .sub(pendingFee());
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
  function doHardWork() external onlyNotPausedInvesting restricted updateVirtualPrice {
    _claimReward();
    _liquidateReward();
    _investAllUnderlying();
  }

  function _setIdleToken(address _address) internal {
    setAddress(_IDLE_TOKEN_SLOT, _address);
  }

  function idleToken() public view returns (address) {
    return getAddress(_IDLE_TOKEN_SLOT);
  }

  function setReferral(address _address) public onlyGovernance {
    setAddress(_REFERRAL_SLOT, _address);
  }

  function referral() public view returns (address) {
    return getAddress(_REFERRAL_SLOT);
  }

  function setProtected(bool _value) public onlyGovernance {
    setBoolean(_PROTECTED_SLOT, _value);
  }

  function protected() public view returns (bool) {
    return getBoolean(_PROTECTED_SLOT);
  }

  function _setVirtualPrice(uint256 _value) internal {
    setUint256(_VIRTUAL_PRICE_SLOT, _value);
  }

  function virtualPrice() public view returns (uint256) {
    return getUint256(_VIRTUAL_PRICE_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
    _updateStoredSupplied(true);
  }
}
