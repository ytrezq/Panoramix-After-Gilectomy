// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {CommonBase} from "forge-std/Base.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";

import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {LibString} from "@solady/utils/LibString.sol";

import {ITumblerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ITumblerV3.sol";

import {ConstantPriceFeed} from "../../helpers/ConstantPriceFeed.sol";

import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {IBytecodeRepository} from "../../interfaces/IBytecodeRepository.sol";
import {IInstanceManager} from "../../interfaces/IInstanceManager.sol";
import {IMarketConfigurator} from "../../interfaces/IMarketConfigurator.sol";
import {IMarketConfiguratorFactory} from "../../interfaces/IMarketConfiguratorFactory.sol";
import {IPriceFeedStore} from "../../interfaces/IPriceFeedStore.sol";
import {AuditReport, Bytecode, DeployParams} from "../../interfaces/Types.sol";
import {
    ICreditConfigureActions,
    CreditFacadeParams,
    CreditManagerParams
} from "../../interfaces/factories/ICreditConfigureActions.sol";
import {IPoolConfigureActions} from "../../interfaces/factories/IPoolConfigureActions.sol";
import {IPriceOracleConfigureActions} from "../../interfaces/factories/IPriceOracleConfigureActions.sol";

import {
    AP_BYTECODE_REPOSITORY,
    AP_CROSS_CHAIN_GOVERNANCE,
    AP_INSTANCE_MANAGER,
    AP_MARKET_CONFIGURATOR_FACTORY,
    AP_PRICE_FEED_STORE,
    AP_TREASURY,
    NO_VERSION_CONTROL
} from "../../libraries/ContractLiterals.sol";
import {Domain} from "../../libraries/Domain.sol";

abstract contract AttachBase is CommonBase {
    using Domain for bytes32;
    using LibString for bytes32;
    using stdStorage for StdStorage;

    address public constant ADDRESS_PROVIDER = 0xF7f0a609BfAb9a0A98786951ef10e5FE26cC1E38;
    bytes32 public constant SALT = "GEARBOX";

    // ----- //
    // SETUP //
    // ----- //

    VmSafe.Wallet public deployer;
    VmSafe.Wallet public author;
    VmSafe.Wallet public auditor;
    VmSafe.Wallet public riskCurator;

    address public zeroPriceFeed;
    address public onePriceFeed;

    function _setUp() internal virtual {
        _attachCore();
        _attachMarketConfigurator();

        _addAuditor(auditor.addr, "Fake Auditor");

        zeroPriceFeed = priceFeedStore.zeroPriceFeed();
        _addPriceFeed(zeroPriceFeed, 0, "$0 price feed");

        if (bytecodeRepository.getAllowedBytecodeHash("PRICE_FEED::CONSTANT", 3_10) == 0) {
            // NOTE: this would fail on deployment if we bump `ConstantPriceFeed` to v3.1.1,
            // but we assume that in this case v3.1.0 is already uploaded to the repository
            _uploadContract("PRICE_FEED::CONSTANT", 3_10, type(ConstantPriceFeed).creationCode);
        }
        onePriceFeed = _deploy("PRICE_FEED::CONSTANT", 3_10, abi.encode(1e8, "$1 price feed"));
        _addPriceFeed(onePriceFeed, 0, "$1 price feed");
    }

    // ---- //
    // CORE //
    // ---- //

    IAddressProvider public addressProvider;
    IBytecodeRepository public bytecodeRepository;
    IInstanceManager public instanceManager;
    IPriceFeedStore public priceFeedStore;
    IMarketConfiguratorFactory public marketConfiguratorFactory;

    address public crossChainGovernance;
    address public instanceOwner;
    address public treasury;

    function _attachCore() internal virtual {
        if (ADDRESS_PROVIDER.code.length == 0) revert("Instance is not deployed");
        addressProvider = IAddressProvider(ADDRESS_PROVIDER);
        bytecodeRepository =
            IBytecodeRepository(addressProvider.getAddressOrRevert(AP_BYTECODE_REPOSITORY, NO_VERSION_CONTROL));
        instanceManager = IInstanceManager(addressProvider.getAddressOrRevert(AP_INSTANCE_MANAGER, NO_VERSION_CONTROL));
        priceFeedStore = IPriceFeedStore(addressProvider.getAddressOrRevert(AP_PRICE_FEED_STORE, NO_VERSION_CONTROL));
        marketConfiguratorFactory = IMarketConfiguratorFactory(
            addressProvider.getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL)
        );
        crossChainGovernance = addressProvider.getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE, NO_VERSION_CONTROL);
        instanceOwner = instanceManager.owner();
        treasury = addressProvider.getAddressOrRevert(AP_TREASURY, NO_VERSION_CONTROL);
    }

    function _deploy(bytes32 contractType, uint256 version, bytes memory constructorParams) internal returns (address) {
        _omniPrank(deployer);
        return bytecodeRepository.deploy({
            contractType: contractType, version: version, constructorParams: constructorParams, salt: SALT
        });
    }

    function _uploadContract(bytes32 contractType, uint256 version, bytes memory initCode) internal {
        bytes32 allowedBytecodeHash = bytecodeRepository.getAllowedBytecodeHash(contractType, version);
        if (allowedBytecodeHash != 0) {
            bytes memory uploadedInitCode = bytecodeRepository.getBytecode(allowedBytecodeHash).initCode;
            require(
                keccak256(initCode) == keccak256(uploadedInitCode),
                string.concat("Bytecode mismatch for ", contractType.fromSmallString(), " v", vm.toString(version))
            );
            return;
        }

        Bytecode memory bytecode;
        bytecode.contractType = contractType;
        bytecode.version = version;
        bytecode.initCode = initCode;
        bytecode.source = "https://github.com/Gearbox-protocol/mock-contract-source-url";
        _signBytecode(author, bytecode);

        _omniPrank(author);
        bytecodeRepository.uploadBytecode(bytecode);

        bytes32 bytecodeHash = bytecodeRepository.computeBytecodeHash(bytecode);

        AuditReport memory auditReport;
        auditReport.reportUrl = "https://github.com/Gearbox-protocol/mock-audit-report-url";
        _signAuditReport(auditor, bytecodeHash, auditReport);
        _omniPrank(deployer);
        bytecodeRepository.submitAuditReport(bytecodeHash, auditReport);

        if (bytecodeRepository.isPublicDomain(Domain.extractDomain(contractType))) {
            if (bytecodeRepository.getContractTypeOwner(contractType) != address(0)) {
                // TODO: check if this works in script contexts, not sure about `checked_write`
                stdstore.target(address(bytecodeRepository)).sig("getContractTypeOwner(bytes32)").with_key(contractType)
                    .checked_write(author.addr);
            }
            _omniPrank(deployer);
            bytecodeRepository.allowPublicContract(bytecodeHash);
        } else {
            _allowSystemContract(bytecodeHash);
        }
    }

    function _signBytecode(VmSafe.Wallet memory signer, Bytecode memory bytecode) internal view {
        bytecode.author = signer.addr;
        bytecode.authorSignature =
            _sign(signer, bytecodeRepository.domainSeparatorV4(), bytecodeRepository.computeBytecodeHash(bytecode));
    }

    function _signAuditReport(VmSafe.Wallet memory signer, bytes32 bytecodeHash, AuditReport memory auditReport)
        internal
        view
    {
        auditReport.auditor = signer.addr;
        auditReport.signature = _sign(
            signer,
            bytecodeRepository.domainSeparatorV4(),
            bytecodeRepository.computeAuditReportHash(bytecodeHash, auditReport)
        );
    }

    function _deploySystemContract(bytes32 contractType, uint256 version) internal {
        _omniPrank(crossChainGovernance);
        instanceManager.deploySystemContract(contractType, version, true);
    }

    function _setGlobalAddress(bytes32 key, address addr, bool saveVersion) internal {
        _omniPrank(crossChainGovernance);
        instanceManager.setGlobalAddress(key, addr, saveVersion);
    }

    function _setLocalAddress(bytes32 key, address addr, bool saveVersion) internal {
        _omniPrank(instanceOwner);
        instanceManager.setLocalAddress(key, addr, saveVersion);
    }

    function _configureGlobal(address target, bytes memory data) internal {
        _omniPrank(crossChainGovernance);
        instanceManager.configureGlobal(target, data);
    }

    function _configureLocal(address target, bytes memory data) internal {
        _omniPrank(instanceOwner);
        instanceManager.configureLocal(target, data);
    }

    function _addAuditor(address newAuditor, string memory name) internal {
        if (bytecodeRepository.isAuditor(newAuditor)) return;

        _configureGlobal(address(bytecodeRepository), abi.encodeCall(bytecodeRepository.addAuditor, (newAuditor, name)));
    }

    function _addPublicDomain(bytes32 domain) internal {
        if (bytecodeRepository.isPublicDomain(domain)) return;

        _configureGlobal(address(bytecodeRepository), abi.encodeCall(bytecodeRepository.addPublicDomain, (domain)));
    }

    function _allowSystemContract(bytes32 bytecodeHash) internal {
        _configureGlobal(
            address(bytecodeRepository), abi.encodeCall(bytecodeRepository.allowSystemContract, (bytecodeHash))
        );
    }

    function _addPriceFeed(address priceFeed, uint32 stalenessPeriod, string memory name) internal {
        if (priceFeedStore.isKnownPriceFeed(priceFeed)) return;

        _configureLocal(
            address(priceFeedStore), abi.encodeCall(priceFeedStore.addPriceFeed, (priceFeed, stalenessPeriod, name))
        );
    }

    function _allowPriceFeed(address token, address priceFeed) internal {
        if (priceFeedStore.isAllowedPriceFeed(token, priceFeed)) return;

        _configureLocal(address(priceFeedStore), abi.encodeCall(priceFeedStore.allowPriceFeed, (token, priceFeed)));
    }

    // ------- //
    // MARKETS //
    // ------- //

    IMarketConfigurator public marketConfigurator;

    function _attachMarketConfigurator() internal {
        _omniPrank(riskCurator);
        marketConfigurator = IMarketConfigurator(
            marketConfiguratorFactory.createMarketConfigurator({
                emergencyAdmin: address(0),
                adminFeeTreasury: address(0),
                curatorName: "Fake Risk Curator",
                deployGovernor: false
            })
        );
    }

    struct MarketParams {
        string name;
        string symbol;
        DeployParams interestRateModelParams;
        DeployParams rateKeeperParams;
        DeployParams lossPolicyParams;
        address underlyingPriceFeed;
    }

    function _getDefaultMarketParams(address underlying) internal view returns (MarketParams memory) {
        string memory name = string.concat("Mock Diesel ", ERC20(underlying).name());
        string memory symbol = string.concat("md", ERC20(underlying).symbol());
        address pool = marketConfigurator.previewCreateMarket({
            minorVersion: 3_10, underlying: underlying, name: name, symbol: symbol
        });
        return MarketParams({
            name: name,
            symbol: symbol,
            interestRateModelParams: DeployParams({
                postfix: "LINEAR", salt: SALT, constructorParams: abi.encode(5000, 9000, 10_00, 0, 0, 0, false)
            }),
            rateKeeperParams: DeployParams({postfix: "TUMBLER", salt: SALT, constructorParams: abi.encode(pool, 0)}),
            lossPolicyParams: DeployParams({
                postfix: "ALIASED", salt: SALT, constructorParams: abi.encode(pool, ADDRESS_PROVIDER)
            }),
            underlyingPriceFeed: onePriceFeed
        });
    }

    function _createDefaultMockMarket(address underlying) internal returns (address) {
        return _createMockMarket(underlying, _getDefaultMarketParams(underlying));
    }

    function _createMockMarket(address underlying, MarketParams memory params) internal returns (address pool) {
        _omniPrank(riskCurator);
        pool = marketConfigurator.createMarket({
            minorVersion: 3_10,
            underlying: underlying,
            name: params.name,
            symbol: params.symbol,
            interestRateModelParams: params.interestRateModelParams,
            rateKeeperParams: params.rateKeeperParams,
            lossPolicyParams: params.lossPolicyParams,
            underlyingPriceFeed: params.underlyingPriceFeed
        });
    }

    struct CreditSuiteParams {
        uint128 minDebt;
        uint128 maxDebt;
        uint256 debtLimit;
        uint8 maxEnabledTokens;
        uint16 feeInterest;
        uint16 feeLiquidation;
        uint16 liquidationPremium;
        uint16 feeLiquidationExpired;
        uint16 liquidationPremiumExpired;
        address degenNFT;
        bool expirable;
        bool migrateBotList;
        DeployParams accountFactoryParams;
    }

    function _getDefaultCreditSuiteParams() internal pure returns (CreditSuiteParams memory) {
        return CreditSuiteParams({
            minDebt: 0,
            maxDebt: 0,
            debtLimit: 0,
            maxEnabledTokens: 2,
            feeInterest: 50_00,
            feeLiquidation: 1_00,
            liquidationPremium: 1_00,
            feeLiquidationExpired: 1_00,
            liquidationPremiumExpired: 1_00,
            degenNFT: address(0),
            expirable: false,
            migrateBotList: false,
            accountFactoryParams: DeployParams({
                postfix: "DEFAULT", salt: SALT, constructorParams: abi.encode(ADDRESS_PROVIDER)
            })
        });
    }

    function _createDefaultMockCreditSuite(address pool) internal returns (address) {
        return _createMockCreditSuite(pool, _getDefaultCreditSuiteParams());
    }

    function _createMockCreditSuite(address pool, CreditSuiteParams memory params)
        internal
        returns (address creditManager)
    {
        CreditManagerParams memory cmParams = CreditManagerParams({
            maxEnabledTokens: params.maxEnabledTokens,
            feeInterest: params.feeInterest,
            feeLiquidation: params.feeLiquidation,
            liquidationPremium: params.liquidationPremium,
            feeLiquidationExpired: params.feeLiquidationExpired,
            liquidationPremiumExpired: params.liquidationPremiumExpired,
            minDebt: params.minDebt,
            maxDebt: params.maxDebt,
            name: string.concat("Mock ", ERC20(ERC4626(pool).asset()).symbol(), " Credit Suite"),
            accountFactoryParams: params.accountFactoryParams
        });

        CreditFacadeParams memory cfParams = CreditFacadeParams({
            degenNFT: params.degenNFT, expirable: params.expirable, migrateBotList: params.migrateBotList
        });

        _startOmniPrank(riskCurator);
        creditManager = marketConfigurator.createCreditSuite({
            minorVersion: 3_10, pool: pool, encdodedParams: abi.encode(cmParams, cfParams)
        });

        if (params.debtLimit != 0) {
            marketConfigurator.configurePool(
                pool, abi.encodeCall(IPoolConfigureActions.setCreditManagerDebtLimit, (creditManager, params.debtLimit))
            );
        }
        _stopOmniPrank();
    }

    struct TokenParams {
        address token;
        address priceFeed;
        address reservePriceFeed;
        uint96 quotaLimit;
        uint16 quotaRate;
    }

    function _getDefaultTokenParams(address token) internal view returns (TokenParams memory) {
        return TokenParams({
            token: token, priceFeed: zeroPriceFeed, reservePriceFeed: address(0), quotaLimit: 0, quotaRate: 0
        });
    }

    function _addDefaultToken(address pool, address token) internal {
        _addToken(pool, _getDefaultTokenParams(token));
    }

    function _addToken(address pool, TokenParams memory params) internal {
        _startOmniPrank(riskCurator);

        marketConfigurator.addToken({pool: pool, token: params.token, priceFeed: params.priceFeed});

        if (params.reservePriceFeed != address(0)) {
            marketConfigurator.configurePriceOracle(
                pool,
                abi.encodeCall(
                    IPriceOracleConfigureActions.setReservePriceFeed, (params.token, params.reservePriceFeed)
                )
            );
        }
        if (params.quotaLimit != 0) {
            marketConfigurator.configurePool(
                pool, abi.encodeCall(IPoolConfigureActions.setTokenLimit, (params.token, params.quotaLimit))
            );
        }
        if (params.quotaRate != 0) {
            marketConfigurator.configureRateKeeper(
                pool, abi.encodeCall(ITumblerV3.setRate, (params.token, params.quotaRate))
            );
        }

        _stopOmniPrank();
    }

    function _addCollateralToken(address creditManager, address token, uint16 lt) internal {
        _omniPrank(riskCurator);
        marketConfigurator.configureCreditSuite(
            creditManager, abi.encodeCall(ICreditConfigureActions.addCollateralToken, (token, lt))
        );
    }

    function _allowAdapter(address creditManager, bytes32 postfix, bytes memory constructorParams) internal {
        _omniPrank(riskCurator);
        marketConfigurator.configureCreditSuite(
            creditManager,
            abi.encodeCall(
                ICreditConfigureActions.allowAdapter,
                (DeployParams({postfix: postfix, salt: SALT, constructorParams: constructorParams}))
            )
        );
    }

    function _configureAdapter(address creditManager, address targetContract, bytes memory data) internal {
        _omniPrank(riskCurator);
        marketConfigurator.configureCreditSuite(
            creditManager, abi.encodeCall(ICreditConfigureActions.configureAdapterFor, (targetContract, data))
        );
    }

    function _updateQuotaRates(address pool) internal {
        _omniPrank(riskCurator);
        IMarketConfigurator(marketConfigurator).configureRateKeeper(pool, abi.encodeCall(ITumblerV3.updateRates, ()));
    }

    function _addPeripheryContract(address peripheryContract) internal {
        _omniPrank(riskCurator);
        IMarketConfigurator(marketConfigurator).addPeripheryContract(peripheryContract);
    }

    // ----- //
    // UTILS //
    // ----- //

    error SignerIsNotInitialized();
    error UnknownExecutionContext();

    function _omniPrank(address caller) internal {
        if (vm.isContext(VmSafe.ForgeContext.TestGroup)) {
            vm.prank(caller);
        } else if (vm.isContext(VmSafe.ForgeContext.ScriptGroup)) {
            vm.broadcast(caller);
        } else {
            revert UnknownExecutionContext();
        }
    }

    function _omniPrank(VmSafe.Wallet memory wallet) internal {
        _omniPrank(wallet.addr);
    }

    function _startOmniPrank(address caller) internal {
        if (vm.isContext(VmSafe.ForgeContext.TestGroup)) {
            vm.startPrank(caller);
        } else if (vm.isContext(VmSafe.ForgeContext.ScriptGroup)) {
            vm.startBroadcast(caller);
        } else {
            revert UnknownExecutionContext();
        }
    }

    function _startOmniPrank(VmSafe.Wallet memory wallet) internal {
        _startOmniPrank(wallet.addr);
    }

    function _stopOmniPrank() internal {
        if (vm.isContext(VmSafe.ForgeContext.TestGroup)) {
            vm.stopPrank();
        } else if (vm.isContext(VmSafe.ForgeContext.ScriptGroup)) {
            vm.stopBroadcast();
        } else {
            revert UnknownExecutionContext();
        }
    }

    function _buildDomainSeparator(address eip712Contract) internal view returns (bytes32) {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            IERC5267(eip712Contract).eip712Domain();
        // TODO: use `fields` and `extensions` parameters to build the proper type hash
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
    }

    function _sign(VmSafe.Wallet memory signer, bytes32 domainSeparator, bytes32 structHash)
        internal
        pure
        returns (bytes memory)
    {
        bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, structHash);
        if (signer.privateKey != 0) {
            // for test contexts and script contexts where the private key is known, e.g.,
            // with explicitly set `--private-key` flag
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, digest);
            return abi.encodePacked(r, s, v);
        } else if (signer.addr != address(0)) {
            // for script contexts where the private key is not known, e.g.,
            // with `--keystore` or `--ledger` flags
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.addr, digest);
            return abi.encodePacked(r, s, v);
        }
        revert SignerIsNotInitialized();
    }
}
