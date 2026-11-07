// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {LibString} from "@solady/utils/LibString.sol";

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";

import {ICreditFactory} from "../interfaces/factories/ICreditFactory.sol";
import {IFactory} from "../interfaces/factories/IFactory.sol";
import {IInterestRateModelFactory} from "../interfaces/factories/IInterestRateModelFactory.sol";
import {ILossPolicyFactory} from "../interfaces/factories/ILossPolicyFactory.sol";
import {IMarketFactory} from "../interfaces/factories/IMarketFactory.sol";
import {IPoolFactory} from "../interfaces/factories/IPoolFactory.sol";
import {IPriceOracleFactory} from "../interfaces/factories/IPriceOracleFactory.sol";
import {IRateKeeperFactory} from "../interfaces/factories/IRateKeeperFactory.sol";

import {IACL} from "../interfaces/IACL.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IBytecodeRepository} from "../interfaces/IBytecodeRepository.sol";
import {IContractsRegister} from "../interfaces/IContractsRegister.sol";
import {IGovernor} from "../interfaces/IGovernor.sol";
import {IMarketConfigurator} from "../interfaces/IMarketConfigurator.sol";
import {Call, DeployParams, DeployResult, MarketFactories} from "../interfaces/Types.sol";

import {
    AP_ACL,
    AP_CONTRACTS_REGISTER,
    AP_CREDIT_FACTORY,
    AP_GOVERNOR,
    AP_INTEREST_RATE_MODEL_FACTORY,
    AP_LOSS_POLICY_FACTORY,
    AP_MARKET_CONFIGURATOR,
    AP_POOL_FACTORY,
    AP_PRICE_ORACLE_FACTORY,
    AP_RATE_KEEPER_FACTORY,
    AP_TREASURY,
    AP_TREASURY_SPLITTER,
    NO_VERSION_CONTROL,
    ROLE_PAUSABLE_ADMIN,
    ROLE_UNPAUSABLE_ADMIN
} from "../libraries/ContractLiterals.sol";
import {Domain} from "../libraries/Domain.sol";

import {DeployerTrait} from "../traits/DeployerTrait.sol";

