// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

/// @title LiquidityMigrator
/// @notice Allows the instance owner to migrate a pool position of a user from one pool to another. The user gives an approval of
///         their pool shares to this contract. The instance owner can then migrate assets from specfic `poolFrom` to specific `poolTo`
///         at their discretion.
contract LiquidityMigrator is Ownable, IVersion {
    using SafeERC20 for IERC20;

    bytes32 public constant contractType = "ZAPPER::LIQUIDITY_MIGRATOR";
    uint256 public constant version = 310;

    error PoolAssetsDoNotMatchException();

    event Migrate(address indexed user, uint256 assetsAmount);

    /// @notice The pool the assets are being migrated from
    address public immutable poolFrom;
    /// @notice The pool the assets are being migrated to
    address public immutable poolTo;

    /// @notice Constructs a new LiquidityMigrator
    /// @param ioProxy The address of the Instance Owner's ProxyCall contract. The instance owner migrates liquidity by
    ///                calling `migrate` through the proxy.
    /// @param _poolFrom The address of the pool the assets are being migrated from.
    /// @param _poolTo The address of the pool the assets are being migrated to.
    constructor(address ioProxy, address _poolFrom, address _poolTo) {
        _transferOwnership(ioProxy);
        poolFrom = _poolFrom;
        poolTo = _poolTo;

        address assetTo = IERC4626(poolTo).asset();
        address assetFrom = IERC4626(poolFrom).asset();

        if (assetTo != assetFrom) {
            revert PoolAssetsDoNotMatchException();
        }

        IERC20(assetTo).forceApprove(poolTo, type(uint256).max);
    }

    /// @notice Migrates assets from `poolFrom` to `poolTo` for `user`
    /// @param user The address of the user whose assets are being migrated
    /// @param amount The amount of `poolFrom` LP shares to migrate
    function migrate(address user, uint256 amount) external onlyOwner {
        // Shares are redeemed from `poolFrom`, which returns the amount of assets withdrawn
        uint256 assetsAmount = IERC4626(poolFrom).redeem(amount, address(this), user);
        // The same amount of assets is deposited into `poolTo`, with the user as the receiver of new LP shares
        IERC4626(poolTo).deposit(assetsAmount, user);

        emit Migrate(user, assetsAmount);
    }
}
