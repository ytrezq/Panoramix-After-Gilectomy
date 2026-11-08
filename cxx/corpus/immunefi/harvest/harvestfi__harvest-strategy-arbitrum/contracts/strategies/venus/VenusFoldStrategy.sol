// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/compound/CTokenInterface.sol";
import "../../base/interface/compound/IComptroller.sol";
import "../../base/interface/venus/IRewardsDistributor.sol";
import "../../base/interface/merkl/IDistributor.sol";
import "../../base/interface/balancer/IBVault.sol";

contract VenusFoldStrategy is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);
  address public constant bVault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _CTOKEN_SLOT = 0x316ad921d519813e6e41c0e056b79e4395192c2b101f8b61cf5b94999360d568;
  bytes32 internal constant _COMPTROLLER_SLOT = 0x21864471ca9d8b67bc7f58951fb160897ce623fdb405c56534d08a363a47e235;
  bytes32 internal constant _STORED_SUPPLIED_SLOT = 0x280539da846b4989609abdccfea039bd1453e4f710c670b29b9eeaca0730c1a2;
  bytes32 internal constant _PENDING_FEE_SLOT = 0x0af7af9f5ccfa82c3497f40c7c382677637aee27293a6243a22216b51481bd97;
  bytes32 internal constant _COLLATERALFACTORNUMERATOR_SLOT = 0x129eccdfbcf3761d8e2f66393221fa8277b7623ad13ed7693a0025435931c64a;
  bytes32 internal constant _FACTORDENOMINATOR_SLOT = 0x4e92df66cc717205e8df80bec55fc1429f703d590a2d456b97b74f0008b4a3ee;
  bytes32 internal constant _BORROWTARGETFACTORNUMERATOR_SLOT = 0xa65533f4b41f3786d877c8fdd4ae6d27ada84e1d9c62ea3aca309e9aa03af1cd;
  bytes32 internal constant _FOLD_SLOT = 0x1841be4c16015a744c9fbf595f7c6b32d40278c16c1fc7cf2de88c6348de44ba;

  bool internal makingFlashDeposit;
  bool internal makingFlashWithdrawal;

  // this would be reset on each upgrade
  address[] public rewardTokens;

  constructor() BaseUpgradeableStrategy() {
    assert(_CTOKEN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.cToken")) - 1));
    assert(_COMPTROLLER_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.comptroller")) - 1));
    assert(_STORED_SUPPLIED_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.storedSupplied")) - 1));
    assert(_PENDING_FEE_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.pendingFee")) - 1));
    assert(_COLLATERALFACTORNUMERATOR_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.collateralFactorNumerator")) - 1));
    assert(_FACTORDENOMINATOR_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.factorDenominator")) - 1));
    assert(_BORROWTARGETFACTORNUMERATOR_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.borrowTargetFactorNumerator")) - 1));
    assert(_FOLD_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.fold")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _cToken,
    address _comptroller,
    address _rewardToken,
    uint256 _borrowTargetFactorNumerator,
    uint256 _collateralFactorNumerator,
    uint256 _factorDenominator,
    bool _fold
  )
  public initializer {
    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _comptroller,
      _rewardToken,
      harvestMSIG
    );

    require(CTokenInterface(_cToken).underlying() == _underlying, "Underlying mismatch");

    _setCToken(_cToken);
    _setComptroller(_comptroller);

    require(_collateralFactorNumerator < _factorDenominator, "Numerator should be smaller than denominator");
    require(_borrowTargetFactorNumerator < _collateralFactorNumerator, "Target should be lower than limit");
    _setFactorDenominator(_factorDenominator);
    setUint256(_COLLATERALFACTORNUMERATOR_SLOT, _collateralFactorNumerator);
    setUint256(_BORROWTARGETFACTORNUMERATOR_SLOT, _borrowTargetFactorNumerator);
    setBoolean(_FOLD_SLOT, _fold);

    address[] memory markets = new address[](1);
    markets[0] = _cToken;
    IComptroller(_comptroller).enterMarkets(markets);
  }

  function currentBalance() public returns (uint256) {
    address _cToken = cToken();
    // amount we supplied
    uint256 suppliedInUnderlying = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    // amount we borrowed
    uint256 borrowedInUnderlying = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
    return suppliedInUnderlying.sub(borrowedInUnderlying);
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
    if (fee > 100) {
      _redeem(fee);
      address _underlying = underlying();
      fee = Math.min(fee, IERC20(_underlying).balanceOf(address(this)));
      uint256 balanceIncrease = fee.mul(feeDenominator()).div(totalFeeNumerator());
      _notifyProfitInRewardToken(_underlying, balanceIncrease);
      setUint256(_PENDING_FEE_SLOT, pendingFee().sub(fee));
    }
  }
  
  function depositArbCheck() public pure returns (bool) {
    // there's no arb here.
    return true;
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying() || token == cToken());
  }

  function _investAllUnderlying() internal onlyNotPausedInvesting {
    address _underlying = underlying();
    uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
    if (underlyingBalance > 0) {
      _supply(underlyingBalance);
    }
    if (fold()) {
      _depositWithFlashloan();
    }
  }

  function withdrawAllToVault() public restricted {
    address _underlying = underlying();
    _withdrawMaximum(true);
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    if (balance > 0) {
      IERC20(_underlying).safeTransfer(vault(), balance);
    }
    _updateStoredBalance();
  }

  function emergencyExit() external onlyGovernance {
    _withdrawMaximum(false);
    _setPausedInvesting(true);
    _updateStoredBalance();
  }

  function _withdrawMaximum(bool claim) internal {
    if (claim) {
      _handleFee();
      _claimReward();
      _liquidateReward();
    } else {
      _accrueFee();
    }
    _redeemMaximum();
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
    _redeemPartial(toRedeem);
    // transfer the amount requested (or the amount we have) back to vault()
    IERC20(_underlying).safeTransfer(vault(), amountUnderlying);
    balance = IERC20(_underlying).balanceOf(address(this));
    if (balance > 0) {
      _investAllUnderlying();
    }
    _updateStoredBalance();
  }

  function _redeemPartial(uint256 amountUnderlying) internal {
    address _underlying = underlying();
    uint256 balanceBefore = IERC20(_underlying).balanceOf(address(this));
    _redeemWithFlashloan(
      amountUnderlying,
      fold()? borrowTargetFactorNumerator():0
    );
    uint256 balanceAfter = IERC20(_underlying).balanceOf(address(this));
    require(balanceAfter.sub(balanceBefore) >= amountUnderlying, "Unable to withdraw the entire amountUnderlying");
  }

  function doHardWork() public restricted {
    _handleFee();
    _claimReward();
    _liquidateReward();
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

  function _claimReward() internal {
    address[] memory rewardDistributors = IComptroller(comptroller()).getRewardDistributors();
    for (uint256 i = 0; i < rewardDistributors.length; i++) {
      address rewardDistributor = rewardDistributors[i];
      IRewardsDistributor(rewardDistributor).claimRewardToken(address(this));
    }
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
    address _underlying = underlying();
    for(uint256 i = 0; i < rewardTokens.length; i++){
      address token = rewardTokens[i];
      uint256 balance = IERC20(token).balanceOf(address(this));

      if (balance > 0 && token != _rewardToken){
        IERC20(token).safeApprove(_universalLiquidator, 0);
        IERC20(token).safeApprove(_universalLiquidator, balance);
        IUniversalLiquidator(_universalLiquidator).swap(token, _rewardToken, balance, 1, address(this));
      }
    }

    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    if (rewardBalance < 1e14) {
      return;
    }
    _notifyProfitInRewardToken(_rewardToken, rewardBalance);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance == 0) {
      return;
    }

    if (_underlying != _rewardToken) {
      IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
      IERC20(_rewardToken).safeApprove(_universalLiquidator, remainingRewardBalance);
      IUniversalLiquidator(_universalLiquidator).swap(_rewardToken, _underlying, remainingRewardBalance, 1, address(this));
    }
  }

  /**
  * Returns the current balance.
  */
  function investedUnderlyingBalance() public view returns (uint256) {
    uint256 balance = IERC20(underlying()).balanceOf(address(this));
    return balance.add(storedBalance()).sub(pendingFee());
  }

  function _supply(uint256 amountUnderlying) internal {
    if (amountUnderlying == 0){
      return;
    }
    address _underlying = underlying();
    address _cToken = cToken();
    uint256 supplyCap = IComptroller(comptroller()).supplyCaps(_cToken);
    if (supplyCap == 0) {
      supplyCap = type(uint256).max;
    }
    uint256 totalSupply = IERC20(_cToken).totalSupply().mul(CTokenInterface(_cToken).exchangeRateCurrent()).div(1e18);
    if (totalSupply >= supplyCap) {
      return;
    } else if (supplyCap.sub(totalSupply) <= amountUnderlying) {
      amountUnderlying = supplyCap.sub(totalSupply).sub(2);
    }
    IERC20(_underlying).safeApprove(_cToken, 0);
    IERC20(_underlying).safeApprove(_cToken, amountUnderlying);
    CTokenInterface(_cToken).mint(amountUnderlying);
  }

  function _borrow(uint256 amountUnderlying) internal {
    if (amountUnderlying == 0){
      return;
    }
    CTokenInterface(cToken()).borrow(amountUnderlying);
  }

  function _redeem(uint256 amountUnderlying) internal {
    if (amountUnderlying == 0){
      return;
    }
    address _cToken = cToken();
    uint256 exchange = CTokenInterface(_cToken).exchangeRateCurrent();
    if (amountUnderlying.mul(1e18) < exchange){
      CTokenInterface(_cToken).redeem(1);
      return;
    }
    CTokenInterface(_cToken).redeemUnderlying(amountUnderlying);
  }

  function _repay(uint256 amountUnderlying) internal {
    if (amountUnderlying == 0){
      return;
    }
    address _underlying = underlying();
    address _cToken = cToken();
    IERC20(_underlying).safeApprove(_cToken, 0);
    IERC20(_underlying).safeApprove(_cToken, amountUnderlying);
    CTokenInterface(_cToken).repayBorrow(amountUnderlying);
  }

  function _redeemMaximum() internal {
    address _cToken = cToken();
    uint256 available = CTokenInterface(_cToken).getCash();
    // amount we supplied
    uint256 supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    // amount we borrowed
    uint256 borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
    uint256 balance = supplied.sub(borrowed).sub(pendingFee());

    _redeemWithFlashloan(Math.min(balance, available), 0);
    available = CTokenInterface(_cToken).getCash();
    supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    if (Math.min(supplied, available) > pendingFee()) {
      _redeem(Math.min(supplied, available).sub(pendingFee().add(1)));
    }
  }

  function _depositWithFlashloan() internal {
    address _cToken = cToken();
    uint256 _denom = factorDenominator();
    uint256 _borrowNum = borrowTargetFactorNumerator();
    // amount we supplied
    uint256 supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    // amount we borrowed
    uint256 borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
    uint256 balance = supplied.sub(borrowed);
    uint256 borrowTarget = balance.mul(_borrowNum).div(_denom.sub(_borrowNum));

    if (borrowed > borrowTarget) {
      _redeemPartial(0);
      borrowTarget = borrowed;
    } else {
      address _comptroller = comptroller();
      uint256 borrowCap = IComptroller(_comptroller).borrowCaps(_cToken);
      uint256 supplyCap = IComptroller(_comptroller).supplyCaps(_cToken);
      if (borrowCap == 0) {
        borrowCap = type(uint256).max;
      }
      if (supplyCap == 0) {
        supplyCap = type(uint256).max;
      }
      uint256 totalBorrow = CTokenInterface(_cToken).totalBorrows();
      uint256 totalSupply = IERC20(_cToken).totalSupply().mul(CTokenInterface(_cToken).exchangeRateCurrent()).div(1e18);
      uint256 borrowAvail;
      if (totalBorrow < borrowCap) {
        borrowAvail = borrowCap.sub(totalBorrow).sub(2);
        if (totalSupply < supplyCap) {
          borrowAvail = Math.min(supplyCap.sub(totalSupply).sub(2), borrowAvail);
        } else {
          borrowAvail = 0;
        }
      } else {
        borrowAvail = 0;
      }
      borrowTarget = Math.min(borrowTarget, borrowed.add(borrowAvail));
    }
    uint256 borrowDiff = borrowTarget.sub(borrowed);
    address _underlying = underlying();
    uint256 balancerBalance = IERC20(_underlying).balanceOf(bVault);

    if (borrowDiff > balancerBalance) {
      _depositNoFlash(borrowTarget);
    } else {
      address[] memory tokens = new address[](1);
      uint256[] memory amounts = new uint256[](1);
      bytes memory userData = abi.encode(0);
      tokens[0] = underlying();
      amounts[0] = borrowDiff;
      makingFlashDeposit = true;
      IBVault(bVault).flashLoan(address(this), tokens, amounts, userData);
      makingFlashDeposit = false;
    }
  }

  function _redeemWithFlashloan(uint256 amount, uint256 _borrowTargetFactorNumerator) internal {
    address _cToken = cToken();
    // amount we supplied
    uint256 supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    // amount we borrowed
    uint256 borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
    uint256 newBorrowTarget;
    {
      uint256 oldBalance = supplied.sub(borrowed);
      uint256 newBalance = oldBalance.sub(amount);
      newBorrowTarget = newBalance.mul(_borrowTargetFactorNumerator).div(factorDenominator().sub(_borrowTargetFactorNumerator));
    }
    uint256 borrowDiff;
    if (borrowed < newBorrowTarget) {
      borrowDiff = 0;
    } else {
      borrowDiff = borrowed.sub(newBorrowTarget);
    }

    address _underlying = underlying();
    uint256 balancerBalance = IERC20(_underlying).balanceOf(bVault);

    if (borrowDiff > balancerBalance) {
      _redeemNoFlash(amount, newBorrowTarget);
    } else {
      address[] memory tokens = new address[](1);
      uint256[] memory amounts = new uint256[](1);
      bytes memory userData = abi.encode(0);
      tokens[0] = _underlying;
      amounts[0] = borrowDiff;
      makingFlashWithdrawal = true;
      IBVault(bVault).flashLoan(address(this), tokens, amounts, userData);
      makingFlashWithdrawal = false;
      _redeem(amount);
    }
  }

  function receiveFlashLoan(IERC20[] memory /*tokens*/, uint256[] memory amounts, uint256[] memory feeAmounts, bytes memory /*userData*/) external {
    require(msg.sender == bVault);
    require(!makingFlashDeposit || !makingFlashWithdrawal, "Only one can be true");
    require(makingFlashDeposit || makingFlashWithdrawal, "One has to be true");
    address _underlying = underlying();
    uint256 toRepay = amounts[0].add(feeAmounts[0]);
    if (makingFlashDeposit){
      _supply(amounts[0]);
      _borrow(toRepay);
    } else {
      address _cToken = cToken();
      uint256 borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
      uint256 repaying = Math.min(amounts[0], borrowed);
      IERC20(_underlying).safeApprove(_cToken, 0);
      IERC20(_underlying).safeApprove(_cToken, repaying);
      _repay(repaying);
      _redeem(toRepay);
    }
    IERC20(_underlying).safeTransfer(bVault, toRepay);
  }

  function _depositNoFlash(uint256 borrowTarget) internal {
    address _underlying = underlying();
    address _cToken = cToken();
    uint256 borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
    uint256 supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));

    while (borrowed < borrowTarget) {
      uint256 wantBorrow = borrowTarget.sub(borrowed);
      uint256 maxBorrow = supplied.mul(collateralFactorNumerator()).div(factorDenominator()).sub(borrowed);
      _borrow(Math.min(wantBorrow, maxBorrow));
      uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
      if (underlyingBalance > 0) {
        _supply(underlyingBalance);
      }
      //update parameters
      borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
      supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    }
  }

  function _redeemNoFlash(uint256 amount, uint256 newBorrowTarget) internal {
    address _underlying = underlying();
    address _cToken = cToken();
    uint256 borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
    uint256 supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    
    while (borrowed > newBorrowTarget) {
      uint256 requiredCollateral = borrowed.mul(factorDenominator()).div(collateralFactorNumerator());
      uint256 toRepay = borrowed.sub(newBorrowTarget);
      // redeem just as much as needed to repay the loan
      // supplied - requiredCollateral = max redeemable, amount + repay = needed
      uint256 toRedeem = Math.min(supplied.sub(requiredCollateral), amount.add(toRepay));
      _redeem(toRedeem);
      // now we can repay our borrowed amount
      uint256 balance = IERC20(_underlying).balanceOf(address(this));
      _repay(Math.min(toRepay, balance));
      // update the parameters
      borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
      supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    }
    uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
    if (underlyingBalance < amount) {
      uint256 toRedeem = amount.sub(underlyingBalance);
      uint256 balance = supplied.sub(borrowed);
      // redeem the most we can redeem
      _redeem(Math.min(toRedeem, balance));
    }
  }

  // updating collateral factor
  // note 1: one should settle the loan first before calling this
  // note 2: collateralFactorDenominator is 1000, therefore, for 20%, you need 200
  function _setCollateralFactorNumerator(uint256 _numerator) public onlyGovernance {
    require(_numerator <= factorDenominator(), "Collateral factor cannot be this high");
    require(_numerator > borrowTargetFactorNumerator(), "Collateral factor should be higher than borrow target");
    setUint256(_COLLATERALFACTORNUMERATOR_SLOT, _numerator);
  }

  function collateralFactorNumerator() public view returns (uint256) {
    return getUint256(_COLLATERALFACTORNUMERATOR_SLOT);
  }

  function _setFactorDenominator(uint256 _denominator) internal {
    setUint256(_FACTORDENOMINATOR_SLOT, _denominator);
  }

  function factorDenominator() public view returns (uint256) {
    return getUint256(_FACTORDENOMINATOR_SLOT);
  }

  function setBorrowTargetFactorNumerator(uint256 _numerator) public onlyGovernance {
    require(_numerator < collateralFactorNumerator(), "Target should be lower than collateral limit");
    setUint256(_BORROWTARGETFACTORNUMERATOR_SLOT, _numerator);
  }

  function borrowTargetFactorNumerator() public view returns (uint256) {
    return getUint256(_BORROWTARGETFACTORNUMERATOR_SLOT);
  }

  function setFold (bool _fold) public onlyGovernance {
    setBoolean(_FOLD_SLOT, _fold);
  }

  function fold() public view returns (bool) {
    return getBoolean(_FOLD_SLOT);
  }

  function _setCToken (address _target) internal {
    setAddress(_CTOKEN_SLOT, _target);
  }

  function cToken() public view returns (address) {
    return getAddress(_CTOKEN_SLOT);
  }

  function _setComptroller (address _target) internal {
    setAddress(_COMPTROLLER_SLOT, _target);
  }

  function comptroller() public view returns (address) {
    return getAddress(_COMPTROLLER_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }

  receive() external payable {}
}