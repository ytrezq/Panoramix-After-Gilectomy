// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IEIP3009 } from "contracts/interfaces/external/IEIP3009.sol";

import "./BaseSavings.sol";
import "./SavingsEIP3009.sol";

/// @title Savings
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice In this implementation, assets in the contract increase in value following a `rate` chosen by governance
/// @dev This contract is an authorized fork of Angle's Savings contract:
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/savings/Savings.sol
contract Savings is BaseSavings, SavingsEIP3009 {
  using SafeERC20 for IERC20Metadata;
  using Math for uint256;

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    PARAMETERS / REFERENCES
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Inflation rate (per second) in BASE_27
  uint208 public rate;

  /// @notice Last time rewards were accrued
  uint40 public lastUpdate;

  /// @notice Whether the contract is paused or not
  uint8 public paused;

  /// @notice Maximum inflation rate
  uint256 public maxRate;

  /// @notice Checks whether the address is trusted to set the rate
  mapping(address => uint256) public isTrustedUpdater;

  /// @notice Tracked balance of `asset` backing share holders
  /// @dev Distinct from `IERC20(asset()).balanceOf(address(this))`: only updated by `deposit`/`mint`,
  /// `withdraw`/`redeem`, the EIP-3009 authorized variants and `_accrue`. Direct ERC20 transfers
  /// to this contract are *not* counted as backing, neutralizing donation/inflation attacks.
  /// The surplus (`balanceOf(self) - storedAssets`) can be retrieved via `recoverSurplus`.
  uint256 public storedAssets;

  uint256[47] private __gap;

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    EVENTS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  event Accrued(uint256 interest);
  event MaxRateUpdated(uint256 newMaxRate);
  event ToggledPause(uint128 pauseStatus);
  event ToggledTrusted(address indexed trustedAddress, uint256 trustedStatus);
  event RateUpdated(uint256 newRate);
  event SurplusRecovered(address indexed to, uint256 amount);

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    INITIALIZATION
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Initializes the contract
  /// @param _authority Reference to the `AccessManagerContract` contract
  /// @param name_ Name of the savings contract
  /// @param symbol_ Symbol of the savings contract
  /// @param divizer Quantifies the first initial deposit (should be typically 1 for tokens like agEUR)
  /// @dev A first deposit is done at initialization to protect for the classical issue of ERC4626 contracts
  /// where the the first user of the contract tries to steal everyone else's tokens
  function initialize(
    address _authority,
    IERC20Metadata asset_,
    string memory name_,
    string memory symbol_,
    uint256 divizer
  )
    public
    initializer
  {
    if (address(_authority) == address(0)) revert ZeroAddress();
    if (bytes(name_).length == 0 || bytes(symbol_).length == 0) revert InvalidParam();
    if (divizer == 0 || BASE_18 / divizer == 0 || 10 ** asset_.decimals() / divizer == 0) revert InvalidParam();
    __ERC4626_init(asset_);
    __ERC20_init(name_, symbol_);
    __UUPSUpgradeable_init();
    __AccessManaged_init(_authority);
    _setNameAndSymbol(name_, symbol_);
    _deposit(msg.sender, address(this), 10 ** (asset_.decimals()) / divizer, BASE_18 / divizer);
    lastUpdate = uint40(block.timestamp);
  }

  /// @notice One-shot reinitializer for upgrades that introduce `storedAssets`
  /// @dev Seeds `storedAssets` with the current ERC20 balance held by the contract, so existing
  /// legitimately deposited assets remain backing. Any subsequent direct transfer is treated as a
  /// donation surplus and ignored by `totalAssets()` until `recoverSurplus` is called.
  function initializeStoredAssets() external restricted reinitializer(2) {
    if (block.timestamp - lastUpdate > MAX_STORED_ASSETS_INIT_STALENESS) revert StaleAccrual();
    storedAssets = IERC20Metadata(asset()).balanceOf(address(this));
    lastUpdate = uint40(block.timestamp);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    MODIFIERS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Checks whether the whole contract is paused or not
  modifier whenNotPaused() {
    if (paused > 0) revert Paused();
    _;
  }

  /// @notice Checks whether the sender is allowed to update the rate
  modifier onlyTrustedOrRestricted() {
    if (isTrustedUpdater[msg.sender] == 0 && !_checkCanCall(_msgSender(), _msgData())) {
      revert NotTrusted();
    }
    _;
  }

  /// @notice Reverts when shares exist but `storedAssets` was never seeded (non-atomic upgrade)
  modifier onlyInitialized() {
    if (storedAssets == 0 && totalSupply() != 0) revert NotInitialized();
    _;
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    CONTRACT LOGIC
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Accrues interest to this contract by minting tokenPs
  /// @dev Uses the tracked `storedAssets` rather than `IERC20.balanceOf(self)` so that donations
  /// can never inflate the accrual base.
  function _accrue() internal returns (uint256 newTotalAssets) {
    uint256 currentBalance = storedAssets;
    if (paused > 0) {
      lastUpdate = uint40(block.timestamp);
      return currentBalance;
    }
    newTotalAssets = _computeUpdatedAssets(currentBalance, block.timestamp - lastUpdate);
    lastUpdate = uint40(block.timestamp);
    uint256 earned = newTotalAssets - currentBalance;
    if (earned > 0) {
      ITokenP(asset()).mint(address(this), earned);
      storedAssets = newTotalAssets;
      emit Accrued(earned);
    }
  }

  /// @notice Computes how much `currentBalance` held in the contract would be after `exp` time following
  /// the `rate` of increase
  function _computeUpdatedAssets(uint256 currentBalance, uint256 exp) internal view returns (uint256) {
    uint256 ratePerSecond = rate;
    if (exp == 0 || ratePerSecond == 0) return currentBalance;
    uint256 expMinusOne = exp - 1;
    uint256 expMinusTwo = exp > 2 ? exp - 2 : 0;
    uint256 basePowerTwo = (ratePerSecond * ratePerSecond + HALF_BASE_27) / BASE_27;
    uint256 basePowerThree = (basePowerTwo * ratePerSecond + HALF_BASE_27) / BASE_27;
    uint256 secondTerm = (exp * expMinusOne * basePowerTwo) / 2;
    uint256 thirdTerm = (exp * expMinusOne * expMinusTwo * basePowerThree) / 6;
    return (currentBalance * (BASE_27 + ratePerSecond * exp + secondTerm + thirdTerm)) / BASE_27;
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ERC4626 VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @inheritdoc ERC4626Upgradeable
  /// @dev Returns the projection of `storedAssets` rather than `IERC20.balanceOf(self)`.
  /// Direct ERC20 transfers to this contract do not affect this value.
  function totalAssets() public view override returns (uint256) {
    if (paused > 0) return storedAssets;
    return _computeUpdatedAssets(storedAssets, block.timestamp - lastUpdate);
  }

  /// @inheritdoc ERC4626Upgradeable
  function maxDeposit(address receiver) public view override returns (uint256) {
    return paused > 0 ? 0 : super.maxDeposit(receiver);
  }

  /// @inheritdoc ERC4626Upgradeable
  function maxMint(address receiver) public view override returns (uint256) {
    return paused > 0 ? 0 : super.maxMint(receiver);
  }

  /// @inheritdoc ERC4626Upgradeable
  function maxWithdraw(address owner) public view override returns (uint256) {
    return paused > 0 ? 0 : super.maxWithdraw(owner);
  }

  /// @inheritdoc ERC4626Upgradeable
  function maxRedeem(address owner) public view override returns (uint256) {
    return paused > 0 ? 0 : super.maxRedeem(owner);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ERC4626 INTERACTION FUNCTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @inheritdoc ERC4626Upgradeable
  function deposit(
    uint256 assets,
    address receiver
  )
    public
    override
    whenNotPaused
    onlyInitialized
    returns (uint256 shares)
  {
    uint256 newTotalAssets = _accrue();
    uint256 maxAssets = maxDeposit(receiver);
    if (assets > maxAssets) revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
    shares = _convertToShares(assets, newTotalAssets, Math.Rounding.Floor);
    _deposit(_msgSender(), receiver, assets, shares);
  }

  /// @inheritdoc ERC4626Upgradeable
  function mint(
    uint256 shares,
    address receiver
  )
    public
    override
    whenNotPaused
    onlyInitialized
    returns (uint256 assets)
  {
    uint256 newTotalAssets = _accrue();
    uint256 maxShares = maxMint(receiver);
    if (shares > maxShares) revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
    assets = _convertToAssets(shares, newTotalAssets, Math.Rounding.Ceil);
    _deposit(_msgSender(), receiver, assets, shares);
  }

  /// @inheritdoc ERC4626Upgradeable
  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  )
    public
    override
    whenNotPaused
    onlyInitialized
    returns (uint256 shares)
  {
    uint256 newTotalAssets = _accrue();
    uint256 maxAssets = maxWithdraw(owner);
    if (assets > maxAssets) revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
    shares = _convertToShares(assets, newTotalAssets, Math.Rounding.Ceil);
    _withdraw(_msgSender(), receiver, owner, assets, shares);
  }

  /// @inheritdoc ERC4626Upgradeable
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  )
    public
    override
    whenNotPaused
    onlyInitialized
    returns (uint256 assets)
  {
    uint256 newTotalAssets = _accrue();
    uint256 maxShares = maxRedeem(owner);
    if (shares > maxShares) revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
    assets = _convertToAssets(shares, newTotalAssets, Math.Rounding.Floor);
    _withdraw(_msgSender(), receiver, owner, assets, shares);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    AUTHORIZED DEPOSITS / REDEMPTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Deposits the underlying asset on behalf of `owner` using a signed authorization,
  /// and mints shares to `receiver`.
  /// @dev Two signatures:
  ///   - `savingsSignature` binds `receiver` via `DEPOSIT_WITH_AUTHORIZATION_TYPEHASH` on this
  ///     contract's EIP-712 domain (front-run protection on the shares recipient).
  ///   - `tokenSignature` is a standard EIP-3009 `ReceiveWithAuthorization` on the underlying
  ///     asset that pulls `assets` from `owner` into this contract.
  /// Both may share the same `nonce`/validity window — they're tracked on different contracts.
  function depositWithAuthorization(
    uint256 assets,
    address receiver,
    address owner,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    bytes calldata savingsSignature,
    bytes calldata tokenSignature
  )
    external
    whenNotPaused
    onlyInitialized
    returns (uint256 shares)
  {
    _consumeDepositAuthorization(
      address(this), owner, receiver, assets, validAfter, validBefore, nonce, savingsSignature
    );

    uint256 newTotalAssets = _accrue();
    if (assets > maxDeposit(receiver)) revert ERC4626ExceededMaxDeposit(receiver, assets, maxDeposit(receiver));
    shares = _convertToShares(assets, newTotalAssets, Math.Rounding.Floor);
    IEIP3009(asset())
      .receiveWithAuthorization(owner, address(this), assets, validAfter, validBefore, nonce, tokenSignature);
    storedAssets += assets;
    _mint(receiver, shares);
    emit Deposit(owner, receiver, assets, shares);
  }

  /// @notice Burns `shares` from `owner` using a signed authorization, and sends the underlying
  /// asset to `receiver`.
  /// @dev The signature is signed over `REDEEM_WITH_AUTHORIZATION_TYPEHASH` against this
  /// contract's EIP-712 domain. It binds `receiver` so a relayer cannot redirect the redeemed
  /// underlying to an attacker-controlled address.
  /// @param shares The amount of shares to redeem
  /// @param receiver The address to receive the redeemed underlying
  /// @param owner The address of the owner of the shares
  /// @param validAfter The timestamp after which the authorization is valid
  /// @param validBefore The timestamp before which the authorization is valid
  /// @param nonce The nonce of the authorization
  /// @param v The recovery id of the signature
  /// @param r The r value of the signature
  /// @param s The s value of the signature
  /// @return assets The amount of underlying assets received
  function redeemWithAuthorization(
    uint256 shares,
    address receiver,
    address owner,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    external
    whenNotPaused
    returns (uint256 assets)
  {
    return _redeemWithAuthorization(shares, receiver, owner, validAfter, validBefore, nonce, abi.encodePacked(r, s, v));
  }

  /// @notice EIP-1271 compatible variant of `redeemWithAuthorization`.
  /// @dev The signature is signed over `REDEEM_WITH_AUTHORIZATION_TYPEHASH` against this
  /// contract's EIP-712 domain. It binds `receiver` so a relayer cannot redirect the redeemed
  /// underlying to an attacker-controlled address.
  /// @param shares The amount of shares to redeem
  /// @param receiver The address to receive the redeemed underlying
  /// @param owner The address of the owner of the shares
  /// @param validAfter The timestamp after which the authorization is valid
  /// @param validBefore The timestamp before which the authorization is valid
  /// @param nonce The nonce of the authorization
  /// @param signature The signature bytes signed by an EOA wallet or a contract wallet
  /// @return assets The amount of underlying assets received
  function redeemWithAuthorization(
    uint256 shares,
    address receiver,
    address owner,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    bytes calldata signature
  )
    external
    whenNotPaused
    returns (uint256 assets)
  {
    return _redeemWithAuthorization(shares, receiver, owner, validAfter, validBefore, nonce, signature);
  }

  function _redeemWithAuthorization(
    uint256 shares,
    address receiver,
    address owner,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    bytes memory signature
  )
    internal
    onlyInitialized
    returns (uint256 assets)
  {
    _consumeRedeemAuthorization(address(this), owner, receiver, shares, validAfter, validBefore, nonce, signature);
    uint256 newTotalAssets = _accrue();
    uint256 maxShares = maxRedeem(owner);
    if (shares > maxShares) revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
    assets = _convertToAssets(shares, newTotalAssets, Math.Rounding.Floor);
    storedAssets -= assets;
    _burn(owner, shares);
    SafeERC20.safeTransfer(IERC20Metadata(asset()), receiver, assets);
    emit Withdraw(msg.sender, receiver, owner, assets, shares);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    INTERNAL HELPERS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @inheritdoc ERC4626Upgradeable
  function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256 shares) {
    return _convertToShares(assets, totalAssets(), rounding);
  }

  /// @notice Same as the function above except that the `totalAssets` value does not have to be recomputed here
  function _convertToShares(
    uint256 assets,
    uint256 newTotalAssets,
    Math.Rounding rounding
  )
    internal
    view
    returns (uint256 shares)
  {
    uint256 supply = totalSupply();
    return (assets == 0 || supply == 0)
      ? assets.mulDiv(BASE_18, 10 ** (IERC20Metadata(asset()).decimals()), rounding)
      : assets.mulDiv(supply, newTotalAssets, rounding);
  }

  /// @inheritdoc ERC4626Upgradeable
  function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256 assets) {
    return _convertToAssets(shares, totalAssets(), rounding);
  }

  /// @notice Same as the function above except that the `totalAssets` value does not have to be recomputed here
  function _convertToAssets(
    uint256 shares,
    uint256 newTotalAssets,
    Math.Rounding rounding
  )
    internal
    view
    returns (uint256 assets)
  {
    uint256 supply = totalSupply();
    return (supply == 0)
      ? shares.mulDiv(10 ** (IERC20Metadata(asset()).decimals()), BASE_18, rounding)
      : shares.mulDiv(newTotalAssets, supply, rounding);
  }

  function decimals() public view override(ERC4626Upgradeable, ERC20Upgradeable) returns (uint8) {
    return super.decimals();
  }

  function _setNameAndSymbol(string memory newName, string memory newSymbol) internal virtual { }

  /// @inheritdoc ERC4626Upgradeable
  /// @dev Mirrors deposits into `storedAssets` so direct transfers stay outside the backing.
  function _deposit(
    address caller,
    address receiver,
    uint256 assets,
    uint256 shares
  )
    internal
    override
  {
    super._deposit(caller, receiver, assets, shares);
    storedAssets += assets;
  }

  /// @inheritdoc ERC4626Upgradeable
  /// @dev Mirrors withdrawals out of `storedAssets`.
  function _withdraw(
    address caller,
    address receiver,
    address owner,
    uint256 assets,
    uint256 shares
  )
    internal
    override
  {
    storedAssets -= assets;
    super._withdraw(caller, receiver, owner, assets, shares);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    HELPERS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Provides an estimated Annual Percentage Yield for base depositors on this contract
  function estimatedAPY() external view returns (uint256 apy) {
    return _computeUpdatedAssets(BASE_18, SECONDS_PER_YEAR) - BASE_18;
  }

  /// @notice Wrapper on top of the `computeUpdatedAssets` function
  function computeUpdatedAssets(uint256 _totalAssets, uint256 exp) external view returns (uint256) {
    return _computeUpdatedAssets(_totalAssets, exp);
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    GOVERNANCE
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Pauses the contract — blocks `deposit`, `mint`, `withdraw`, `redeem` and the
  /// EIP-3009 authorized variants
  /// @dev Reverts if already paused, so a no-op governance call cannot pass silently. Accrues
  /// outstanding yield before flipping the flag so holders are settled the moment the vault stops
  /// accepting interactions, removing the stale-window deferral.
  function pause() external restricted {
    if (paused == 1) revert AlreadyPaused();
    _accrue();
    paused = 1;
    emit ToggledPause(1);
  }

  /// @notice Unpauses the contract
  /// @dev Reverts if not paused, so a no-op governance call cannot pass silently. Advances
  /// `lastUpdate` to the unpause timestamp so the paused interval is dropped rather than minted:
  /// pausing halts emission. `pause()` already settles yield up to the pause moment.
  function unpause() external restricted {
    if (paused == 0) revert NotPaused();
    lastUpdate = uint40(block.timestamp);
    paused = 0;
    emit ToggledPause(0);
  }

  /// @notice Toggles an address
  function toggleTrusted(address trustedAddress) external restricted {
    uint256 trustedStatus = 1 - isTrustedUpdater[trustedAddress];
    isTrustedUpdater[trustedAddress] = trustedStatus;
    emit ToggledTrusted(trustedAddress, trustedStatus);
  }

  /// @notice Updates the inflation rate for depositing `asset` in this contract
  /// @dev Any `rate` can be set by the guardian or by a trusted address provided that it is inferior to
  ///the `maxRate` settable by a governor address
  function setRate(uint208 newRate) external onlyTrustedOrRestricted {
    if (newRate > maxRate) revert InvalidRate();
    _accrue();
    rate = newRate;
    emit RateUpdated(newRate);
  }

  /// @notice Updates the maximum rate settable
  /// @dev Settles outstanding yield at the prior rate before mutating `maxRate`, then clamps the active `rate`
  /// down to the new cap when it would otherwise exceed it. This keeps the `rate <= maxRate` invariant intact
  /// across both setters in a single transaction.
  function setMaxRate(uint256 newMaxRate) external restricted {
    _accrue();
    maxRate = newMaxRate;
    if (rate > newMaxRate) {
      rate = uint208(newMaxRate);
      emit RateUpdated(newMaxRate);
    }
    emit MaxRateUpdated(newMaxRate);
  }

  /// @notice Transfers any `asset` balance held by the contract that is not part of the tracked
  /// `storedAssets` (i.e. donated or otherwise sent directly) to `to`
  /// @dev Scope is limited to the underlying `asset()`: it recovers the `balanceOf(self) - storedAssets`
  /// surplus only, and never any third-party ERC20 mistakenly sent here (use a dedicated rescue path for
  /// those). Restricted to governance. Cannot drain assets backing share holders since it returns `0`
  /// whenever the actual balance does not exceed `storedAssets`.
  /// @param to Recipient of the recovered surplus
  /// @return surplus Amount of `asset()` transferred out (0 when there is no surplus)
  function recoverSurplus(address to) external restricted returns (uint256 surplus) {
    if (to == address(0)) revert ZeroAddress();
    uint256 actualBalance = IERC20Metadata(asset()).balanceOf(address(this));
    uint256 stored = storedAssets;
    if (actualBalance <= stored) return 0;
    surplus = actualBalance - stored;
    IERC20Metadata(asset()).safeTransfer(to, surplus);
    emit SurplusRecovered(to, surplus);
  }
}
