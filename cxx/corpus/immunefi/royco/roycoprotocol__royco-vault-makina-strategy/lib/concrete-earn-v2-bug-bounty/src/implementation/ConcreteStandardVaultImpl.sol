// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

/**
 * @title ConcreteStandardVaultImpl
 * @notice ERC-4626 upgradeable standard vault implementation for the Concrete Earn V2 protocol.
 *         Holds an underlying ERC20 asset and exposes deposit/mint/withdraw/redeem flows.
 *         Integrates with strategy modules to route assets to yield sources.
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
import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {
    ERC4626Upgradeable,
    IERC20,
    IERC4626,
    Math,
    SafeERC20
} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Address} from "@openzeppelin-contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin-contracts/utils/math/SafeCast.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Protocol-facing interfaces
// ─────────────────────────────────────────────────────────────────────────────
import {IConcreteStandardVaultImpl} from "../interface/IConcreteStandardVaultImpl.sol";
import {IStrategyTemplate} from "../interface/IStrategyTemplate.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Internal modules/contracts
// ─────────────────────────────────────────────────────────────────────────────
import {IAllocateModule} from "../module/AllocateModule.sol";
import {UpgradeableVault} from "../common/UpgradeableVault.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Internal libraries
// ─────────────────────────────────────────────────────────────────────────────
import {ConcreteV2ConstantsLib as ConstantsLib} from "../lib/Constants.sol";
import {ConcreteV2ConversionLib as ConversionLib} from "../lib/Conversion.sol";
import {Hooks, HooksLibV1 as HooksLib} from "../lib/Hooks.sol";
import {ConcreteV2RolesLib as RolesLib} from "../lib/Roles.sol";
import {StateInitLib} from "../lib/StateInitLib.sol";
import {StateSetterLib} from "../lib/StateSetterLib.sol";
import {Time} from "../lib/Time.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Storage layout libraries
// ─────────────────────────────────────────────────────────────────────────────
import {
    ConcreteCachedVaultStateStorageLib as CachedVaultStateLib
} from "../lib/storage/ConcreteCachedVaultStateStorageLib.sol";
import {ConcreteStandardVaultImplStorageLib as SVLib} from "../lib/storage/ConcreteStandardVaultImplStorageLib.sol";

contract ConcreteStandardVaultImpl is
    ERC4626Upgradeable,
    UpgradeableVault,
    AccessControlEnumerableUpgradeable,
    IConcreteStandardVaultImpl
{
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCast for uint256;
    using ConversionLib for uint256;

    using HooksLib for Hooks;

    event HooksSet(Hooks hooks);

    /// @dev Modifier to accrue yield before function execution
    modifier withYieldAccrual() {
        _accrueYield();
        _;
    }
    /**
     * @dev Constructor
     * @param factory The address of the factory
     */

    constructor(address factory) UpgradeableVault(factory) {}

    /// @inheritdoc IConcreteStandardVaultImpl
    function allocate(bytes calldata data) public virtual nonReentrant onlyRole(RolesLib.ALLOCATOR) withYieldAccrual {
        // delegatecall allocate module
        bytes memory delegateData = abi.encodeWithSelector(IAllocateModule.allocateFunds.selector, data);
        allocateModule().functionDelegateCall(delegateData);
        require(IERC20(asset()).balanceOf(address(this)) >= _lockedAssets(), InsufficientBalance());
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function accrueYield() external virtual nonReentrant {
        _accrueYield();
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function updateManagementFee(uint16 managementFee_)
        external
        nonReentrant
        onlyRole(RolesLib.VAULT_MANAGER)
        withYieldAccrual
    {
        StateSetterLib.updateManagementFee(managementFee_);
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function updateManagementFeeRecipient(address recipient) external nonReentrant withYieldAccrual {
        require(_msgSender() == Ownable(factory).owner(), InvalidFactoryOwner());

        StateSetterLib.updateManagementFeeRecipient(recipient);
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function updatePerformanceFee(uint16 performanceFee_)
        external
        nonReentrant
        onlyRole(RolesLib.VAULT_MANAGER)
        withYieldAccrual
    {
        StateSetterLib.updatePerformanceFee(performanceFee_);
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function updatePerformanceFeeRecipient(address recipient) external nonReentrant withYieldAccrual {
        require(msg.sender == Ownable(factory).owner(), InvalidFactoryOwner());

        StateSetterLib.updatePerformanceFeeRecipient(recipient);
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function setDepositLimits(uint256 minDepositAmount, uint256 maxDepositAmount)
        external
        nonReentrant
        onlyRole(RolesLib.VAULT_MANAGER)
    {
        StateSetterLib.setDepositLimits(minDepositAmount, maxDepositAmount);
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function setWithdrawLimits(uint256 minWithdrawAmount, uint256 maxWithdrawAmount)
        external
        nonReentrant
        onlyRole(RolesLib.VAULT_MANAGER)
    {
        StateSetterLib.setWithdrawLimits(minWithdrawAmount, maxWithdrawAmount);
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function getFeeConfig()
        external
        view
        override
        returns (
            uint16 currentManagementFee,
            address currentManagementFeeRecipient,
            uint32 currentLastManagementFeeAccrual,
            uint16 currentPerformanceFee,
            address currentPerformanceFeeRecipient
        )
    {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        return (
            $.managementFee,
            $.managementFeeRecipient,
            $.lastManagementFeeAccrual,
            $.performanceFee,
            $.performanceFeeRecipient
        );
    }

    /**
     * @inheritdoc IERC4626
     */
    function deposit(uint256 assets, address receiver)
        public
        virtual
        override(IERC4626, ERC4626Upgradeable)
        nonReentrant
        withYieldAccrual
        returns (uint256)
    {
        require(receiver != address(0), InvalidReceiver());

        Hooks memory h = SVLib.fetch().hooks;
        uint256 totalAssetsBeforeDeposit = cachedTotalAssets();
        // invoke pre-deposit hook if enabled
        if (h.checkIsValid(HooksLib.PRE_DEPOSIT)) {
            h.preDeposit(_msgSender(), assets, receiver, totalAssetsBeforeDeposit);
        }

        // deposit assets
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = assets.calcConvertToShares(totalSupply(), totalAssetsBeforeDeposit, Math.Rounding.Floor, true);

        (uint256 maxDepositAmount, uint256 minDepositAmount) = getDepositLimits();
        require(
            assets + totalAssetsBeforeDeposit <= maxDepositAmount && assets >= minDepositAmount,
            AssetAmountOutOfBounds(msg.sender, assets, minDepositAmount, maxDepositAmount)
        );

        _deposit(_msgSender(), receiver, assets, shares);

        // invoke post-deposit hook if enabled
        if (h.checkIsValid(HooksLib.POST_DEPOSIT)) {
            h.postDeposit(_msgSender(), assets, shares, receiver, cachedTotalAssets());
        }

        return shares;
    }

    /**
     * @inheritdoc IERC4626
     */
    function mint(uint256 shares, address receiver)
        public
        virtual
        override(IERC4626, ERC4626Upgradeable)
        nonReentrant
        withYieldAccrual
        returns (uint256)
    {
        require(receiver != address(0), InvalidReceiver());

        Hooks memory h = SVLib.fetch().hooks;
        uint256 totalAssetsBeforeDeposit = cachedTotalAssets();
        // invoke pre-mint hook if enabled
        if (h.checkIsValid(HooksLib.PRE_MINT)) h.preMint(_msgSender(), shares, receiver, totalAssetsBeforeDeposit);

        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }

        uint256 assets = shares.calcConvertToAssets(totalSupply(), totalAssetsBeforeDeposit, Math.Rounding.Ceil, true);

        (uint256 maxDepositAmount, uint256 minDepositAmount) = getDepositLimits();
        require(
            assets + totalAssetsBeforeDeposit <= maxDepositAmount && assets >= minDepositAmount,
            AssetAmountOutOfBounds(_msgSender(), assets, minDepositAmount, maxDepositAmount)
        );

        _deposit(_msgSender(), receiver, assets, shares);

        // invoke post-mint hook if enabled
        if (h.checkIsValid(HooksLib.POST_MINT)) {
            h.postMint(_msgSender(), assets, shares, receiver, cachedTotalAssets());
        }

        return assets;
    }

    /**
     * @inheritdoc IERC4626
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override(IERC4626, ERC4626Upgradeable)
        nonReentrant
        withYieldAccrual
        returns (uint256)
    {
        require(receiver != address(0), InvalidReceiver());

        Hooks memory h = SVLib.fetch().hooks;
        uint256 totalAssetsBeforeWithdrawal = cachedTotalAssets();

        if (h.checkIsValid(HooksLib.PRE_WITHDRAW)) {
            h.preWithdraw(_msgSender(), assets, receiver, owner, totalAssetsBeforeWithdrawal);
        }
        // Optimistic maxAssets that does not account for the withdrawals from strategies, this is to avoid the need to call _simulateWithdraw().
        // If maxAssets is greater than the actual withdrawable amount, _executeWithdraw() will revert.
        uint256 totalSupply_ = totalSupply();
        uint256 maxAssets =
            balanceOf(owner).calcConvertToAssets(totalSupply_, totalAssetsBeforeWithdrawal, Math.Rounding.Floor, false);

        uint256 shares = assets.calcConvertToShares(totalSupply_, totalAssetsBeforeWithdrawal, Math.Rounding.Ceil, true);
        if (assets > maxAssets || _executeWithdraw(_msgSender(), receiver, owner, assets, shares) < assets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        (uint256 maxWithdrawAmount, uint256 minWithdrawAmount) = getWithdrawLimits();
        require(
            assets <= maxWithdrawAmount && assets >= minWithdrawAmount,
            AssetAmountOutOfBounds(_msgSender(), assets, minWithdrawAmount, maxWithdrawAmount)
        );

        // invoke post-withdraw hook if enabled
        if (h.checkIsValid(HooksLib.POST_WITHDRAW)) {
            h.postWithdraw(_msgSender(), assets, shares, receiver, cachedTotalAssets());
        }

        return shares;
    }

    /**
     * @inheritdoc IERC4626
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override(IERC4626, ERC4626Upgradeable)
        nonReentrant
        withYieldAccrual
        returns (uint256)
    {
        require(receiver != address(0), InvalidReceiver());

        Hooks memory h = SVLib.fetch().hooks;
        uint256 totalAssetsBeforeWithdrawal = cachedTotalAssets();

        // invoke pre-redeem hook if enabled
        if (h.checkIsValid(HooksLib.PRE_REDEEM)) {
            h.preRedeem(_msgSender(), shares, receiver, owner, totalAssetsBeforeWithdrawal);
        }

        // Optimistic maxShares that does not account for the withdrawals from strategies, this is to avoid the need to call _simulateWithdraw().
        // If maxShares is greater than the actual redeemable amount, _executeWithdraw() will revert.
        uint256 maxShares = balanceOf(owner);

        uint256 assets =
            shares.calcConvertToAssets(totalSupply(), totalAssetsBeforeWithdrawal, Math.Rounding.Floor, true);

        if (shares > maxShares || _executeWithdraw(_msgSender(), receiver, owner, assets, shares) < assets) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        (uint256 maxWithdrawAmount, uint256 minWithdrawAmount) = getWithdrawLimits();
        require(
            assets <= maxWithdrawAmount && assets >= minWithdrawAmount,
            AssetAmountOutOfBounds(_msgSender(), assets, minWithdrawAmount, maxWithdrawAmount)
        );

        // invoke post-redeem hook if enabled
        if (h.checkIsValid(HooksLib.POST_REDEEM)) {
            h.postRedeem(_msgSender(), assets, shares, receiver, cachedTotalAssets());
        }

        return assets;
    }

    /**
     * @inheritdoc IConcreteStandardVaultImpl
     */
    function setHooks(Hooks memory hooks) external virtual nonReentrant onlyRole(RolesLib.HOOK_MANAGER) {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        $.hooks = hooks;

        emit HooksSet(hooks);
    }

    /**
     * @notice overwrites the deallocation order from strategies;
     */
    function setDeallocationOrder(address[] calldata order) external virtual nonReentrant onlyRole(RolesLib.ALLOCATOR) {
        StateSetterLib.setDeallocationOrder(order);
    }

    /**
     * @inheritdoc IConcreteStandardVaultImpl
     */
    function addStrategy(address strategy) public virtual nonReentrant onlyRole(RolesLib.STRATEGY_MANAGER) {
        require(IStrategyTemplate(strategy).asset() == asset(), InvalidStrategyAsset());
        StateSetterLib.addStrategy(strategy);
    }

    /**
     * @inheritdoc IConcreteStandardVaultImpl
     */
    function removeStrategy(address strategy) public virtual nonReentrant onlyRole(RolesLib.STRATEGY_MANAGER) {
        StateSetterLib.removeStrategy(strategy);
    }

    /**
     * @inheritdoc IConcreteStandardVaultImpl
     */
    function toggleStrategyStatus(address strategy) public virtual nonReentrant onlyRole(RolesLib.STRATEGY_MANAGER) {
        StateSetterLib.toggleStrategyStatus(strategy);
    }

    /**
     * @notice Returns the deallocation order from strategies.
     */
    function getDeallocationOrder() external view returns (address[] memory order) {
        return SVLib.fetch().deallocationOrder;
    }

    /**
     * @dev See {IERC4626-previewDeposit}.
     */
    function previewDeposit(uint256 assets)
        public
        view
        virtual
        override(IERC4626, ERC4626Upgradeable)
        returns (uint256)
    {
        (uint256 totalAssetsPreview, uint256 totalSupply) = _previewAccrueYieldAndFees();
        return assets.calcConvertToShares(totalSupply, totalAssetsPreview, Math.Rounding.Floor, false);
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewMint(uint256 shares) public view virtual override(IERC4626, ERC4626Upgradeable) returns (uint256) {
        (uint256 totalAssetsPreview, uint256 totalSupply) = _previewAccrueYieldAndFees();

        return shares.calcConvertToAssets(totalSupply, totalAssetsPreview, Math.Rounding.Ceil, false);
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewWithdraw(uint256 assets)
        public
        view
        virtual
        override(IERC4626, ERC4626Upgradeable)
        returns (uint256)
    {
        (uint256 totalAssetsPreview, uint256 totalSupply) = _previewAccrueYieldAndFees();

        return assets.calcConvertToShares(totalSupply, totalAssetsPreview, Math.Rounding.Ceil, false);
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewRedeem(uint256 shares)
        public
        view
        virtual
        override(IERC4626, ERC4626Upgradeable)
        returns (uint256)
    {
        (uint256 totalAssetsPreview, uint256 totalSupply) = _previewAccrueYieldAndFees();

        return shares.calcConvertToAssets(totalSupply, totalAssetsPreview, Math.Rounding.Floor, false);
    }

    /**
     * @inheritdoc IConcreteStandardVaultImpl
     */
    function previewAccrueYield() public view virtual returns (uint256, uint256) {
        return _previewAccrueYieldAndFees();
    }

    /**
     * @inheritdoc IERC4626
     */
    function totalAssets()
        public
        view
        virtual
        override(IERC4626, ERC4626Upgradeable)
        returns (uint256 totalAssetsWithYield)
    {
        (totalAssetsWithYield,) = _previewAccrueYieldAndFees();
    }

    /**
     * @inheritdoc IERC4626
     */
    function maxRedeem(address owner) public view virtual override(IERC4626, ERC4626Upgradeable) returns (uint256) {
        (uint256 maxAssets, uint256 expectedTotalAssets, uint256 expectedTotalSupply) = _maxWithdraw(owner);

        return maxAssets.calcConvertToShares(expectedTotalSupply, expectedTotalAssets, Math.Rounding.Floor, false);
    }

    /**
     * @inheritdoc IERC4626
     */
    function maxWithdraw(address owner)
        public
        view
        virtual
        override(IERC4626, ERC4626Upgradeable)
        returns (uint256 maxAssets)
    {
        (maxAssets,,) = _maxWithdraw(owner);
    }

    /**
     * @inheritdoc IConcreteStandardVaultImpl
     */
    function getStrategyData(address strategy) public view returns (StrategyData memory) {
        return SVLib.fetch().strategyData[strategy];
    }

    /**
     * @inheritdoc IConcreteStandardVaultImpl
     */
    function getStrategies() public view returns (address[] memory) {
        return SVLib.fetch().strategies.values();
    }

    /**
     * @inheritdoc IConcreteStandardVaultImpl
     */
    function allocateModule() public view returns (address) {
        return SVLib.fetch().allocateModule;
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function getDepositLimits() public view returns (uint256, uint256) {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();
        return ($.maxDepositAmount, $.minDepositAmount);
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function getWithdrawLimits() public view returns (uint256, uint256) {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();
        return ($.maxWithdrawAmount, $.minWithdrawAmount);
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function managementFee() public view returns (address, uint16, uint32) {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();
        return ($.managementFeeRecipient, $.managementFee, $.lastManagementFeeAccrual);
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function performanceFee() public view returns (address, uint16) {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();
        return ($.performanceFeeRecipient, $.performanceFee);
    }

    /// @inheritdoc IConcreteStandardVaultImpl
    function getTotalAllocated() public view returns (uint256 totalAllocated) {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        address[] memory strategies = $.strategies.values();

        for (uint256 i = 0; i < strategies.length; i++) {
            totalAllocated += $.strategyData[strategies[i]].allocated;
        }
    }

    function cachedTotalAssets() public view returns (uint256) {
        return CachedVaultStateLib.fetch().cachedTotalAssets;
    }

    /**
     * @dev Initialization function that will be called when a proxy vault is deployed through `ConcreteFactory`.
     */
    function _initialize(
        uint64,
        /*initialVersion*/
        address,
        /*owner*/
        bytes memory data
    )
        internal
        virtual
        override
    {
        (
            address allocateModuleAddr,
            address asset,
            address initialVaultManager,
            string memory name,
            string memory symbol
        ) = abi.decode(data, (address, address, address, string, string));

        require(allocateModuleAddr != address(0), InvalidAllocateModule());
        require(asset != address(0), InvalidAsset());
        require(initialVaultManager != address(0), InvalidInitialVaultManager());

        require(bytes(name).length > 0, InvalidName());
        require(bytes(symbol).length > 0, InvalidSymbol());

        __ERC20_init_unchained(name, symbol);
        __ERC4626_init_unchained(IERC20(asset));
        __AccessControlEnumerable_init_unchained();

        StateInitLib.stateInitStandardVaultImpl(allocateModuleAddr, initialVaultManager, _msgSender());
    }

    /**
     * @dev Upgrade function that will be called when a proxy vault upgrades to this implementation
     */
    function _upgrade(
        uint64,
        /* oldVersion */
        uint64,
        /* newVersion */
        bytes calldata /* data */
    )
        internal
        virtual
        override
    {
        revert();
    }

    /**
     * @dev Internal function that executes the yield accrual operation across all active strategies.
     * @dev This function iterates through all strategies managed by the vault, calculates
     *      yield generated and losses incurred since the last yield accrual, and updates the vault's
     *      internal accounting accordingly.
     * @dev This function does not trigger actual fund movements, it only updates accounting
     *      to reflect the current state of strategy allocations.
     */
    function _accrueYield() internal virtual returns (uint256) {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        uint256 totalPositiveYield;
        uint256 totalNegativeYield;
        {
            address[] memory strategies = $.strategies.values();
            uint256 strategiesCounter = strategies.length;

            for (uint256 i; i < strategiesCounter; ++i) {
                (uint256 positiveYield, uint256 loss, uint256 strategyTotalAllocatedValue) =
                    _previewStrategyYield(strategies[i]);

                // update the strategy allocated amount only if there is yield or loss, otherwise it's the same amount as when we called `allocate()`.
                // we do update the lastTotalAssets after netting the yield and loss
                if (positiveYield != 0 || loss != 0) {
                    $.strategyData[strategies[i]].allocated = strategyTotalAllocatedValue.toUint120();

                    totalPositiveYield += positiveYield;
                    totalNegativeYield += loss;

                    emit StrategyYieldAccrued(strategies[i], strategyTotalAllocatedValue, positiveYield, loss);
                }
            }
        }

        CachedVaultStateLib.ConcreteCachedVaultStateStorage storage $cached = CachedVaultStateLib.fetch();

        uint256 totalAssetsCached = $cached.cachedTotalAssets + totalPositiveYield - totalNegativeYield;
        // update the lastTotalAssets
        $cached.cachedTotalAssets = totalAssetsCached;

        // Accrue management fees after accruing yield to calculate fee asset amount on total vault AUM
        accrueManagementFee(totalAssetsCached);

        // Accrue performance fees on net yield amount
        accruePerformanceFee(totalAssetsCached, totalPositiveYield, totalNegativeYield);

        emit YieldAccrued(totalPositiveYield, totalNegativeYield);

        return totalAssetsCached;
    }

    /**
     * @dev Internal function that handles withdrawal operations, including strategy deallocation when needed.
     * @dev This function implements the core withdrawal logic for the vault, automatically managing
     *      fund retrieval from both idle vault balance and allocated strategies to fulfill withdrawal requests.
     * @dev Withdrawal Process:
     *      1. First attempts to use idle funds (assets sitting in the vault contract)
     *      2. If idle funds are insufficient, iterates through active strategies to deallocate funds
     *      3. For each strategy, respects the strategy's maxWithdraw() limit
     *      4. Updates strategy allocation accounting after successful deallocations
     *      5. Delegates to parent contract for final ERC4626 withdrawal execution
     * @dev Requirements:
     *      - Combined idle funds and strategy liquidity must be sufficient for withdrawal amount
     *      - All deallocated strategies must be in Active status
     *      - Strategy onWithdraw() calls must succeed and return expected amounts
     * @param caller The address that initiated the withdrawal (for access control)
     * @param receiver The address that will receive the withdrawn assets
     * @param owner The address whose shares are being burned for the withdrawal
     * @param assets The amount of assets to withdraw from the vault
     * @param shares The amount of shares to burn in exchange for the assets
     */
    function _executeWithdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        returns (uint256)
    {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        uint256 floatingFunds = IERC20(asset()).balanceOf(address(this));
        uint256 lockedAssets = _lockedAssets();
        uint256 totalWithdrawableAmount = floatingFunds >= lockedAssets ? floatingFunds - lockedAssets : 0;
        if (totalWithdrawableAmount < assets) {
            address[] memory deallocationOrder = $.deallocationOrder;
            uint256 strategiesCounter = deallocationOrder.length;

            uint256 desiredAssets;
            for (uint256 i; i < strategiesCounter; ++i) {
                if (
                    ($.strategyData[deallocationOrder[i]].status != IConcreteStandardVaultImpl.StrategyStatus.Active)
                        || !$.strategies.contains(deallocationOrder[i])
                ) continue;

                unchecked {
                    desiredAssets = assets - totalWithdrawableAmount;
                }

                uint256 withdrawableAmountFromStrategy = IStrategyTemplate(deallocationOrder[i]).maxWithdraw();
                uint256 withdrawAmount =
                    (withdrawableAmountFromStrategy >= desiredAssets) ? desiredAssets : withdrawableAmountFromStrategy;

                if (withdrawAmount > 0) {
                    // Actually withdraw from the strategy
                    uint256 actualWithdrawn = IStrategyTemplate(deallocationOrder[i]).onWithdraw(withdrawAmount);

                    // Update strategy allocated amount
                    $.strategyData[deallocationOrder[i]].allocated -= actualWithdrawn.toUint120();

                    totalWithdrawableAmount += actualWithdrawn;
                }

                if (totalWithdrawableAmount >= assets) break;
            }
        }

        _withdraw(caller, receiver, owner, assets, shares);

        return totalWithdrawableAmount;
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // If asset() is ERC-777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.

        CachedVaultStateLib.fetch().cachedTotalAssets -= assets;
        _burn(owner, shares);
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        // If asset() is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);
        CachedVaultStateLib.fetch().cachedTotalAssets += assets;
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Accrue management fees by minting shares to the fee recipient.
     * @param totalAssetsAmount The total assets in the vault to calculate fee on
     */
    function accrueManagementFee(uint256 totalAssetsAmount) internal {
        (uint256 feeShares, uint256 feeAmount) = previewManagementFee(totalAssetsAmount);

        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        // Update last accrual timestamp
        $.lastManagementFeeAccrual = Time.timestamp();

        // Mint shares to management fee recipient
        address managementFeeRecipient = $.managementFeeRecipient;
        if (feeShares != 0 && managementFeeRecipient != address(0)) {
            // Mint shares to management fee recipient
            _mint(managementFeeRecipient, feeShares);

            emit ManagementFeeAccrued(managementFeeRecipient, feeShares, feeAmount);
        }
    }

    /**
     * @dev Accrue performance fees by minting shares to the fee recipient.
     * @param totalAssetsAmount The total assets in the vault to calculate fee on
     * @param positiveYield The total positive yield generated by all strategies
     * @param loss The total losses incurred by all strategies
     */
    function accruePerformanceFee(uint256 totalAssetsAmount, uint256 positiveYield, uint256 loss) internal {
        (uint256 performanceFeeShares, uint256 feeAmount) =
            previewPerformanceFee(totalAssetsAmount, positiveYield, loss, totalSupply());

        if (performanceFeeShares == 0) return;

        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        // Mint shares to performance fee recipient
        address performanceFeeRecipient = $.performanceFeeRecipient;
        if (performanceFeeRecipient != address(0)) {
            _mint(performanceFeeRecipient, performanceFeeShares);
            emit PerformanceFeeAccrued(performanceFeeRecipient, performanceFeeShares, feeAmount);
        }
    }

    /**
     * @dev Simulates the yield accrual operation across all strategies including fees.
     * @return totalAssets The projected total assets after yield accrual (current + yield - losses)
     * @return totalSupply The projected total supply after yield accrual (current + management fee shares + performance fee shares)
     */
    function _previewAccrueYieldAndFees() internal view virtual returns (uint256, uint256) {
        (uint256 totalPositiveYield, uint256 totalNegativeYield) = _previewYieldNoFees();

        uint256 totalSupplyCached = totalSupply();
        uint256 totalAssetsCached = cachedTotalAssets() + totalPositiveYield - totalNegativeYield;

        (uint256 managementFeeShares,) = previewManagementFee(totalAssetsCached);
        totalSupplyCached += managementFeeShares;

        (uint256 performanceFeeShares,) =
            previewPerformanceFee(totalAssetsCached, totalPositiveYield, totalNegativeYield, totalSupplyCached);
        totalSupplyCached += performanceFeeShares;

        return (totalAssetsCached, totalSupplyCached);
    }

    /**
     * @dev Calculates total positive and negative yield across all strategies.
     * @return totalPositiveYield The sum of all positive yields from strategies
     * @return totalNegativeYield The sum of all losses from strategies
     */
    function _previewYieldNoFees()
        internal
        view
        virtual
        returns (uint256 totalPositiveYield, uint256 totalNegativeYield)
    {
        address[] memory strategies = SVLib.fetch().strategies.values();
        uint256 strategiesCounter = strategies.length;

        for (uint256 i; i < strategiesCounter; ++i) {
            (uint256 positiveYield, uint256 loss,) = _previewStrategyYield(strategies[i]);

            if (positiveYield != 0 || loss != 0) {
                totalPositiveYield += positiveYield;
                totalNegativeYield += loss;
            }
        }
    }

    /**
     * @dev Accrues yield and accounts for losses for a single strategy.
     * @dev This function queries the current total allocated value from a strategy,
     *      compares it against the previously recorded allocated amount, and calculates
     *      the yield generated or loss incurred since the last yield accrual.
     * @param strategy The address of the strategy contract to accrue yield from.
     * @return yield The amount of positive yield generated by the strategy since last accrual.
     * @return loss The amount of loss incurred by the strategy since last accrual.
     */
    function _previewStrategyYield(address strategy) internal view returns (uint256, uint256, uint256) {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        uint120 strategyAllocatedAmount = $.strategyData[strategy].allocated;

        if ($.strategyData[strategy].status != IConcreteStandardVaultImpl.StrategyStatus.Active) {
            return (0, 0, 0);
        }

        uint256 currentTotalAllocatedValue = IStrategyTemplate(strategy).totalAllocatedValue();
        currentTotalAllocatedValue =
            (currentTotalAllocatedValue >= type(uint120).max) ? type(uint120).max : currentTotalAllocatedValue;

        uint256 yield;
        uint256 loss;
        if (currentTotalAllocatedValue == strategyAllocatedAmount) {
            return (yield, loss, currentTotalAllocatedValue);
        } else if (currentTotalAllocatedValue > strategyAllocatedAmount) {
            yield = currentTotalAllocatedValue - strategyAllocatedAmount;
        } else {
            loss = strategyAllocatedAmount - currentTotalAllocatedValue;
        }

        return (yield, loss, currentTotalAllocatedValue);
    }

    /**
     * @dev Preview management fee accrual.
     * @param _lastTotalAssets The total assets deposited in the vault to calculate fee on
     * @return feeShares The number of shares to mint as management fee
     * @return feeAmount The asset value of the management fee
     */
    function previewManagementFee(uint256 _lastTotalAssets)
        internal
        view
        returns (uint256 feeShares, uint256 feeAmount)
    {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        if ($.managementFee == 0) return (0, 0);

        uint32 currentTime = Time.timestamp();
        uint32 lastAccrual = $.lastManagementFeeAccrual;

        if (currentTime == lastAccrual) return (0, 0);

        uint256 timeElapsed = currentTime - lastAccrual;
        // management fee is calculated on total vault AUM(after yield accrual)
        uint256 annualFeeAmount = (_lastTotalAssets * $.managementFee) / ConstantsLib.BASIS_POINTS_DENOMINATOR;
        feeAmount = (annualFeeAmount * timeElapsed) / (365 days);

        if (feeAmount == 0) return (0, 0);

        // sanity check - clamp the fee amount to the last total assets
        if (feeAmount > _lastTotalAssets) {
            feeAmount = _lastTotalAssets;
        }

        // convert fee amount to shares using total assets net of the fee to prevent dilution. of the fee amount
        feeShares =
            feeAmount.calcConvertToShares(totalSupply(), _lastTotalAssets - feeAmount, Math.Rounding.Floor, false);

        return (feeShares, feeAmount);
    }

    /**
     * @dev Preview performance fee accrual.
     * @param totalAssetsAmount The total assets in the vault to calculate fee on
     * @param positiveYield The total positive yield generated by all strategies
     * @param loss The total losses incurred by all strategies
     * @param totalSupply The current total supply of vault shares
     * @return shares The number of shares to mint as performance fee
     * @return feeAmount The asset value of the performance fee
     */
    function previewPerformanceFee(uint256 totalAssetsAmount, uint256 positiveYield, uint256 loss, uint256 totalSupply)
        internal
        view
        returns (uint256, uint256)
    {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        if ($.performanceFee == 0 || (loss >= positiveYield)) return (0, 0);

        uint256 netPositiveYield = positiveYield - loss;
        uint256 feeAmount = Math.mulDiv(netPositiveYield, $.performanceFee, ConstantsLib.BASIS_POINTS_DENOMINATOR);

        if (feeAmount == 0) return (0, 0);

        uint256 feeShares =
            feeAmount.calcConvertToShares(totalSupply, totalAssetsAmount - feeAmount, Math.Rounding.Floor, false);

        return (feeShares, feeAmount);
    }

    /**
     * @dev Internal function to calculate the maximum amount of assets that can be withdrawn by an owner.
     * @dev The calculation considers:
     *      - Owner's current share balance converted to equivalent assets
     *      - Current vault liquidity (idle assets + withdrawable amounts from strategies)
     *      - Strategy withdrawal limitations and availability
     * @param owner The address of the account for which to calculate maximum withdrawal.
     * @return The maximum amount of assets that can actually be withdrawn by the owner,
     *         considering both ownership rights and liquidity constraints.
     * @return totalAssets The total amount of assets in the vault after previewing the yield accrual
     */
    function _maxWithdraw(address owner) internal view virtual returns (uint256, uint256, uint256) {
        uint256 ownerShares = balanceOf(owner);
        (uint256 totalAssetsPreview, uint256 totalSupplyPreview) = _previewAccrueYieldAndFees();

        uint256 maxAssets =
            ownerShares.calcConvertToAssets(totalSupplyPreview, totalAssetsPreview, Math.Rounding.Floor, false);

        return (_simulateWithdraw(maxAssets), totalAssetsPreview, totalSupplyPreview);
    }

    /// @dev Simulate withdrawing an amount of assets from the vault.
    /// @param requestedAssets Amount of assets to withdraw.
    /// @return Amount of assets filled.
    function _simulateWithdraw(uint256 requestedAssets) internal view virtual returns (uint256) {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        uint256 totalWithdrawableAmount = IERC20(asset()).balanceOf(address(this));
        if (totalWithdrawableAmount < requestedAssets) {
            address[] memory deallocationOrder = $.deallocationOrder;
            uint256 strategiesCounter = deallocationOrder.length;

            for (uint256 i; i < strategiesCounter; ++i) {
                if (
                    ($.strategyData[deallocationOrder[i]].status != IConcreteStandardVaultImpl.StrategyStatus.Active)
                        || !$.strategies.contains(deallocationOrder[i])
                ) continue;

                uint256 desiredAssets;
                unchecked {
                    desiredAssets = requestedAssets - totalWithdrawableAmount;
                }

                uint256 withdrawableAmountFromStrategy = IStrategyTemplate(deallocationOrder[i]).maxWithdraw();
                uint256 withdrawAmount =
                    (withdrawableAmountFromStrategy >= desiredAssets) ? desiredAssets : withdrawableAmountFromStrategy;

                totalWithdrawableAmount += withdrawAmount;

                if (totalWithdrawableAmount >= requestedAssets) break;
            }
        } else {
            totalWithdrawableAmount = requestedAssets;
        }

        return totalWithdrawableAmount;
    }

    /**
     * @dev Internal function used only by the public convertToShares() function.
     * @dev This function returns share amounts NOT inclusive of management or performance fees,
     *      as required by the ERC4626 specification. The convertToShares() function should return
     *      the theoretical share amount for a given asset amount without considering fee deductions.
     * @param assets The amount of assets to convert to shares
     * @param rounding The rounding direction for the conversion
     * @return The equivalent amount of shares, NOT inclusive of fees
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual override returns (uint256) {
        (uint256 totalPositiveYield, uint256 totalNegativeYield) = _previewYieldNoFees();
        return assets.calcConvertToShares(
            totalSupply(), cachedTotalAssets() + totalPositiveYield - totalNegativeYield, rounding, false
        );
    }

    /**
     * @dev Internal function used only by the public convertToAssets() function.
     * @dev This function returns asset amounts NOT inclusive of management or performance fees,
     *      as required by the ERC4626 specification. The convertToAssets() function should return
     *      the theoretical asset amount for a given share amount without considering fee deductions.
     * @param shares The amount of shares to convert to assets
     * @param rounding The rounding direction for the conversion
     * @return The equivalent amount of assets, NOT inclusive of fees
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256) {
        (uint256 totalPositiveYield, uint256 totalNegativeYield) = _previewYieldNoFees();
        return shares.calcConvertToAssets(
            totalSupply(), cachedTotalAssets() + totalPositiveYield - totalNegativeYield, rounding, false
        );
    }

    function _lockedAssets() internal view virtual returns (uint256) {
        return 0;
    }
}
