// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

/**
 * @title ConcreteAsyncVaultImpl
 * @notice ERC-4626-compatible, upgradeable async vault implementation that inherits the standard vault
 *         implementation and adds delayed/batched settlement flows for integrations where
 *         strategies have liquidity latency or epoch-based processing.
 *
 * @author Blueprint Finance
 * @custom:protocol Concrete Earn V2
 * @custom:oz-upgrades Use OZ Upgradeable patterns and eip7201 storage layout
 * @custom:source on request
 * @custom:audits on request
 * @custom:license AGPL-3.0
 */

// ─────────────────────────────────────────────────────────────────────────────
// External dependencies
// ─────────────────────────────────────────────────────────────────────────────
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin-contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Protocol-facing interfaces
// ─────────────────────────────────────────────────────────────────────────────
import {IConcreteAsyncVaultImpl} from "../interface/IConcreteAsyncVaultImpl.sol";
import {IConcreteStandardVaultImpl} from "../interface/IConcreteStandardVaultImpl.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Internal contracts
// ─────────────────────────────────────────────────────────────────────────────
import {ConcreteStandardVaultImpl} from "./ConcreteStandardVaultImpl.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Internal libraries
// ─────────────────────────────────────────────────────────────────────────────
import {AsyncVaultHelperLib} from "../lib/AsyncVaultHelperLib.sol";
import {ConcreteV2ConversionLib as ConversionLib} from "../lib/Conversion.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../src/lib/Roles.sol";
import {StateInitLib} from "../lib/StateInitLib.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Storage layout libraries
// ─────────────────────────────────────────────────────────────────────────────
import {ConcreteAsyncVaultImplStorageLib} from "../lib/storage/ConcreteAsyncVaultImplStorageLib.sol";

