// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IBaseStrategy} from "../interface/IBaseStrategy.sol";
import {IStrategyTemplate, StrategyType} from "../../interface/IStrategyTemplate.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {BaseStrategyStorageLib as BaseStrategyStorage} from "../lib/BaseStrategyStorageLib.sol";
import {PeripheryRolesLib} from "../lib/PeripheryRolesLib.sol";

/**
 * @title BaseStrategy
 * @dev Abstract base strategy implementation that provides common functionality
 * @dev for all strategy implementations including yield accrual and position management.
 * @dev Uses EIP-7201 storage layout for upgradeability.
 */
abstract contract BaseStrategy is IBaseStrategy, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @dev Constructor that disables initializers
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev External initializer function
     * @param admin The address that will have admin role
     * @param vault_ The address of the authorized vault
     */
    function initialize(address admin, address vault_) external initializer {
        _initializeBaseStrategy(admin, vault_);
    }

    /**
     * @dev Internal initializer function that can be called by child contracts
     * @param admin The address that will have admin role
     * @param vault_ The address of the authorized vault
     */
    function _initializeBaseStrategy(address admin, address vault_) internal virtual {
        if (admin == address(0)) revert ZeroAdminAddress();
        if (vault_ == address(0)) revert ZeroVaultAddress();

        __AccessControl_init();
        __Pausable_init();
        _setRoleAdmin(PeripheryRolesLib.STRATEGY_ADMIN, PeripheryRolesLib.STRATEGY_ADMIN_ADMIN);
        _setRoleAdmin(PeripheryRolesLib.OPERATOR_ROLE, PeripheryRolesLib.OPERATOR_ADMIN);
        _grantRole(PeripheryRolesLib.STRATEGY_ADMIN_ADMIN, admin);
        _grantRole(PeripheryRolesLib.OPERATOR_ADMIN, admin);
        _grantRole(PeripheryRolesLib.OPERATOR_ROLE, admin);
        _grantRole(PeripheryRolesLib.STRATEGY_ADMIN, admin);

        BaseStrategyStorage.BaseStrategyStorage storage baseStrategyStorage = BaseStrategyStorage.fetch();
        baseStrategyStorage.vault = vault_;
        baseStrategyStorage.asset = IERC4626(vault_).asset();
        // Default to unlimited withdrawals
        baseStrategyStorage.maxWithdraw = type(uint256).max;
    }

    /**
     * @dev Modifier to ensure only the authorized vault can call functions
     */
    modifier onlyVault() {
        BaseStrategyStorage.BaseStrategyStorage storage baseStrategyStorage = BaseStrategyStorage.fetch();
        if (msg.sender != baseStrategyStorage.vault) revert UnauthorizedVault();
        _;
    }

    /**
     * @dev Abstract virtual function to preview the current position value
     * @dev Must be implemented by derived strategies to return the current position value
     * @return The current position value
     */
    function _previewPosition() internal view virtual returns (uint256);

    /**
     * @dev Abstract virtual function to allocate funds to the position
     * @param data The data containing the amount to allocate and protocol specific data
     * @return The actual amount allocated
     */
    function _allocateToPosition(bytes calldata data) internal virtual returns (uint256);

    /**
     * @dev Abstract virtual function to deallocate funds from the position
     * @param data The data containing the amount to deallocate and protocol specific data
     * @return The actual amount deallocated
     */
    function _deallocateFromPosition(bytes calldata data) internal virtual returns (uint256);

    /**
     * @dev Abstract virtual function to withdraw funds from the position
     * @param assets The amount of assets to withdraw
     * @return The actual amount withdrawn
     */
    function _withdrawFromPosition(uint256 assets) internal virtual returns (uint256);

    /**
     * @inheritdoc IStrategyTemplate
     */
    function allocateFunds(bytes calldata data) external virtual override onlyVault whenNotPaused returns (uint256) {
        uint256 amountToAllocate;
        assembly {
            amountToAllocate := calldataload(data.offset)
        }
        if (amountToAllocate == 0) return 0;

        // Cache storage reference to avoid multiple sloads
        BaseStrategyStorage.BaseStrategyStorage storage baseStrategyStorage = BaseStrategyStorage.fetch();
        address vault = baseStrategyStorage.vault;

        IERC20(baseStrategyStorage.asset).safeTransferFrom(vault, address(this), amountToAllocate);

        uint256 actualAllocated = _allocateToPosition(data);

        emit AllocateFunds(actualAllocated);
        return actualAllocated;
    }

    /**
     * @inheritdoc IStrategyTemplate
     */
    function deallocateFunds(bytes calldata data) external virtual override onlyVault whenNotPaused returns (uint256) {
        uint256 amountToDeallocate;
        assembly {
            amountToDeallocate := calldataload(data.offset)
        }

        if (amountToDeallocate == 0) return 0;

        uint256 actualDeallocated = _deallocateFromPosition(data);

        BaseStrategyStorage.BaseStrategyStorage storage baseStrategyStorage = BaseStrategyStorage.fetch();
        IERC20(baseStrategyStorage.asset).safeTransfer(baseStrategyStorage.vault, actualDeallocated);

        emit DeallocateFunds(actualDeallocated);
        return actualDeallocated;
    }

    /**
     * @inheritdoc IStrategyTemplate
     */
    function onWithdraw(uint256 assets) external virtual override onlyVault whenNotPaused returns (uint256) {
        // Check maxWithdraw limit
        uint256 maxWithdrawAmount = this.maxWithdraw();
        if (assets > maxWithdrawAmount) revert MaxWithdrawAmountExceeded();

        uint256 actualWithdrawn = _withdrawFromPosition(assets);

        BaseStrategyStorage.BaseStrategyStorage storage baseStrategyStorage = BaseStrategyStorage.fetch();
        IERC20(baseStrategyStorage.asset).safeTransfer(baseStrategyStorage.vault, actualWithdrawn);

        emit StrategyWithdraw(actualWithdrawn);
        return actualWithdrawn;
    }

    /**
     * @inheritdoc IStrategyTemplate
     */
    function asset() external view virtual override returns (address) {
        return BaseStrategyStorage.fetch().asset;
    }

    /**
     * @inheritdoc IStrategyTemplate
     */
    function totalAllocatedValue() external view virtual override whenNotPaused returns (uint256) {
        return _previewPosition();
    }

    /**
     * @inheritdoc IStrategyTemplate
     */
    function maxAllocation() external pure virtual override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @inheritdoc IStrategyTemplate
     */
    function maxWithdraw() external view virtual override returns (uint256) {
        BaseStrategyStorage.BaseStrategyStorage storage baseStrategyStorage = BaseStrategyStorage.fetch();
        uint256 positionValue = _previewPosition();
        return baseStrategyStorage.maxWithdraw > positionValue ? positionValue : baseStrategyStorage.maxWithdraw;
    }

    /**
     * @dev Get the authorized vault address
     * @return The authorized vault address
     */
    function getVault() external view virtual returns (address) {
        return BaseStrategyStorage.fetch().vault;
    }

    /**
     * @dev Set the maximum withdraw amount for the strategy
     * @param maxWithdraw_ The maximum amount that can be withdrawn
     */
    function setMaxWithdraw(uint256 maxWithdraw_) external virtual onlyRole(PeripheryRolesLib.STRATEGY_ADMIN) {
        BaseStrategyStorage.BaseStrategyStorage storage baseStrategyStorage = BaseStrategyStorage.fetch();
        emit MaxWithdrawUpdated(baseStrategyStorage.maxWithdraw, maxWithdraw_);
        baseStrategyStorage.maxWithdraw = maxWithdraw_;
    }

    /**
     * @dev Rescue function to recover tokens (only admin)
     * @dev Cannot rescue the strategy's asset token
     * @param token The token address to rescue
     * @param amount The amount to rescue (0 to rescue all available tokens)
     */
    function rescueToken(address token, uint256 amount) external virtual onlyRole(PeripheryRolesLib.STRATEGY_ADMIN) {
        BaseStrategyStorage.BaseStrategyStorage storage baseStrategyStorage = BaseStrategyStorage.fetch();
        if (token == baseStrategyStorage.asset) revert InvalidAsset();

        uint256 rescueAmount = amount == 0 ? IERC20(token).balanceOf(address(this)) : amount;
        IERC20(token).safeTransfer(msg.sender, rescueAmount);
    }

    /**
     * @notice Pauses the strategy, preventing deposits and withdrawals
     * @dev Only admin can pause the strategy
     */
    function pause() external onlyRole(PeripheryRolesLib.STRATEGY_ADMIN) {
        _pause();
    }

    /**
     * @notice Unpauses the strategy, allowing deposits and withdrawals
     * @dev Only admin can unpause the strategy
     */
    function unpause() external onlyRole(PeripheryRolesLib.STRATEGY_ADMIN) {
        _unpause();
    }
}
