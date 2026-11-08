// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/interface/IVault.sol";
import "../../base/upgradability/BaseUpgradeableStrategyV2.sol";
import "../../base/interface/aave/IAToken.sol";
import "../../base/interface/aave/IPool.sol";

contract AaveSupplyStrategy is BaseUpgradeableStrategyV2 {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant harvestMSIG = address(0x39cC360806b385C96969ce9ff26c23476017F652);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _ATOKEN_SLOT = 0x8cdee58637b787efaa2d78bb1da1e053a2c91e61640b32339bfbba65c00abd68;
  bytes32 internal constant _STORED_SUPPLIED_SLOT = 0x280539da846b4989609abdccfea039bd1453e4f710c670b29b9eeaca0730c1a2;
  bytes32 internal constant _PENDING_FEE_SLOT = 0x0af7af9f5ccfa82c3497f40c7c382677637aee27293a6243a22216b51481bd97;

  constructor() public BaseUpgradeableStrategyV2() {
    assert(_ATOKEN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.aToken")) - 1));
    assert(_STORED_SUPPLIED_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.storedSupplied")) - 1));
    assert(_PENDING_FEE_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.pendingFee")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _aToken
  )
  public initializer {
    BaseUpgradeableStrategyV2.initialize(
      _storage,
      _underlying,
      _vault,
      _aToken,
      _underlying,
      harvestMSIG
    );

    require(IAToken(_aToken).UNDERLYING_ASSET_ADDRESS() == _underlying, "Underlying mismatch");
    _setAToken(_aToken);
  }

  function currentSupplied() public view returns (uint256) {
    return IAToken(aToken()).balanceOf(address(this));
  }

  function storedSupplied() public view returns (uint256) {
    return getUint256(_STORED_SUPPLIED_SLOT);
  }

  function _updateStoredSupplied() internal {
    setUint256(_STORED_SUPPLIED_SLOT, currentSupplied());
  }

  function totalFeeNumerator() public view returns (uint256) {
    return strategistFeeNumerator().add(platformFeeNumerator()).add(profitSharingNumerator());
  }

  function pendingFee() public view returns (uint256) {
    return getUint256(_PENDING_FEE_SLOT);
  }

  function _accrueFee() internal {
    uint256 fee;
    if (currentSupplied() > storedSupplied()) {
      uint256 balanceIncrease = currentSupplied().sub(storedSupplied());
      fee = balanceIncrease.mul(totalFeeNumerator()).div(feeDenominator());
    }
    setUint256(_PENDING_FEE_SLOT, pendingFee().add(fee));
    _updateStoredSupplied();
  }

  function _handleFee() internal {
    _accrueFee();
    uint256 fee = pendingFee();
    if (fee > 100) {
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
    return (token == underlying() || token == aToken());
  }

  /**
  * Exits Moonwell and transfers everything to the vault.
  */
  function withdrawAllToVault() public restricted {
    address _underlying = underlying();
    _handleFee();
    _redeemMaximum();
    if (IERC20(_underlying).balanceOf(address(this)) > 0) {
      IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
    }
    _updateStoredSupplied();
  }

  function emergencyExit() external onlyGovernance {
    _accrueFee();
    _redeemMaximum();
    _updateStoredSupplied();
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
    // transfer the amount requested (or the amount we have) back to vault()
    IERC20(_underlying).safeTransfer(vault(), amountUnderlying);
    balance = IERC20(_underlying).balanceOf(address(this));
    if (balance > 0) {
      _supply(balance);
    }
    _updateStoredSupplied();
  }

  /**
  * Withdraws all assets, liquidates XVS, and invests again in the required ratio.
  */
  function doHardWork() public restricted {
    _handleFee();
    _supply(IERC20(underlying()).balanceOf(address(this)));
    _updateStoredSupplied();
  }

  /**
  * Salvages a token.
  */
  function salvage(address recipient, address token, uint256 amount) public onlyGovernance {
    // To make sure that governance cannot come in and take away the coins
    require(!unsalvagableTokens(token), "token is defined as not salvagable");
    IERC20(token).safeTransfer(recipient, amount);
  }

  /**
  * Returns the current balance.
  */
  function investedUnderlyingBalance() public view returns (uint256) {
    // underlying in this strategy + underlying redeemable from Radiant - debt
    return IERC20(underlying()).balanceOf(address(this))
    .add(storedSupplied())
    .sub(pendingFee());
  }

  /**
  * Supplies to Moonwel
  */
  function _supply(uint256 amount) internal {
    if (amount == 0){
      return;
    }
    address _underlying = underlying();
    address _pool = IAToken(aToken()).POOL();
    IERC20(_underlying).safeApprove(_pool, 0);
    IERC20(_underlying).safeApprove(_pool, amount);
    IPool(_pool).supply(_underlying, amount, address(this), 0);
  }

  function _redeem(uint256 amountUnderlying) internal {
    if (amountUnderlying == 0){
      return;
    }
    address _pool = IAToken(aToken()).POOL();
    IPool(_pool).withdraw(underlying(), amountUnderlying, address(this));
  }

  function _redeemMaximum() internal {
    if (currentSupplied() > 0) {
      _redeem(currentSupplied().sub(pendingFee().add(1)));
    }
  }

  function _setAToken (address _target) internal {
    setAddress(_ATOKEN_SLOT, _target);
  }

  function aToken() public view returns (address) {
    return getAddress(_ATOKEN_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }

  receive() external payable {}
}