contract ConcreteAsyncVaultImpl is ConcreteStandardVaultImpl, IConcreteAsyncVaultImpl {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    constructor(address factory) ConcreteStandardVaultImpl(factory) {}

    /**
     * @dev Override _initialize to set up async vault specific state
     */
    function _initialize(uint64 initialVersion, address owner, bytes memory data) internal virtual override {
        super._initialize(initialVersion, owner, data);

        address initialVaultManager;
        assembly {
            initialVaultManager := mload(add(data, 0x60))
        }
        __ConcreteAsyncVaultImpl_init(initialVaultManager);
    }

    /**
     * @notice Initializes the WithdrawalQueueModule
     * @dev Sets the initial epoch ID to 1 and emits initialization event
     */
    function __ConcreteAsyncVaultImpl_init(address initialVaultManager) internal onlyInitializing {
        StateInitLib.stateInitAsyncVaultImpl(initialVaultManager, _msgSender());
    }

    /// @inheritdoc IConcreteAsyncVaultImpl
    function toggleQueueActive() external virtual onlyRole(RolesLib.VAULT_MANAGER) {
        ConcreteAsyncVaultImplStorageLib.ConcreteAsyncVaultImplStorage storage $ =
            ConcreteAsyncVaultImplStorageLib.fetch();

        bool newQueueActiveState = !$.isQueueActive;
        $.isQueueActive = newQueueActiveState;

        emit QueueActiveToggled(newQueueActiveState);
    }

    /// @inheritdoc IConcreteAsyncVaultImpl
    function cancelRequest(uint256 epochID) external virtual {
        AsyncVaultHelperLib.cancelRequest(_msgSender(), epochID);
    }

    /// @inheritdoc IConcreteAsyncVaultImpl
    function cancelRequest(address user, uint256 epochID) external virtual onlyRole(RolesLib.WITHDRAWAL_MANAGER) {
        require(user != address(0), ZeroAddress());
        AsyncVaultHelperLib.cancelRequest(user, epochID);
    }

    function closeEpoch() external virtual onlyRole(RolesLib.WITHDRAWAL_MANAGER) {
        AsyncVaultHelperLib.closeEpoch();
    }

    /// @inheritdoc IConcreteAsyncVaultImpl
    function processEpoch() external virtual withYieldAccrual nonReentrant onlyRole(RolesLib.WITHDRAWAL_MANAGER) {
        // calculate share price without accruing yield or taking fees.
        uint8 decimals = decimals();
        AsyncVaultHelperLib.processEpoch(
            //sharePrice
            ConversionLib.calcConvertToAssets(
                10 ** decimals, totalSupply(), cachedTotalAssets(), Math.Rounding.Floor, false
            ),
            //availableAssets
            IERC20(asset()).balanceOf(address(this)),
            // decimals to avoid repeated internal function invocations
            decimals
        );
    }

    // External view functions

    /// @inheritdoc IConcreteAsyncVaultImpl
    function getUserEpochRequestInAssets(address user, uint256 epochID) external view virtual returns (uint256 assets) {
        ConcreteAsyncVaultImplStorageLib.ConcreteAsyncVaultImplStorage storage $ =
            ConcreteAsyncVaultImplStorageLib.fetch();

        assets = AsyncVaultHelperLib.getUserEpochRequestInAssets(
            user, epochID, $.latestEpochID, getEpochPricePerShare(epochID), decimals()
        );
    }

    // Public functions
    /// @inheritdoc IConcreteAsyncVaultImpl

    function claimWithdrawal(uint256[] calldata epochIDs) external virtual {
        require(epochIDs.length > 0, EmptyEpochIDs());
        AsyncVaultHelperLib.claimWithdrawal(asset(), _msgSender(), epochIDs, decimals());
    }

    /// @inheritdoc IConcreteAsyncVaultImpl
    function claimWithdrawal(address user, uint256[] calldata epochIDs)
        external
        virtual
        onlyRole(RolesLib.WITHDRAWAL_MANAGER)
    {
        require(user != address(0), ZeroAddress());
        require(epochIDs.length > 0, EmptyEpochIDs());
        AsyncVaultHelperLib.claimWithdrawal(asset(), user, epochIDs, decimals());
    }

    function claimUsersBatch(address[] calldata users, uint256 epochID)
        external
        virtual
        onlyRole(RolesLib.WITHDRAWAL_MANAGER)
    {
        require(users.length > 0, EmptyUsers());
        AsyncVaultHelperLib.claimUsersBatch(asset(), users, epochID, decimals());
    }

    /**
     * @notice Internal function to move a deposit request to the next deposit epoch
     * @dev Validates inputs, determines amount to move, updates storage for both epochs.
     * @param user The user whose request to move
     */
    function moveRequestToNextEpoch(address user) external onlyRole(RolesLib.WITHDRAWAL_MANAGER) {
        require(user != address(0), ZeroAddress());
        AsyncVaultHelperLib.moveRequestToNextEpoch(user);
    }

    /// @inheritdoc IConcreteAsyncVaultImpl
    function getUserEpochRequest(address user, uint256 epochID) external view virtual returns (uint256 shares) {
        return ConcreteAsyncVaultImplStorageLib.fetch().userEpochRequests[user][epochID];
    }

    /// @inheritdoc IConcreteAsyncVaultImpl
    function latestEpochID() external view virtual returns (uint256) {
        return ConcreteAsyncVaultImplStorageLib.fetch().latestEpochID;
    }

    /// @inheritdoc IConcreteAsyncVaultImpl
    function pastEpochsUnclaimedAssets() external view virtual returns (uint256) {
        return ConcreteAsyncVaultImplStorageLib.fetch().pastEpochsUnclaimedAssets;
    }

    /// @inheritdoc IConcreteAsyncVaultImpl
    function totalRequestedSharesPerEpoch(uint256 epochID) external view virtual returns (uint256) {
        return ConcreteAsyncVaultImplStorageLib.fetch().totalRequestedSharesPerEpoch[epochID];
    }

    /// @inheritdoc IConcreteAsyncVaultImpl
    function totalRequestedSharesForCurrentEpochs() external view virtual returns (uint256, uint256, uint256) {
        return AsyncVaultHelperLib.totalRequestedSharesForCurrentEpochs();
    }

    /// @inheritdoc IConcreteAsyncVaultImpl
    function getEpochPricePerShare(uint256 epochID) public view virtual returns (uint256) {
        uint256 epochPricePlusOne = ConcreteAsyncVaultImplStorageLib.fetch().epochPricePerSharePlusOne[epochID];
        if (epochPricePlusOne == 0) return 0;
        return epochPricePlusOne - 1;
    }

    function getEpochState(uint256 epochID) external view virtual returns (EpochState) {
        return AsyncVaultHelperLib.getEpochState(epochID);
    }

    // Internal functions
    /**
     * @dev Override _executeWithdraw to implement async withdrawal pattern
     * @dev This is called by parent's withdraw() and redeem() after harvest and validation
     * @dev Instead of immediately transferring assets, we queue the request for epoch processing
     */
    function _executeWithdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
        returns (uint256)
    {
        require(shares > 0, ZeroShares());

        ConcreteAsyncVaultImplStorageLib.ConcreteAsyncVaultImplStorage storage $ =
            ConcreteAsyncVaultImplStorageLib.fetch();

        if ($.isQueueActive) {
            if (caller != owner) {
                _spendAllowance(owner, caller, shares);
            }
            // Transfer shares from owner to vault for holding until epoch processing
            _transfer(owner, address(this), shares);

            // Add request to current epoch
            uint256 currentEpochID = $.latestEpochID;
            $.userEpochRequests[receiver][currentEpochID] += shares;
            $.totalRequestedSharesPerEpoch[currentEpochID] += shares;

            emit QueuedWithdrawal(caller, receiver, owner, assets, shares, currentEpochID);

            // Return assets to satisfy parent's validation that withdrawal was successful
            return assets;
        } else {
            return super._executeWithdraw(caller, receiver, owner, assets, shares);
        }
    }

    /// @inheritdoc IConcreteAsyncVaultImpl
    function isQueueActive() external view virtual returns (bool) {
        return ConcreteAsyncVaultImplStorageLib.fetch().isQueueActive;
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function allocate(bytes calldata data)
        public
        virtual
        override(ConcreteStandardVaultImpl, IConcreteStandardVaultImpl)
    {
        super.allocate(data);
        require(
            IERC20(asset()).balanceOf(address(this))
                >= ConcreteAsyncVaultImplStorageLib.fetch().pastEpochsUnclaimedAssets,
            InsufficientBalance()
        );
    }

    function _lockedAssets() internal view override returns (uint256) {
        return ConcreteAsyncVaultImplStorageLib.fetch().pastEpochsUnclaimedAssets;
    }
}
