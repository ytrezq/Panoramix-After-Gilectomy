// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {LibString} from "@solady/utils/LibString.sol";

import {ITumblerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ITumblerV3.sol";

import {IMarketConfigurator} from "../../interfaces/IMarketConfigurator.sol";
import {AuditReport, Bytecode, DeployParams} from "../../interfaces/Types.sol";
import {
    ICreditConfigureActions,
    CreditFacadeParams,
    CreditManagerParams
} from "../../interfaces/factories/ICreditConfigureActions.sol";
import {IPoolConfigureActions} from "../../interfaces/factories/IPoolConfigureActions.sol";
import {IPriceOracleConfigureActions} from "../../interfaces/factories/IPriceOracleConfigureActions.sol";

import {Domain} from "../../libraries/Domain.sol";

import {AttachBase} from "./AttachBase.sol";

contract AttachTestBase is AttachBase, Test {
    using LibString for bytes32;
    using stdStorage for StdStorage;

    // ---- //
    // CORE //
    // ---- //

    VmSafe.Wallet public author;
    VmSafe.Wallet public auditor;

    function _attachCore() internal virtual override {
        super._attachCore();

        author = vm.createWallet("MockAuthor");
        auditor = vm.createWallet("MockAuditor");

        vm.prank(crossChainGovernance);
        instanceManager.configureGlobal(
            address(bytecodeRepository), abi.encodeCall(bytecodeRepository.addAuditor, (auditor.addr, "MockAuditor"))
        );
    }

    function _addPublicDomain(bytes32 domain) internal {
        if (bytecodeRepository.isPublicDomain(domain)) return;

        vm.prank(crossChainGovernance);
        instanceManager.configureGlobal(
            address(bytecodeRepository), abi.encodeCall(bytecodeRepository.addPublicDomain, (domain))
        );
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

        vm.prank(author.addr);
        bytecodeRepository.uploadBytecode(bytecode);

        bytes32 bytecodeHash = bytecodeRepository.computeBytecodeHash(bytecode);

        AuditReport memory auditReport;
        auditReport.reportUrl = "https://github.com/Gearbox-protocol/mock-audit-report-url";
        _signAuditReport(auditor, bytecodeHash, auditReport);
        bytecodeRepository.submitAuditReport(bytecodeHash, auditReport);

        if (bytecodeRepository.isPublicDomain(Domain.extractDomain(contractType))) {
            if (bytecodeRepository.getContractTypeOwner(contractType) != address(0)) {
                stdstore.target(address(bytecodeRepository)).sig("getContractTypeOwner(bytes32)").with_key(contractType)
                    .checked_write(author.addr);
            }
            bytecodeRepository.allowPublicContract(bytecodeHash);
        } else {
            vm.prank(crossChainGovernance);
            instanceManager.configureGlobal(
                address(bytecodeRepository), abi.encodeCall(bytecodeRepository.allowSystemContract, (bytecodeHash))
            );
        }
    }

    function _deploy(bytes32 contractType, uint256 version, bytes memory constructorParams) internal returns (address) {
        return bytecodeRepository.deploy({
            contractType: contractType, version: version, constructorParams: constructorParams, salt: "GEARBOX"
        });
    }

    function _addPriceFeed(address priceFeed, uint32 stalenessPeriod, string memory name) internal {
        if (priceFeedStore.isKnownPriceFeed(priceFeed)) return;

        vm.prank(instanceOwner);
        instanceManager.configureLocal(
            address(priceFeedStore), abi.encodeCall(priceFeedStore.addPriceFeed, (priceFeed, stalenessPeriod, name))
        );
    }

    function _allowPriceFeed(address token, address priceFeed) internal {
        if (priceFeedStore.isAllowedPriceFeed(token, priceFeed)) return;

        vm.prank(instanceOwner);
        instanceManager.configureLocal(
            address(priceFeedStore), abi.encodeCall(priceFeedStore.allowPriceFeed, (token, priceFeed))
        );
    }

    // ------- //
    // MARKETS //
    // ------- //

    IMarketConfigurator public marketConfigurator;
    address public riskCurator;

    function _attachMarketConfigurator() internal {
        address configurator = vm.envOr("MARKET_CONFIGURATOR", address(0));
        if (configurator == address(0)) {
            configurator = _createMockMarketConfigurator();
            console.log("Using mock market configurator");
        } else {
            if (IMarketConfigurator(configurator).contractType() != "MARKET_CONFIGURATOR") {
                revert("MARKET_CONFIGURATOR is not a market configurator");
            }
            if (!bytecodeRepository.isDeployedFromRepository(configurator)) {
                revert("Market configurator is not deployed from repository");
            }
            console.log("Attached to market configurator", configurator);
        }
        marketConfigurator = IMarketConfigurator(configurator);
        riskCurator = marketConfigurator.admin();
    }

    function _createMockMarketConfigurator() internal returns (address configurator) {
        address curator = makeAddr("MockCurator");
        vm.prank(curator);
        configurator = marketConfiguratorFactory.createMarketConfigurator({
            emergencyAdmin: address(0), adminFeeTreasury: address(0), curatorName: "MockCurator", deployGovernor: false
        });
    }

    function _createMockMarket(address underlying, address priceFeed) internal returns (address pool) {
        string memory name = string.concat("Mock Diesel ", ERC20(underlying).name());
        string memory symbol = string.concat("md", ERC20(underlying).symbol());

        deal({token: underlying, to: address(marketConfigurator), give: 1e5});

        pool = marketConfigurator.previewCreateMarket({
            minorVersion: 3_10, underlying: underlying, name: name, symbol: symbol
        });

        vm.prank(riskCurator);
        marketConfigurator.createMarket({
            minorVersion: 3_10,
            underlying: underlying,
            name: name,
            symbol: symbol,
            interestRateModelParams: DeployParams({
                postfix: "LINEAR", salt: "GEARBOX", constructorParams: abi.encode(5000, 9000, 0, 100, 200, 700, false)
            }),
            rateKeeperParams: DeployParams({
                postfix: "TUMBLER", salt: "GEARBOX", constructorParams: abi.encode(pool, 1 days)
            }),
            lossPolicyParams: DeployParams({
                postfix: "ALIASED", salt: "GEARBOX", constructorParams: abi.encode(pool, ADDRESS_PROVIDER)
            }),
            underlyingPriceFeed: priceFeed
        });
    }

    function _createMockCreditSuite(address pool, uint128 minDebt, uint128 maxDebt, uint256 debtLimit)
        internal
        returns (address creditManager)
    {
        address underlying = ERC4626(pool).asset();
        string memory name = string.concat("Mock ", ERC20(underlying).symbol(), " Credit Suite");

        vm.startPrank(riskCurator);
        creditManager = marketConfigurator.createCreditSuite({
            minorVersion: 3_10,
            pool: pool,
            encdodedParams: abi.encode(
                CreditManagerParams({
                    maxEnabledTokens: 2,
                    feeInterest: 50_00,
                    feeLiquidation: 100,
                    liquidationPremium: 100,
                    feeLiquidationExpired: 100,
                    liquidationPremiumExpired: 100,
                    minDebt: minDebt,
                    maxDebt: maxDebt,
                    name: name,
                    accountFactoryParams: DeployParams({
                        postfix: "DEFAULT", salt: "GEARBOX", constructorParams: abi.encode(ADDRESS_PROVIDER)
                    })
                }),
                CreditFacadeParams({degenNFT: address(0), expirable: false, migrateBotList: false})
            )
        });

        if (debtLimit != 0) {
            marketConfigurator.configurePool(
                pool, abi.encodeCall(IPoolConfigureActions.setCreditManagerDebtLimit, (creditManager, debtLimit))
            );
        }
        vm.stopPrank();
    }

    struct TokenConfig {
        address token;
        address priceFeed;
        address reservePriceFeed;
        uint96 quotaLimit;
        uint16 quotaRate;
    }

    function _addToken(address pool, TokenConfig memory config) internal {
        vm.startPrank(riskCurator);

        marketConfigurator.addToken({pool: pool, token: config.token, priceFeed: config.priceFeed});

        if (config.reservePriceFeed != address(0)) {
            marketConfigurator.configurePriceOracle(
                pool,
                abi.encodeCall(
                    IPriceOracleConfigureActions.setReservePriceFeed, (config.token, config.reservePriceFeed)
                )
            );
        }
        if (config.quotaLimit != 0) {
            marketConfigurator.configurePool(
                pool, abi.encodeCall(IPoolConfigureActions.setTokenLimit, (config.token, config.quotaLimit))
            );
        }
        if (config.quotaRate != 0) {
            marketConfigurator.configureRateKeeper(
                pool, abi.encodeCall(ITumblerV3.setRate, (config.token, config.quotaRate))
            );
        }

        vm.stopPrank();
    }

    function _addCollateralToken(address creditManager, address token, uint16 lt) internal {
        vm.prank(riskCurator);
        marketConfigurator.configureCreditSuite(
            creditManager, abi.encodeCall(ICreditConfigureActions.addCollateralToken, (token, lt))
        );
    }

    function _allowAdapter(address creditManager, bytes32 postfix, bytes memory constructorParams) internal {
        vm.prank(riskCurator);
        marketConfigurator.configureCreditSuite(
            creditManager,
            abi.encodeCall(
                ICreditConfigureActions.allowAdapter,
                (DeployParams({postfix: postfix, salt: "GEARBOX", constructorParams: constructorParams}))
            )
        );
    }

    function _configureAdapter(address creditManager, address targetContract, bytes memory data) internal {
        vm.prank(riskCurator);
        marketConfigurator.configureCreditSuite(
            creditManager, abi.encodeCall(ICreditConfigureActions.configureAdapterFor, (targetContract, data))
        );
    }
}
