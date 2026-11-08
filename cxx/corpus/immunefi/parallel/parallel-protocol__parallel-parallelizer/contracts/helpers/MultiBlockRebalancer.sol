// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseRebalancer, YieldBearingParams } from "./BaseRebalancer.sol";
import { IParallelizer } from "contracts/interfaces/IParallelizer.sol";
import { ITokenP } from "contracts/interfaces/ITokenP.sol";
import { IPool } from "contracts/interfaces/IPool.sol";

import "../utils/Errors.sol";
import "../utils/Constants.sol";

/// @title MultiBlockRebalancer
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @dev Contract to harvest yield from multiple yield bearing assets in multiple blocks transactions
/// @dev This contract is an authorized fork of Angle's MultiBlockHarvester contract:
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/helpers/MultiBlockHarvester.sol
contract MultiBlockRebalancer is BaseRebalancer {
  using SafeERC20 for IERC20;
  using Math for uint256;

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice address to deposit to receive yieldBearingAsset
  mapping(address => address) public yieldBearingToDepositAddress;

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       CONSTRUCTOR
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  constructor(
    address initialAuthority,
    ITokenP definitivetokenP,
    IParallelizer definitiveParallelizer
  )
    BaseRebalancer(initialAuthority, definitivetokenP, definitiveParallelizer)
  { }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        GUARDIAN FUNCTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /**
   * @notice Set the deposit address for a yieldBearingAsset
   * @param yieldBearingAsset address of the yieldBearingAsset
   * @param newDepositAddress address to deposit to receive yieldBearingAsset
   */
  function setYieldBearingToDepositAddress(address yieldBearingAsset, address newDepositAddress) external restricted {
    address previousDepositAddress = yieldBearingToDepositAddress[yieldBearingAsset];
    address asset = yieldBearingData[yieldBearingAsset].asset;
    // The outgoing deposit address would otherwise keep its allowance over the underlying asset
    if (previousDepositAddress != address(0) && previousDepositAddress != newDepositAddress && asset != address(0)) {
      IERC20(asset).forceApprove(previousDepositAddress, 0);
      emit AllowanceReset(asset, previousDepositAddress);
    }
    yieldBearingToDepositAddress[yieldBearingAsset] = newDepositAddress;
  }

  /// @inheritdoc BaseRebalancer
  function _revokeAssetAllowances(address yieldBearingAsset, address previousAsset) internal override {
    address depositAddress = yieldBearingToDepositAddress[yieldBearingAsset];
    if (depositAddress != address(0)) {
      IERC20(previousAsset).forceApprove(depositAddress, 0);
      emit AllowanceReset(previousAsset, depositAddress);
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        TRUSTED FUNCTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /**
   * @notice Initiate a rebalance
   * @param scale scale to apply to the rebalance amount
   * @param yieldBearingAsset address of the yieldBearingAsset
   */
  function harvest(address yieldBearingAsset, uint256 scale, bytes calldata) external onlyTrusted {
    if (scale > 1e9) revert InvalidParam();
    updateLimitExposuresYieldAsset(yieldBearingAsset);
    YieldBearingParams memory yieldBearingInfo = yieldBearingData[yieldBearingAsset];
    (uint8 increase, uint256 amount) = _computeRebalanceAmount(yieldBearingAsset, yieldBearingInfo);
    amount = (amount * scale) / 1e9;
    if (amount == 0) revert ZeroAmount();

    try parallelizer.updateOracle(yieldBearingAsset) { } catch { }
    _rebalance(increase, yieldBearingAsset, yieldBearingInfo, amount);
  }

  /**
   * @notice Finalize a rebalance
   * @param yieldBearingAsset address of the yieldBearingAsset
   */
  function finalizeRebalance(address yieldBearingAsset, uint256 balance) external onlyTrusted {
    try parallelizer.updateOracle(yieldBearingAsset) { } catch { }
    _adjustAllowance(yieldBearingAsset, address(parallelizer), balance);
    uint256 amountOut =
      parallelizer.swapExactInput(balance, 0, yieldBearingAsset, address(tokenP), address(this), block.timestamp);
    address depositAddress = yieldBearingAsset == XEVT ? yieldBearingToDepositAddress[yieldBearingAsset] : address(0);
    _checkSlippage(
      balance, amountOut, yieldBearingAsset, depositAddress, true, yieldBearingData[yieldBearingAsset].maxSlippage
    );
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _rebalance(
    uint8 typeAction,
    address yieldBearingAsset,
    YieldBearingParams memory yieldBearingInfo,
    uint256 amount
  )
    internal
  {
    address depositAddress = yieldBearingToDepositAddress[yieldBearingAsset];
    if (typeAction == 1) {
      uint256 amountOut =
        parallelizer.swapExactInput(amount, 0, address(tokenP), yieldBearingInfo.asset, address(this), block.timestamp);
      if (yieldBearingAsset == XEVT) {
        _adjustAllowance(yieldBearingInfo.asset, address(depositAddress), amountOut);
        (uint256 shares,) = IPool(depositAddress).deposit(amountOut, address(this));
        _adjustAllowance(yieldBearingAsset, address(parallelizer), shares);
        amountOut =
          parallelizer.swapExactInput(shares, 0, yieldBearingAsset, address(tokenP), address(this), block.timestamp);
        _checkSlippage(amount, amountOut, address(tokenP), depositAddress, false, yieldBearingInfo.maxSlippage);
      } else if (yieldBearingAsset == USDM) {
        IERC20(yieldBearingInfo.asset).safeTransfer(depositAddress, amountOut);
        _checkSlippage(amount, amountOut, yieldBearingInfo.asset, depositAddress, false, yieldBearingInfo.maxSlippage);
      }
    } else {
      uint256 amountOut =
        parallelizer.swapExactInput(amount, 0, address(tokenP), yieldBearingAsset, address(this), block.timestamp);
      if (yieldBearingAsset == USDM) amountOut = IERC20(yieldBearingAsset).balanceOf(address(this));
      _checkSlippage(amount, amountOut, yieldBearingAsset, depositAddress, false, yieldBearingInfo.maxSlippage);
      if (yieldBearingAsset == XEVT) {
        IPool(depositAddress).requestRedeem(amountOut);
      } else if (yieldBearingAsset == USDM) {
        IERC20(yieldBearingAsset).safeTransfer(depositAddress, amountOut);
      }
    }
  }

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    HELPER                                                      
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  function _checkSlippage(
    uint256 amountIn,
    uint256 amountOut,
    address asset,
    address depositAddress,
    bool assetIn,
    uint64 maxSlippage
  )
    internal
    view
  {
    // Divide or multiply the amountIn to match the decimals of the asset
    amountIn = _scaleAmountBasedOnDecimals(IERC20Metadata(asset).decimals(), 18, amountIn, assetIn);

    uint256 result;
    if (asset == USDC || asset == USDM || asset == EURC || asset == address(tokenP)) {
      // Assume 1:1 ratio between stablecoins
      (, result) = amountIn.trySub(amountOut);
    } else if (asset == XEVT) {
      // Assume 1:1 ratio between the underlying asset of the vault
      if (assetIn) {
        (, result) = IPool(depositAddress).convertToAssets(amountIn).trySub(amountOut);
      } else {
        (, result) = amountIn.trySub(IPool(depositAddress).convertToAssets(amountOut));
      }
    } else {
      revert InvalidParam();
    }

    uint256 slippage = (result * 1e9) / amountIn;
    if (slippage > maxSlippage) revert SlippageTooHigh();
  }
}
