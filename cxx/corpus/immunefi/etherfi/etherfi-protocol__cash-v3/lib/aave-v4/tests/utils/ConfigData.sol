// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IHub} from 'src/hub/interfaces/IHub.sol';
import {ISpoke} from 'src/spoke/interfaces/ISpoke.sol';

/// @title ConfigData Library
/// @author Aave Labs
/// @notice Parameter structs for post-deployment configuration operations (asset listing, reserve setup, etc.).
library ConfigData {
  /// @dev hub Target Hub address.
  /// @dev underlying The underlying ERC20 token address.
  /// @dev decimals The decimals of the underlying token.
  /// @dev feeReceiver The address that receives fees.
  /// @dev liquidityFee The liquidity fee in basis points.
  /// @dev irStrategy The InterestRateStrategy contract address.
  /// @dev reinvestmentController The reinvestment controller address.
  /// @dev irData Encoded interest rate parameters.
  struct AddAssetParams {
    address hub;
    address underlying;
    uint8 decimals;
    address feeReceiver;
    uint16 liquidityFee;
    address irStrategy;
    address reinvestmentController;
    bytes irData;
  }

  /// @dev hub Target Hub address.
  /// @dev assetId The ID of the asset to update.
  /// @dev config The new asset configuration.
  /// @dev irData Encoded interest rate parameters.
  struct UpdateAssetConfigParams {
    address hub;
    uint256 assetId;
    IHub.AssetConfig config;
    bytes irData;
  }

  /// @dev hub Target Hub address.
  /// @dev assetId The asset ID to register the Spoke for.
  /// @dev spoke The Spoke address to register.
  /// @dev config The Spoke configuration (caps, thresholds, status).
  struct AddSpokeParams {
    address hub;
    uint256 assetId;
    address spoke;
    IHub.SpokeConfig config;
  }

  /// @dev hub Target Hub address.
  /// @dev spoke The Spoke address to register.
  /// @dev assetIds The asset IDs to register the Spoke for.
  /// @dev configs The Spoke configurations (parallel to assetIds).
  struct AddSpokeToAssetsParams {
    address hub;
    address spoke;
    uint256[] assetIds;
    IHub.SpokeConfig[] configs;
  }

  /// @dev spoke Target Spoke address.
  /// @dev config The liquidation configuration.
  struct UpdateLiquidationConfigParams {
    address spoke;
    ISpoke.LiquidationConfig config;
  }

  /// @dev spoke Target Spoke address.
  /// @dev hub The Hub the reserve is associated with.
  /// @dev assetId The asset ID on the Hub.
  /// @dev priceSource The oracle price source address.
  /// @dev config The reserve configuration.
  /// @dev dynamicConfig The dynamic reserve configuration.
  struct AddReserveParams {
    address spoke;
    address hub;
    uint256 assetId;
    address priceSource;
    ISpoke.ReserveConfig config;
    ISpoke.DynamicReserveConfig dynamicConfig;
  }
}