/// @title Market configurator
/// @notice Allows risk curator to deploy and configure market and credit suites
contract MarketConfigurator is DeployerTrait, IMarketConfigurator {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using LibString for string;
    using LibString for bytes32;
    using SafeERC20 for IERC20;

    // --------------- //
    // STATE VARIABLES //
    // --------------- //

    /// @notice Admin address
    address public immutable override admin;

    /// @notice Emergency admin address
    address public override emergencyAdmin;

    /// @dev Risk curator name as small string
    bytes32 internal immutable _curatorName;

    /// @notice ACL contract address
    address public immutable override acl;

    /// @notice Contracts register contract address
    address public immutable override contractsRegister;

    /// @notice Treasury address
    address public immutable override treasury;

    /// @dev Mapping from `domain` to set of periphery contracts
    mapping(bytes32 domain => EnumerableSet.AddressSet) internal _peripheryContracts;

    /// @dev Mapping from `pool` to market factories
    mapping(address pool => MarketFactories) internal _marketFactories;

    /// @dev Mapping from `creditManager` to credit factory
    mapping(address creditManager => address) internal _creditFactories;

    /// @dev Mapping from `target` to factory authorized to configure it
    mapping(address target => address) internal _authorizedFactories;

    /// @dev Mapping from `factory` and market/credit `suite` to set of contracts in this suite
    ///      that factory is authorized to configure
    mapping(address factory => mapping(address suite => EnumerableSet.AddressSet)) internal _factoryTargets;

    // --------- //
    // MODIFIERS //
    // --------- //

    /// @dev Reverts if caller is not the contract itself
    modifier onlySelf() {
        _ensureCallerIsSelf();
        _;
    }

    /// @dev Reverts if caller is not the admin
    modifier onlyAdmin() {
        _ensureCallerIsAdmin();
        _;
    }

    /// @dev Reverts if caller is not the emergency admin
    modifier onlyEmergencyAdmin() {
        _ensureCallerIsEmergencyAdmin();
        _;
    }

    /// @dev Reverts if `pool` is not registered
    modifier onlyRegisteredMarket(address pool) {
        _ensureRegisteredMarket(pool);
        _;
    }

    /// @dev Reverts if `creditManager` is not registered
    modifier onlyRegisteredCreditSuite(address creditManager) {
        _ensureRegisteredCreditSuite(creditManager);
        _;
    }

    // ----------- //
    // CONSTRUCTOR //
    // ----------- //

    /// @notice Constructor
    /// @param addressProvider_ Address provider contract address
    /// @param admin_ Address to set as market configurator's admin or governor's owner, depending on `deployGovernor_`
    /// @param emergencyAdmin_ Address to set as emergency admin
    /// @param adminFeeTreasury_ Address to set as the second admin of the fee splitter, with the first one being the
    ///        DAO treasury. If `address(0)`, the splitter is not deployed and all fees will be sent to the treasury.
    /// @param curatorName_ Risk curator name
    /// @param deployGovernor_ If true, a governor contract is deployed and set as market configurator's admin.
    ///        `admin_` is set as its owner, queue and execution admin, while `emergencyAdmin_` is set as veto admin.
    ///        Otherwise, `admin_` is set as the admin of the market configurator.
    /// @dev Market configurator is granted pausable and unpausable admin roles in ACL
    constructor(
        address addressProvider_,
        address admin_,
        address emergencyAdmin_,
        address adminFeeTreasury_,
        string memory curatorName_,
        bool deployGovernor_
    ) DeployerTrait(addressProvider_) {
        if (deployGovernor_) {
            address governor = _deployLatestPatch({
                contractType: AP_GOVERNOR,
                minorVersion: 3_10,
                constructorParams: abi.encode(admin_, emergencyAdmin_, 1 days, false),
                salt: 0
            });
            admin = IGovernor(governor).timeLock();
        } else {
            admin = admin_;
        }
        emergencyAdmin = emergencyAdmin_;
        _curatorName = curatorName_.toSmallString();

        acl = _deployLatestPatch({
            contractType: AP_ACL,
            minorVersion: 3_10,
            constructorParams: abi.encode(address(this)),
            salt: 0
        });
        contractsRegister = _deployLatestPatch({
            contractType: AP_CONTRACTS_REGISTER,
            minorVersion: 3_10,
            constructorParams: abi.encode(acl),
            salt: 0
        });
        if (adminFeeTreasury_ != address(0)) {
            treasury = _deployLatestPatch({
                contractType: AP_TREASURY_SPLITTER,
                minorVersion: 3_10,
                constructorParams: abi.encode(addressProvider, admin, adminFeeTreasury_),
                salt: 0
            });
        } else {
            treasury = _getAddressOrRevert(AP_TREASURY, NO_VERSION_CONTROL);
        }

        IACL(acl).grantRole(ROLE_PAUSABLE_ADMIN, address(this));
        IACL(acl).grantRole(ROLE_UNPAUSABLE_ADMIN, address(this));

        emit SetEmergencyAdmin(emergencyAdmin_);
        emit GrantRole(ROLE_PAUSABLE_ADMIN, address(this));
        emit GrantRole(ROLE_UNPAUSABLE_ADMIN, address(this));
    }

    // -------- //
    // METADATA //
    // -------- //

    /// @notice Contract version
    /// @dev `MarketConfiguratorLegacy` might have different version, hence the `virtual` modifier
    function version() external view virtual override returns (uint256) {
        return 3_10;
    }

    /// @notice Contract type
    /// @dev `MarketConfiguratorLegacy` has different type, hence the `virtual` modifier
    function contractType() external view virtual override returns (bytes32) {
        return AP_MARKET_CONFIGURATOR;
    }

    /// @notice Curator name
    function curatorName() external view override returns (string memory) {
        return _curatorName.fromSmallString();
    }

    // ---------------- //
    // ROLES MANAGEMENT //
    // ---------------- //

    /// @notice Sets `newEmergencyAdmin` as emergency admin
    /// @dev Reverts if caller is not the admin
    function setEmergencyAdmin(address newEmergencyAdmin) external override onlyAdmin {
        if (newEmergencyAdmin == emergencyAdmin) return;
        emergencyAdmin = newEmergencyAdmin;
        emit SetEmergencyAdmin(newEmergencyAdmin);
    }

    /// @notice Grants role `role` to account `account`
    /// @dev Reverts if caller is not the admin
    function grantRole(bytes32 role, address account) external override onlyAdmin {
        _grantRole(role, account);
        emit GrantRole(role, account);
    }

    /// @notice Revokes role `role` from account `account`
    /// @dev Reverts if caller is not the admin
    function revokeRole(bytes32 role, address account) external override onlyAdmin {
        _revokeRole(role, account);
        emit RevokeRole(role, account);
    }

    /// @notice Emergency revokes role `role` from account `account`
    /// @dev Reverts if caller is not the emergency admin
    function emergencyRevokeRole(bytes32 role, address account) external override onlyEmergencyAdmin {
        _revokeRole(role, account);
        emit EmergencyRevokeRole(role, account);
    }

    // ----------------- //
    // MARKET MANAGEMENT //
    // ----------------- //

    /// @notice Returns the address of a pool that would be created with given parameters
    /// @param minorVersion Minor version to use for deployment
    /// @param underlying Market's underlying token
    /// @param name Market's name
    /// @param symbol Market's symbol
    function previewCreateMarket(uint256 minorVersion, address underlying, string calldata name, string calldata symbol)
        external
        view
        override
        returns (address)
    {
        MarketFactories memory factories = _getLatestMarketFactories(minorVersion);
        return IPoolFactory(factories.poolFactory).computePoolAddress(address(this), underlying, name, symbol);
    }

    /// @notice Creates and registers new market with given parameters.
    ///         Executes `onCreateMarket` hook of all market factories.
    /// @param minorVersion Minor version to use for deployment
    /// @param underlying Market's underlying token
    /// @param name Market's name
    /// @param symbol Market's symbol
    /// @param interestRateModelParams Parameters for interest rate model deployment
    /// @param rateKeeperParams Parameters for rate keeper deployment
    /// @param lossPolicyParams Parameters for loss policy deployment
    /// @param underlyingPriceFeed Price feed for underlying token
    /// @return pool Address of the created pool
    /// @dev Reverts if caller is not the admin
    function createMarket(
        uint256 minorVersion,
        address underlying,
        string calldata name,
        string calldata symbol,
        DeployParams calldata interestRateModelParams,
        DeployParams calldata rateKeeperParams,
        DeployParams calldata lossPolicyParams,
        address underlyingPriceFeed
    ) external override onlyAdmin returns (address pool) {
        MarketFactories memory factories = _getLatestMarketFactories(minorVersion);

        // NOTE: some implementations of pool factory might need underlying to mint dead shares
        IERC20(underlying).forceApprove(factories.poolFactory, type(uint256).max);
        pool = _deployPool(factories.poolFactory, underlying, name, symbol);
        IERC20(underlying).forceApprove(factories.poolFactory, 0);

        address priceOracle = _deployPriceOracle(factories.priceOracleFactory, pool);
        address interestRateModel =
            _deployInterestRateModel(factories.interestRateModelFactory, pool, interestRateModelParams);
        address rateKeeper = _deployRateKeeper(factories.rateKeeperFactory, pool, rateKeeperParams);
        address lossPolicy = _deployLossPolicy(factories.lossPolicyFactory, pool, lossPolicyParams);
        _marketFactories[pool] = factories;

        _registerMarket(pool, priceOracle, lossPolicy);
        _executeMarketHooks(
            pool,
            abi.encodeCall(
                IMarketFactory.onCreateMarket,
                (pool, priceOracle, interestRateModel, rateKeeper, lossPolicy, underlyingPriceFeed)
            )
        );
        emit CreateMarket(pool, priceOracle, interestRateModel, rateKeeper, lossPolicy, factories);
    }

    /// @notice Shuts down market for `pool`.
    ///         Executes `onShutdownMarket` hook of all market factories.
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if pool is not registered
    function shutdownMarket(address pool) external override onlyAdmin onlyRegisteredMarket(pool) {
        _executeMarketHooks(pool, abi.encodeCall(IMarketFactory.onShutdownMarket, (pool)));
        IContractsRegister(contractsRegister).shutdownMarket(pool);
        emit ShutdownMarket(pool);
    }

    /// @notice Adds token `token` with price feed `priceFeed` to market for `pool`.
    ///         Executes `onAddToken` hook of all market factories.
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if pool is not registered
    function addToken(address pool, address token, address priceFeed)
        external
        override
        onlyAdmin
        onlyRegisteredMarket(pool)
    {
        _executeMarketHooks(pool, abi.encodeCall(IMarketFactory.onAddToken, (pool, token, priceFeed)));
        emit AddToken(pool, token);
    }

    /// @notice Configures `pool` by executing `configure` hook of market's pool factory
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if pool is not registered
    function configurePool(address pool, bytes calldata data) external override onlyAdmin onlyRegisteredMarket(pool) {
        _configure(_marketFactories[pool].poolFactory, pool, data);
        emit ConfigurePool(pool, data);
    }

    /// @notice Configures `pool` by executing `emergencyConfigure` hook of market's pool factory
    /// @dev Reverts if caller is not the emergency admin
    /// @dev Reverts if pool is not registered
    function emergencyConfigurePool(address pool, bytes calldata data)
        external
        override
        onlyEmergencyAdmin
        onlyRegisteredMarket(pool)
    {
        _emergencyConfigure(_marketFactories[pool].poolFactory, pool, data);
        emit EmergencyConfigurePool(pool, data);
    }

    /// @dev Deploys pool via factory and executes installation hooks
    function _deployPool(address factory, address underlying, string calldata name, string calldata symbol)
        internal
        returns (address)
    {
        DeployResult memory deployResult = IPoolFactory(factory).deployPool(underlying, name, symbol);
        _executeHook(factory, deployResult.onInstallOps);
        return deployResult.newContract;
    }

    // ----------------------- //
    // CREDIT SUITE MANAGEMENT //
    // ----------------------- //

    /// @notice Returns the address of a credit manager that would be created in existing market
    /// @param minorVersion Minor version to use for deployment
    /// @param pool Pool to create credit suite for
    /// @param encodedParams Encoded parameters for credit suite deployment
    function previewCreateCreditSuite(uint256 minorVersion, address pool, bytes calldata encodedParams)
        external
        view
        override
        returns (address)
    {
        address factory = _getLatestCreditFactory(minorVersion);
        return ICreditFactory(factory).computeCreditManagerAddress(
            address(this),
            pool,
            IPoolV3(pool).asset(),
            IContractsRegister(contractsRegister).getPriceOracle(pool),
            encodedParams
        );
    }

    /// @notice Returns the address of a credit manager that would be created in a new market
    /// @param marketMinorVersion Minor version to use for market deployment
    /// @param creditSuiteMinorVersion Minor version to use for credit manager deployment
    /// @param underlying Market's underlying token
    /// @param name Market's name
    /// @param symbol Market's symbol
    /// @param encodedParams Encoded parameters for credit manager deployment
    function previewCreateCreditSuite(
        uint256 marketMinorVersion,
        uint256 creditSuiteMinorVersion,
        address underlying,
        string calldata name,
        string calldata symbol,
        bytes calldata encodedParams
    ) external view override returns (address) {
        MarketFactories memory factories = _getLatestMarketFactories(marketMinorVersion);
        address pool = IPoolFactory(factories.poolFactory).computePoolAddress(address(this), underlying, name, symbol);
        address priceOracle =
            IPriceOracleFactory(factories.priceOracleFactory).computePriceOracleAddress(address(this), pool);

        address factory = _getLatestCreditFactory(creditSuiteMinorVersion);
        return ICreditFactory(factory).computeCreditManagerAddress(
            address(this), pool, underlying, priceOracle, encodedParams
        );
    }

    /// @notice Creates and registers new credit suite in a market for `pool`.
    ///         Executes `onCreateCreditSuite` hook of all market factories.
    /// @param minorVersion Minor version to use for deployment
    /// @param pool Pool to create credit suite for
    /// @param encodedParams Encoded parameters for credit suite deployment
    /// @return creditManager Address of the created credit manager
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if pool is not registered
    function createCreditSuite(uint256 minorVersion, address pool, bytes calldata encodedParams)
        external
        override
        onlyAdmin
        onlyRegisteredMarket(pool)
        returns (address creditManager)
    {
        address factory = _getLatestCreditFactory(minorVersion);
        creditManager = _deployCreditSuite(factory, pool, encodedParams);
        _creditFactories[creditManager] = factory;

        _registerCreditSuite(creditManager);
        _executeMarketHooks(pool, abi.encodeCall(IMarketFactory.onCreateCreditSuite, (creditManager)));
        emit CreateCreditSuite(creditManager, factory);
    }

    /// @notice Shuts down credit suite for `creditManager`.
    ///         Executes `onShutdownCreditSuite` hook of all market factories.
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if credit suite is not registered
    function shutdownCreditSuite(address creditManager)
        external
        override
        onlyAdmin
        onlyRegisteredCreditSuite(creditManager)
    {
        address pool = ICreditManagerV3(creditManager).pool();
        _executeMarketHooks(pool, abi.encodeCall(IMarketFactory.onShutdownCreditSuite, (creditManager)));
        IContractsRegister(contractsRegister).shutdownCreditSuite(creditManager);
        emit ShutdownCreditSuite(creditManager);
    }

    /// @notice Configures credit suite for `creditManager` by executing `configure` hook of its factory
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if credit suite is not registered
    function configureCreditSuite(address creditManager, bytes calldata data)
        external
        override
        onlyAdmin
        onlyRegisteredCreditSuite(creditManager)
    {
        _configure(_creditFactories[creditManager], creditManager, data);
        emit ConfigureCreditSuite(creditManager, data);
    }

    /// @notice Configures credit suite for `creditManager` by executing `emergencyConfigure` hook of its factory
    /// @dev Reverts if caller is not the emergency admin
    /// @dev Reverts if credit manager is not registered
    function emergencyConfigureCreditSuite(address creditManager, bytes calldata data)
        external
        override
        onlyEmergencyAdmin
        onlyRegisteredCreditSuite(creditManager)
    {
        _emergencyConfigure(_creditFactories[creditManager], creditManager, data);
        emit EmergencyConfigureCreditSuite(creditManager, data);
    }

    /// @dev Deploys credit suite via factory and executes installation hooks
    function _deployCreditSuite(address factory, address pool, bytes calldata encodedParams)
        internal
        returns (address)
    {
        DeployResult memory deployResult = ICreditFactory(factory).deployCreditSuite(pool, encodedParams);
        _executeHook(factory, deployResult.onInstallOps);
        return deployResult.newContract;
    }

    // ----------------------- //
    // PRICE ORACLE MANAGEMENT //
    // ----------------------- //

    /// @notice Updates price oracle in market for `pool`.
    ///         Executes `onUpdatePriceOracle` hook of all market and credit factories.
    /// @param pool Pool to update price oracle for
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if pool is not registered
    function updatePriceOracle(address pool)
        external
        override
        onlyAdmin
        onlyRegisteredMarket(pool)
        returns (address priceOracle)
    {
        address oldPriceOracle = IContractsRegister(contractsRegister).getPriceOracle(pool);
        priceOracle = _deployPriceOracle(_marketFactories[pool].priceOracleFactory, pool);

        IContractsRegister(contractsRegister).setPriceOracle(pool, priceOracle);
        _executeMarketHooks(
            pool, abi.encodeCall(IMarketFactory.onUpdatePriceOracle, (pool, priceOracle, oldPriceOracle))
        );

        address[] memory creditManagers = _registeredCreditManagers(pool);
        uint256 numManagers = creditManagers.length;
        for (uint256 i; i < numManagers; ++i) {
            address creditManager = creditManagers[i];
            _executeHook(
                _creditFactories[creditManager],
                abi.encodeCall(ICreditFactory.onUpdatePriceOracle, (creditManager, priceOracle, oldPriceOracle))
            );
        }
        emit UpdatePriceOracle(pool, priceOracle);
    }

    /// @notice Configures price oracle in market for `pool` by executing
    ///         `configure` hook of market's price oracle factory
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if pool is not registered
    function configurePriceOracle(address pool, bytes calldata data)
        external
        override
        onlyAdmin
        onlyRegisteredMarket(pool)
    {
        _configure(_marketFactories[pool].priceOracleFactory, pool, data);
        emit ConfigurePriceOracle(pool, data);
    }

    /// @notice Emergency configures price oracle in market for `pool` by executing
    ///         `emergencyConfigure` hook of market's price oracle factory
    /// @dev Reverts if caller is not the emergency admin
    /// @dev Reverts if pool is not registered
    function emergencyConfigurePriceOracle(address pool, bytes calldata data)
        external
        override
        onlyEmergencyAdmin
        onlyRegisteredMarket(pool)
    {
        _emergencyConfigure(_marketFactories[pool].priceOracleFactory, pool, data);
        emit EmergencyConfigurePriceOracle(pool, data);
    }

    /// @dev Deploys price oracle via factory and executes installation hooks
    function _deployPriceOracle(address factory, address pool) internal returns (address) {
        DeployResult memory deployResult = IPriceOracleFactory(factory).deployPriceOracle(pool);
        _executeHook(factory, deployResult.onInstallOps);
        return deployResult.newContract;
    }

    // -------------- //
    // IRM MANAGEMENT //
    // -------------- //

    /// @notice Updates interest rate model in market for `pool`.
    ///         Executes `onUpdateInterestRateModel` hook of all market factories.
    /// @param pool Pool to update interest rate model for
    /// @param params Parameters for interest rate model deployment
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if pool is not registered
    function updateInterestRateModel(address pool, DeployParams calldata params)
        external
        override
        onlyAdmin
        onlyRegisteredMarket(pool)
        returns (address interestRateModel)
    {
        address oldInterestRateModel = _interestRateModel(pool);
        interestRateModel = _deployInterestRateModel(_marketFactories[pool].interestRateModelFactory, pool, params);

        _executeMarketHooks(
            pool,
            abi.encodeCall(IMarketFactory.onUpdateInterestRateModel, (pool, interestRateModel, oldInterestRateModel))
        );
        emit UpdateInterestRateModel(pool, interestRateModel);
    }

    /// @notice Configures interest rate model in market for `pool` by executing
    ///         `configure` hook of market's interest rate model factory
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if pool is not registered
    function configureInterestRateModel(address pool, bytes calldata data)
        external
        override
        onlyAdmin
        onlyRegisteredMarket(pool)
    {
        _configure(_marketFactories[pool].interestRateModelFactory, pool, data);
        emit ConfigureInterestRateModel(pool, data);
    }

    /// @notice Emergency configures interest rate model in market for `pool` by executing
    ///         `emergencyConfigure` hook of market's interest rate model factory
    /// @dev Reverts if caller is not the emergency admin
    /// @dev Reverts if pool is not registered
    function emergencyConfigureInterestRateModel(address pool, bytes calldata data)
        external
        override
        onlyEmergencyAdmin
        onlyRegisteredMarket(pool)
    {
        _emergencyConfigure(_marketFactories[pool].interestRateModelFactory, pool, data);
        emit EmergencyConfigureInterestRateModel(pool, data);
    }

    /// @dev Deploys interest rate model via factory and executes installation hooks
    function _deployInterestRateModel(address factory, address pool, DeployParams calldata params)
        internal
        returns (address)
    {
        DeployResult memory deployResult = IInterestRateModelFactory(factory).deployInterestRateModel(pool, params);
        _executeHook(factory, deployResult.onInstallOps);
        return deployResult.newContract;
    }

    // ---------------------- //
    // RATE KEEPER MANAGEMENT //
    // ---------------------- //

    /// @notice Updates rate keeper in market for `pool`.
    ///         Executes `onUpdateRateKeeper` hook of all market factories.
    /// @param pool Pool to update rate keeper for
    /// @param params Parameters for rate keeper deployment
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if pool is not registered
    function updateRateKeeper(address pool, DeployParams calldata params)
        external
        override
        onlyAdmin
        onlyRegisteredMarket(pool)
        returns (address rateKeeper)
    {
        address oldRateKeeper = _rateKeeper(_quotaKeeper(pool));
        rateKeeper = _deployRateKeeper(_marketFactories[pool].rateKeeperFactory, pool, params);

        _executeMarketHooks(pool, abi.encodeCall(IMarketFactory.onUpdateRateKeeper, (pool, rateKeeper, oldRateKeeper)));
        emit UpdateRateKeeper(pool, rateKeeper);
    }

    /// @notice Configures rate keeper in market for `pool` by executing
    ///         `configure` hook of market's rate keeper factory
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if pool is not registered
    function configureRateKeeper(address pool, bytes calldata data)
        external
        override
        onlyAdmin
        onlyRegisteredMarket(pool)
    {
        _configure(_marketFactories[pool].rateKeeperFactory, pool, data);
        emit ConfigureRateKeeper(pool, data);
    }

    /// @notice Emergency configures rate keeper in market for `pool` by executing
    ///         `emergencyConfigure` hook of market's rate keeper factory
    /// @dev Reverts if caller is not the emergency admin
    /// @dev Reverts if pool is not registered
    function emergencyConfigureRateKeeper(address pool, bytes calldata data)
        external
        override
        onlyEmergencyAdmin
        onlyRegisteredMarket(pool)
    {
        _emergencyConfigure(_marketFactories[pool].rateKeeperFactory, pool, data);
        emit EmergencyConfigureRateKeeper(pool, data);
    }

    /// @dev Deploys rate keeper via factory and executes installation hooks
    function _deployRateKeeper(address factory, address pool, DeployParams calldata params)
        internal
        returns (address)
    {
        DeployResult memory deployResult = IRateKeeperFactory(factory).deployRateKeeper(pool, params);
        _executeHook(factory, deployResult.onInstallOps);
        return deployResult.newContract;
    }

    // ---------------------- //
    // LOSS POLICY MANAGEMENT //
    // ---------------------- //

    /// @notice Updates loss policy in market for `pool`.
    ///         Executes `onUpdateLossPolicy` hook of all market and credit factories.
    /// @param pool Pool to update loss policy for
    /// @param params Parameters for loss policy deployment
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if pool is not registered
    function updateLossPolicy(address pool, DeployParams calldata params)
        external
        override
        onlyAdmin
        onlyRegisteredMarket(pool)
        returns (address lossPolicy)
    {
        address oldLossPolicy = IContractsRegister(contractsRegister).getLossPolicy(pool);
        lossPolicy = _deployLossPolicy(_marketFactories[pool].lossPolicyFactory, pool, params);

        IContractsRegister(contractsRegister).setLossPolicy(pool, lossPolicy);
        _executeMarketHooks(pool, abi.encodeCall(IMarketFactory.onUpdateLossPolicy, (pool, lossPolicy, oldLossPolicy)));

        address[] memory creditManagers = _registeredCreditManagers(pool);
        uint256 numManagers = creditManagers.length;
        for (uint256 i; i < numManagers; ++i) {
            address creditManager = creditManagers[i];
            _executeHook(
                _creditFactories[creditManager],
                abi.encodeCall(ICreditFactory.onUpdateLossPolicy, (creditManager, lossPolicy, oldLossPolicy))
            );
        }
        emit UpdateLossPolicy(pool, lossPolicy);
    }

    /// @notice Configures loss policy in market for `pool` by executing
    ///         `configure` hook of market's loss policy factory
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if pool is not registered
    function configureLossPolicy(address pool, bytes calldata data)
        external
        override
        onlyAdmin
        onlyRegisteredMarket(pool)
    {
        _configure(_marketFactories[pool].lossPolicyFactory, pool, data);
        emit ConfigureLossPolicy(pool, data);
    }

    /// @notice Emergency configures loss policy in market for `pool` by executing
    ///         `emergencyConfigure` hook of market's loss policy factory
    /// @dev Reverts if caller is not the emergency admin
    /// @dev Reverts if pool is not registered
    function emergencyConfigureLossPolicy(address pool, bytes calldata data)
        external
        override
        onlyEmergencyAdmin
        onlyRegisteredMarket(pool)
    {
        _emergencyConfigure(_marketFactories[pool].lossPolicyFactory, pool, data);
        emit EmergencyConfigureLossPolicy(pool, data);
    }

    /// @dev Deploys loss policy for a pool via factory and executes installation hooks
    function _deployLossPolicy(address factory, address pool, DeployParams calldata params)
        internal
        returns (address)
    {
        DeployResult memory deployResult = ILossPolicyFactory(factory).deployLossPolicy(pool, params);
        _executeHook(factory, deployResult.onInstallOps);
        return deployResult.newContract;
    }

    // --------- //
    // FACTORIES //
    // --------- //

    /// @notice Returns factories in market for `pool`
    function getMarketFactories(address pool) external view override returns (MarketFactories memory) {
        return _marketFactories[pool];
    }

    /// @notice Returns credit factory of credit suite for `creditManager`
    function getCreditFactory(address creditManager) external view override returns (address) {
        return _creditFactories[creditManager];
    }

    /// @notice Returns factory authorized to configure given `target`
    function getAuthorizedFactory(address target) external view override returns (address) {
        return _authorizedFactories[target];
    }

    /// @notice Returns all targets `factory` is authorized to configure in a given market/credit `suite`
    function getFactoryTargets(address factory, address suite) external view override returns (address[] memory) {
        return _factoryTargets[factory][suite].values();
    }

    /// @notice Authorizes `factory` to configure `target` in a given market/credit `suite`
    /// @dev Reverts if caller is not the contract itself
    /// @dev Reverts if other factory is already authorized to configure `target`
    function authorizeFactory(address factory, address suite, address target) external override onlySelf {
        if (_authorizedFactories[target] == factory) return;
        if (_authorizedFactories[target] != address(0)) revert UnauthorizedFactoryException(factory, target);
        _authorizeFactory(factory, suite, target);
    }

    /// @notice Unauthorizes `factory` to configure `target` in a given market/credit `suite`
    /// @dev Reverts if caller is not the contract itself
    /// @dev Reverts if `factory` is not authorized to configure `target`
    function unauthorizeFactory(address factory, address suite, address target) external override onlySelf {
        if (_authorizedFactories[target] == address(0)) return;
        if (_authorizedFactories[target] != factory) revert UnauthorizedFactoryException(factory, target);
        _unauthorizeFactory(factory, suite, target);
    }

    /// @notice Upgrades pool factory of market for `pool` to latest patch
    /// @dev Reverts if caller is not the admin
    function upgradePoolFactory(address pool) external override onlyAdmin {
        address oldFactory = _marketFactories[pool].poolFactory;
        address newFactory = _getLatestPatch(oldFactory);
        if (newFactory == oldFactory) return;
        _marketFactories[pool].poolFactory = newFactory;
        _migrateFactoryTargets(oldFactory, newFactory, pool);
        emit UpgradePoolFactory(pool, newFactory);
    }

    /// @notice Upgrades price oracle factory of market for `pool` to latest patch
    /// @dev Reverts if caller is not the admin
    function upgradePriceOracleFactory(address pool) external override onlyAdmin {
        address oldFactory = _marketFactories[pool].priceOracleFactory;
        address newFactory = _getLatestPatch(oldFactory);
        if (newFactory == oldFactory) return;
        _marketFactories[pool].priceOracleFactory = newFactory;
        _migrateFactoryTargets(oldFactory, newFactory, pool);
        emit UpgradePriceOracleFactory(pool, newFactory);
    }

    /// @notice Upgrades interest rate model factory of market for `pool` to latest patch
    /// @dev Reverts if caller is not the admin
    function upgradeInterestRateModelFactory(address pool) external override onlyAdmin {
        address oldFactory = _marketFactories[pool].interestRateModelFactory;
        address newFactory = _getLatestPatch(oldFactory);
        if (newFactory == oldFactory) return;
        _marketFactories[pool].interestRateModelFactory = newFactory;
        _migrateFactoryTargets(oldFactory, newFactory, pool);
        emit UpgradeInterestRateModelFactory(pool, newFactory);
    }

    /// @notice Upgrades rate keeper factory of market for `pool` to latest patch
    /// @dev Reverts if caller is not the admin
    function upgradeRateKeeperFactory(address pool) external override onlyAdmin {
        address oldFactory = _marketFactories[pool].rateKeeperFactory;
        address newFactory = _getLatestPatch(oldFactory);
        if (newFactory == oldFactory) return;
        _marketFactories[pool].rateKeeperFactory = newFactory;
        _migrateFactoryTargets(oldFactory, newFactory, pool);
        emit UpgradeRateKeeperFactory(pool, newFactory);
    }

    /// @notice Upgrades loss policy factory of market for `pool` to latest patch
    /// @dev Reverts if caller is not the admin
    function upgradeLossPolicyFactory(address pool) external override onlyAdmin {
        address oldFactory = _marketFactories[pool].lossPolicyFactory;
        address newFactory = _getLatestPatch(oldFactory);
        if (newFactory == oldFactory) return;
        _marketFactories[pool].lossPolicyFactory = newFactory;
        _migrateFactoryTargets(oldFactory, newFactory, pool);
        emit UpgradeLossPolicyFactory(pool, newFactory);
    }

    /// @notice Upgrades credit factory of credit suite for `creditManager` to latest patch
    /// @dev Reverts if caller is not the admin
    function upgradeCreditFactory(address creditManager) external override onlyAdmin {
        address oldFactory = _creditFactories[creditManager];
        address newFactory = _getLatestPatch(oldFactory);
        if (newFactory == oldFactory) return;
        _creditFactories[creditManager] = newFactory;
        _migrateFactoryTargets(oldFactory, newFactory, creditManager);
        emit UpgradeCreditFactory(creditManager, newFactory);
    }

    // --------- //
    // PERIPHERY //
    // --------- //

    /// @notice Returns all periphery contracts registered in a given `domain`
    function getPeripheryContracts(bytes32 domain) external view override returns (address[] memory) {
        return _peripheryContracts[domain].values();
    }

    /// @notice Whether `peripheryContract` is registered in `domain`
    function isPeripheryContract(bytes32 domain, address peripheryContract) external view override returns (bool) {
        return _peripheryContracts[domain].contains(peripheryContract);
    }

    /// @notice Adds `peripheryContract` to a list of registered periphery contracts in its domain
    /// @dev Reverts if caller is not the admin
    /// @dev Reverts if contract is not deployed via bytecode repository
    function addPeripheryContract(address peripheryContract) external override onlyAdmin {
        if (!IBytecodeRepository(bytecodeRepository).isDeployedFromRepository(peripheryContract)) {
            revert IncorrectPeripheryContractException(peripheryContract);
        }
        bytes32 domain = _getDomain(peripheryContract);
        if (_peripheryContracts[domain].add(peripheryContract)) {
            emit AddPeripheryContract(domain, peripheryContract);
        }
    }

    /// @notice Removes `peripheryContract` from a list of registered periphery contracts in its domain
    /// @dev Reverts if caller is not the admin
    function removePeripheryContract(address peripheryContract) external override onlyAdmin {
        bytes32 domain = _getDomain(peripheryContract);
        if (_peripheryContracts[domain].remove(peripheryContract)) {
            emit RemovePeripheryContract(domain, peripheryContract);
        }
    }

    /// @dev Returns domain of a `peripheryContract`
    function _getDomain(address peripheryContract) internal view returns (bytes32) {
        try IVersion(peripheryContract).contractType() returns (bytes32 type_) {
            return Domain.extractDomain(type_);
        } catch {
            revert IncorrectPeripheryContractException(peripheryContract);
        }
    }

    // --------- //
    // INTERNALS //
    // --------- //

    /// @dev Ensures caller is the contract itself
    function _ensureCallerIsSelf() internal view {
        if (msg.sender != address(this)) revert CallerIsNotSelfException(msg.sender);
    }

    /// @dev Ensures caller is the admin
    function _ensureCallerIsAdmin() internal view {
        if (msg.sender != admin) revert CallerIsNotAdminException(msg.sender);
    }

    /// @dev Ensures caller is the emergency admin
    function _ensureCallerIsEmergencyAdmin() internal view {
        if (msg.sender != emergencyAdmin) revert CallerIsNotEmergencyAdminException(msg.sender);
    }

    /// @dev Ensures pool is registered
    function _ensureRegisteredMarket(address pool) internal view {
        if (!IContractsRegister(contractsRegister).isPool(pool)) {
            revert MarketNotRegisteredException(pool);
        }
    }

    /// @dev Ensures credit manager is registered
    function _ensureRegisteredCreditSuite(address creditManager) internal view {
        if (!IContractsRegister(contractsRegister).isCreditManager(creditManager)) {
            revert CreditSuiteNotRegisteredException(creditManager);
        }
    }

    /// @dev Grants role to account in ACL
    /// @dev `MarketConfiguratorLegacy` performs additional actions, hence the `virtual` modifier
    function _grantRole(bytes32 role, address account) internal virtual {
        IACL(acl).grantRole(role, account);
    }

    /// @dev Revokes role from account in ACL
    /// @dev `MarketConfiguratorLegacy` performs additional actions, hence the `virtual` modifier
    function _revokeRole(bytes32 role, address account) internal virtual {
        IACL(acl).revokeRole(role, account);
    }

    /// @dev Registers market in contracts register
    /// @dev `MarketConfiguratorLegacy` performs additional actions, hence the `virtual` modifier
    function _registerMarket(address pool, address priceOracle, address lossPolicy) internal virtual {
        IContractsRegister(contractsRegister).registerMarket(pool, priceOracle, lossPolicy);
    }

    /// @dev Registers credit suite in contracts register
    /// @dev `MarketConfiguratorLegacy` performs additional actions, hence the `virtual` modifier
    function _registerCreditSuite(address creditManager) internal virtual {
        IContractsRegister(contractsRegister).registerCreditSuite(creditManager);
    }

    /// @dev Validates that `factory` is authorized to configure `target`
    /// @dev `MarketConfiguratorLegacy` performs additional checks, hence the `virtual` modifier
    function _validateCallTarget(address target, address factory) internal virtual {
        if (target != address(this) && _authorizedFactories[target] != factory) {
            revert UnauthorizedFactoryException(factory, target);
        }
    }

    /// @dev Returns latest patch in the address provider for given contract type with matching minor version
    function _getLatestPatch(bytes32 key, uint256 minorVersion) internal view returns (address) {
        return _getAddressOrRevert(key, IAddressProvider(addressProvider).getLatestPatchVersion(key, minorVersion));
    }

    /// @dev Returns latest patch for given `factory`
    function _getLatestPatch(address factory) internal view returns (address) {
        return _getLatestPatch(IVersion(factory).contractType(), IVersion(factory).version());
    }

    /// @dev Returns latest market factories for given `minorVersion`
    function _getLatestMarketFactories(uint256 minorVersion) internal view returns (MarketFactories memory) {
        if (minorVersion / 100 != 3) revert IncorrectMinorVersionException(minorVersion);
        return MarketFactories({
            poolFactory: _getLatestPatch(AP_POOL_FACTORY, minorVersion),
            priceOracleFactory: _getLatestPatch(AP_PRICE_ORACLE_FACTORY, minorVersion),
            interestRateModelFactory: _getLatestPatch(AP_INTEREST_RATE_MODEL_FACTORY, minorVersion),
            rateKeeperFactory: _getLatestPatch(AP_RATE_KEEPER_FACTORY, minorVersion),
            lossPolicyFactory: _getLatestPatch(AP_LOSS_POLICY_FACTORY, minorVersion)
        });
    }

    /// @dev Returns latest credit factory for given `minorVersion`
    function _getLatestCreditFactory(uint256 minorVersion) internal view returns (address) {
        if (minorVersion / 100 != 3) revert IncorrectMinorVersionException(minorVersion);
        return _getLatestPatch(AP_CREDIT_FACTORY, minorVersion);
    }

    /// @dev Authorizes `factory` to configure `target` in a market/credit `suite`
    function _authorizeFactory(address factory, address suite, address target) internal {
        _authorizedFactories[target] = factory;
        _factoryTargets[factory][suite].add(target);
        emit AuthorizeFactory(factory, suite, target);
    }

    /// @dev Unauthorizes `factory` to configure `target` in a market/credit `suite`
    function _unauthorizeFactory(address factory, address suite, address target) internal {
        _authorizedFactories[target] = address(0);
        _factoryTargets[factory][suite].remove(target);
        emit UnauthorizeFactory(factory, suite, target);
    }

    /// @dev Migrates all targets from old factory to new factory in a market or credit suite
    function _migrateFactoryTargets(address oldFactory, address newFactory, address suite) internal {
        address[] memory targets = _factoryTargets[oldFactory][suite].values();
        uint256 numTargets = targets.length;
        for (uint256 i; i < numTargets; ++i) {
            address target = targets[i];
            _factoryTargets[oldFactory][suite].remove(target);
            _factoryTargets[newFactory][suite].add(target);
            _authorizedFactories[target] = newFactory;
            emit UnauthorizeFactory(oldFactory, suite, target);
            emit AuthorizeFactory(newFactory, suite, target);
        }
    }

    /// @dev Executes calls returned by a hook in all market factories
    function _executeMarketHooks(address pool, bytes memory data) internal {
        MarketFactories memory factories = _marketFactories[pool];
        _executeHook(factories.poolFactory, data);
        _executeHook(factories.priceOracleFactory, data);
        _executeHook(factories.interestRateModelFactory, data);
        _executeHook(factories.rateKeeperFactory, data);
        _executeHook(factories.lossPolicyFactory, data);
    }

    /// @dev Executes calls returned by factory hook
    function _executeHook(address factory, bytes memory data) internal {
        _executeHook(factory, abi.decode(factory.functionCall(data), (Call[])));
    }

    /// @dev Executes calls returned by factory configuration hook
    function _configure(address factory, address target, bytes calldata callData) internal {
        _executeHook(factory, IFactory(factory).configure(target, callData));
    }

    /// @dev Executes calls returned by factory emergency configuration hook
    function _emergencyConfigure(address factory, address target, bytes calldata callData) internal {
        _executeHook(factory, IFactory(factory).emergencyConfigure(target, callData));
    }

    /// @dev Executes array of calls after validating targets
    function _executeHook(address factory, Call[] memory calls) internal {
        uint256 len = calls.length;
        for (uint256 i; i < len; ++i) {
            address target = calls[i].target;
            bytes memory callData = calls[i].callData;
            _validateCallTarget(target, factory);
            target.functionCall(callData);
            emit ExecuteHook(target, callData);
        }
    }

    /// @dev Returns all registered credit managers
    function _registeredCreditManagers() internal view returns (address[] memory) {
        return IContractsRegister(contractsRegister).getCreditManagers();
    }

    /// @dev Returns all registered credit managers for `pool`
    function _registeredCreditManagers(address pool) internal view returns (address[] memory creditManagers) {
        return IContractsRegister(contractsRegister).getCreditManagers(pool);
    }

    /// @dev Returns quota keeper of `pool`
    function _quotaKeeper(address pool) internal view returns (address) {
        return IPoolV3(pool).poolQuotaKeeper();
    }

    /// @dev Returns interest rate model if `pool`
    function _interestRateModel(address pool) internal view returns (address) {
        return IPoolV3(pool).interestRateModel();
    }

    /// @dev Returns rate keeper of `quotaKeeper`
    function _rateKeeper(address quotaKeeper) internal view returns (address) {
        return IPoolQuotaKeeperV3(quotaKeeper).gauge();
    }
}
