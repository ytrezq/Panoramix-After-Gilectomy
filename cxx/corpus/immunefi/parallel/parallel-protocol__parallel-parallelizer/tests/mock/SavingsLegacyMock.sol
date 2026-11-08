// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ITokenP } from "contracts/interfaces/ITokenP.sol";
import { BaseSavings } from "contracts/savings/BaseSavings.sol";
import { SavingsEIP3009 } from "contracts/savings/SavingsEIP3009.sol";

import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol";

/// @title SavingsLegacyMock
/// @notice Mirrors the pre-storedAssets Savings + SavingsNameable storage and behaviour, used
/// solely as the "before" implementation in upgrade tests. Storage layout matches the production
/// SavingsNameable contract on `audit/eip3009-hotfix-fees` *before* this PR introduced the
/// `storedAssets` slot:
///   slot 0: rate (uint208) + lastUpdate (uint40) + paused (uint8)
///   slot 1: maxRate
///   slot 2: isTrustedUpdater
///   slots 3..50: __gap (48 entries)
///   slot 51: __name
///   slot 52: __symbol
///   slots 53..100: __gapNameable (48 entries)
contract SavingsLegacyMock is BaseSavings, SavingsEIP3009 {
  using Math for uint256;

  uint208 public rate;
  uint40 public lastUpdate;
  uint8 public paused;
  uint256 public maxRate;
  mapping(address => uint256) public isTrustedUpdater;
  uint256[48] private __gap;

  string internal __name;
  string internal __symbol;
  uint256[48] private __gapNameable;

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
    __ERC4626_init(asset_);
    __ERC20_init(name_, symbol_);
    __UUPSUpgradeable_init();
    __AccessManaged_init(_authority);
    __name = name_;
    __symbol = symbol_;
    _deposit(msg.sender, address(this), 10 ** (asset_.decimals()) / divizer, BASE_18 / divizer);
  }

  modifier whenNotPaused() {
    if (paused > 0) revert Paused();
    _;
  }

  /// @notice Legacy implementation: reads raw ERC20 balance (the source of the donation
  /// vulnerability) and projects it through the rate formula.
  function totalAssets() public view override returns (uint256) {
    return _computeUpdatedAssets(super.totalAssets(), block.timestamp - lastUpdate);
  }

  function name() public view override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
    return __name;
  }

  function symbol() public view override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
    return __symbol;
  }

  function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256 shares) {
    uint256 newTotalAssets = _accrue();
    shares = _convertToShares(assets, newTotalAssets, Math.Rounding.Floor);
    _deposit(_msgSender(), receiver, assets, shares);
  }

  function redeem(
    uint256 shares,
    address receiver,
    address owner
  )
    public
    override
    whenNotPaused
    returns (uint256 assets)
  {
    uint256 newTotalAssets = _accrue();
    assets = _convertToAssets(shares, newTotalAssets, Math.Rounding.Floor);
    _withdraw(_msgSender(), receiver, owner, assets, shares);
  }

  function decimals() public view override(ERC4626Upgradeable, ERC20Upgradeable) returns (uint8) {
    return super.decimals();
  }

  function _accrue() internal returns (uint256 newTotalAssets) {
    uint256 currentBalance = super.totalAssets();
    newTotalAssets = _computeUpdatedAssets(currentBalance, block.timestamp - lastUpdate);
    lastUpdate = uint40(block.timestamp);
    uint256 earned = newTotalAssets - currentBalance;
    if (earned > 0) {
      ITokenP(asset()).mint(address(this), earned);
    }
  }

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

  function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256 shares) {
    return _convertToShares(assets, totalAssets(), rounding);
  }

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

  function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256 assets) {
    return _convertToAssets(shares, totalAssets(), rounding);
  }

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
}
