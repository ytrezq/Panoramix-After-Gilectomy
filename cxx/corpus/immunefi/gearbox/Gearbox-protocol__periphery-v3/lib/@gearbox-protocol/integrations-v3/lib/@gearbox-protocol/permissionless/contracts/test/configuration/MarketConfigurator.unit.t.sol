// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ConfigurationTestHelper} from "./ConfigurationTestHelper.sol";
import {MarketConfigurator} from "../../market/MarketConfigurator.sol";
import {IMarketConfigurator, DeployParams, MarketFactories} from "../../interfaces/IMarketConfigurator.sol";
import {MarketConfiguratorFactory} from "../../instance/MarketConfiguratorFactory.sol";
import {IACL} from "../../interfaces/IACL.sol";
import {IContractsRegister} from "../../interfaces/IContractsRegister.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {IGovernor} from "../../interfaces/IGovernor.sol";
import {IBytecodeRepository} from "../../interfaces/IBytecodeRepository.sol";
import {GeneralMock} from "@gearbox-protocol/core-v3/contracts/test/mocks/GeneralMock.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {PoolFactory} from "../../factories/PoolFactory.sol";
import {IMarketFactory} from "../../interfaces/factories/IMarketFactory.sol";
import {IPriceOracleV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPriceOracleV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IGaugeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IGaugeV3.sol";
import {RateKeeperFactory} from "../../factories/RateKeeperFactory.sol";
import {IRateKeeper} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IRateKeeper.sol";
import {IAccountFactory} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IAccountFactory.sol";
import {CreditManagerParams, CreditFacadeParams} from "../../interfaces/factories/ICreditConfigureActions.sol";
import {CreditFactory} from "../../factories/CreditFactory.sol";
import {ICreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditConfiguratorV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IPriceOracleFactory} from "../../interfaces/factories/IPriceOracleFactory.sol";
import {IPriceFeedStore} from "../../interfaces/IPriceFeedStore.sol";
import {MockPriceOraclePatch} from "../mocks/MockPriceOraclePatch.sol";
import {CrossChainCall} from "../helpers/GlobalSetup.sol";

import {
    AP_ACL,
    AP_CONTRACTS_REGISTER,
    AP_GOVERNOR,
    AP_MARKET_CONFIGURATOR,
    AP_TREASURY,
    AP_TREASURY_SPLITTER,
    AP_BYTECODE_REPOSITORY,
    AP_MARKET_CONFIGURATOR_FACTORY,
    AP_PRICE_ORACLE_FACTORY,
    AP_POOL_FACTORY,
    AP_CREDIT_FACTORY,
    AP_INTEREST_RATE_MODEL_FACTORY,
    AP_RATE_KEEPER_FACTORY,
    AP_LOSS_POLICY_FACTORY,
    AP_PRICE_ORACLE,
    NO_VERSION_CONTROL,
    ROLE_PAUSABLE_ADMIN,
    ROLE_UNPAUSABLE_ADMIN
} from "../../libraries/ContractLiterals.sol";

contract MarketConfiguratorUnitTest is ConfigurationTestHelper {
    address public mcf;
    address public treasury;
    string constant CURATOR_NAME = "Test Curator";

    address lossPolicy;
    address priceOracle;
    address poolFactory;
    address creditFactory;
    address priceOracleFactory;
    address interestRateModelFactory;
    address rateKeeperFactory;
    address lossPolicyFactory;
    address gearStaking;

    function setUp() public override {
        super.setUp();
        mcf = IAddressProvider(addressProvider).getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL);
        poolFactory = IAddressProvider(addressProvider).getAddressOrRevert(AP_POOL_FACTORY, 3_10);
        creditFactory = IAddressProvider(addressProvider).getAddressOrRevert(AP_CREDIT_FACTORY, 3_10);
        priceOracleFactory = IAddressProvider(addressProvider).getAddressOrRevert(AP_PRICE_ORACLE_FACTORY, 3_10);
        interestRateModelFactory =
            IAddressProvider(addressProvider).getAddressOrRevert(AP_INTEREST_RATE_MODEL_FACTORY, 3_10);
        rateKeeperFactory = IAddressProvider(addressProvider).getAddressOrRevert(AP_RATE_KEEPER_FACTORY, 3_11);
        lossPolicyFactory = IAddressProvider(addressProvider).getAddressOrRevert(AP_LOSS_POLICY_FACTORY, 3_10);
        gearStaking = RateKeeperFactory(rateKeeperFactory).gearStaking();
        vm.mockCall(gearStaking, abi.encodeWithSignature("getCurrentEpoch()"), abi.encode(62));
        priceOracle = IContractsRegister(marketConfigurator.contractsRegister()).getPriceOracle(address(pool));
        lossPolicy = IContractsRegister(marketConfigurator.contractsRegister()).getLossPolicy(address(pool));
    }

    /// @notice Tests constructor deployment with governor, without treasury
    function test_MC_01_constructor_with_governor() public {
        // Compute future MC address
        address expectedMC = IBytecodeRepository(bytecodeRepository).computeAddress(
            AP_MARKET_CONFIGURATOR,
            3_10,
            abi.encode(addressProvider, admin, emergencyAdmin, address(0), CURATOR_NAME, true),
            bytes32(bytes20(admin)),
            mcf
        );

        // Compute future governor address
        address expectedGovernor = IBytecodeRepository(bytecodeRepository).computeAddress(
            AP_GOVERNOR, 3_10, abi.encode(admin, emergencyAdmin, 1 days, false), bytes32(0), expectedMC
        );

        // Compute future ACL address
        address expectedACL = IBytecodeRepository(bytecodeRepository).computeAddress(
            AP_ACL, 3_10, abi.encode(expectedMC), bytes32(0), expectedMC
        );

        // Expect governor deployment
        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (AP_GOVERNOR, 3_10, abi.encode(admin, emergencyAdmin, 1 days, false), bytes32(0))
            )
        );

        // Expect ACL deployment
        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(IBytecodeRepository.deploy, (AP_ACL, 3_10, abi.encode(expectedMC), bytes32(0)))
        );

        // Expect ContractsRegister deployment
        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy, (AP_CONTRACTS_REGISTER, 3_10, abi.encode(expectedACL), bytes32(0))
            )
        );

        vm.prank(admin);
        address mc = MarketConfiguratorFactory(mcf).createMarketConfigurator(
            emergencyAdmin,
            address(0),
            CURATOR_NAME,
            true // deploy governor
        );

        assertEq(mc, expectedMC, "Incorrect market configurator address");

        // Verify governor and admin setup
        assertEq(MarketConfigurator(mc).admin(), IGovernor(expectedGovernor).timeLock(), "Incorrect admin");
        assertEq(MarketConfigurator(mc).emergencyAdmin(), emergencyAdmin, "Incorrect emergency admin");

        // Verify treasury setup
        assertEq(
            MarketConfigurator(mc).treasury(),
            IAddressProvider(addressProvider).getAddressOrRevert(AP_TREASURY, NO_VERSION_CONTROL),
            "Incorrect treasury"
        );

        // Verify roles
        assertTrue(
            IACL(MarketConfigurator(mc).acl()).hasRole(ROLE_PAUSABLE_ADMIN, mc),
            "Market configurator must have pausable admin role"
        );
        assertTrue(
            IACL(MarketConfigurator(mc).acl()).hasRole(ROLE_UNPAUSABLE_ADMIN, mc),
            "Market configurator must have unpausable admin role"
        );
    }

    /// @notice Tests constructor deployment without governor, with treasury
    function test_MC_02_constructor_without_governor() public {
        address adminFeeTreasury = makeAddr("ADMIN_FEE_TREASURY");

        // Compute future MC address
        address expectedMC = IBytecodeRepository(bytecodeRepository).computeAddress(
            AP_MARKET_CONFIGURATOR,
            3_10,
            abi.encode(addressProvider, admin, emergencyAdmin, adminFeeTreasury, CURATOR_NAME, false),
            bytes32(bytes20(admin)),
            mcf
        );

        // Compute future ACL address
        address expectedACL = IBytecodeRepository(bytecodeRepository).computeAddress(
            AP_ACL, 3_10, abi.encode(expectedMC), bytes32(0), expectedMC
        );

        // Expect ACL deployment
        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(IBytecodeRepository.deploy, (AP_ACL, 3_10, abi.encode(expectedMC), bytes32(0)))
        );

        // Expect ContractsRegister deployment
        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy, (AP_CONTRACTS_REGISTER, 3_10, abi.encode(expectedACL), bytes32(0))
            )
        );

        // Expect TreasurySplitter deployment
        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (AP_TREASURY_SPLITTER, 3_10, abi.encode(addressProvider, admin, adminFeeTreasury), bytes32(0))
            )
        );

        vm.prank(admin);
        address mc = MarketConfiguratorFactory(mcf).createMarketConfigurator(
            emergencyAdmin,
            adminFeeTreasury,
            CURATOR_NAME,
            false // don't deploy governor
        );

        assertEq(mc, expectedMC, "Incorrect market configurator address");

        // Verify admin setup
        assertEq(MarketConfigurator(mc).admin(), admin, "Incorrect admin");
        assertEq(MarketConfigurator(mc).emergencyAdmin(), emergencyAdmin, "Incorrect emergency admin");

        // Verify treasury deployment
        address expectedTreasury = MarketConfigurator(mc).treasury();
        assertTrue(expectedTreasury.code.length > 0, "Treasury must be deployed");

        // Verify roles
        assertTrue(
            IACL(MarketConfigurator(mc).acl()).hasRole(ROLE_PAUSABLE_ADMIN, mc),
            "Market configurator must have pausable admin role"
        );
        assertTrue(
            IACL(MarketConfigurator(mc).acl()).hasRole(ROLE_UNPAUSABLE_ADMIN, mc),
            "Market configurator must have unpausable admin role"
        );
    }

    /// @notice Tests setting emergency admin
    function test_MC_04_setEmergencyAdmin() public {
        address newEmergencyAdmin = makeAddr("NEW_EMERGENCY_ADMIN");

        // Test that only admin can set emergency admin
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.setEmergencyAdmin(newEmergencyAdmin);

        // Test successful emergency admin change
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.SetEmergencyAdmin(newEmergencyAdmin);
        marketConfigurator.setEmergencyAdmin(newEmergencyAdmin);

        assertEq(marketConfigurator.emergencyAdmin(), newEmergencyAdmin, "Emergency admin not updated");
    }

    /// @notice Tests granting roles
    function test_MC_05_grantRole() public {
        bytes32 role = keccak256("TEST_ROLE");
        address account = makeAddr("ACCOUNT");

        // Test that only admin can grant roles
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.grantRole(role, account);

        // Test successful role grant
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.GrantRole(role, account);
        marketConfigurator.grantRole(role, account);

        assertTrue(IACL(marketConfigurator.acl()).hasRole(role, account), "Role not granted");
    }

    /// @notice Tests revoking roles
    function test_MC_06_revokeRole() public {
        bytes32 role = keccak256("TEST_ROLE");
        address account = makeAddr("ACCOUNT");

        // Grant role first
        vm.prank(admin);
        marketConfigurator.grantRole(role, account);

        // Test that only admin can revoke roles
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.revokeRole(role, account);

        // Test successful role revocation
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.RevokeRole(role, account);
        marketConfigurator.revokeRole(role, account);

        assertFalse(IACL(marketConfigurator.acl()).hasRole(role, account), "Role not revoked");
    }

    /// @notice Tests emergency role revocation
    function test_MC_07_emergencyRevokeRole() public {
        bytes32 role = keccak256("TEST_ROLE");
        address account = makeAddr("ACCOUNT");

        // Grant role first
        vm.prank(admin);
        marketConfigurator.grantRole(role, account);

        // Test that only emergency admin can emergency revoke roles
        vm.expectRevert(
            abi.encodeWithSelector(IMarketConfigurator.CallerIsNotEmergencyAdminException.selector, address(this))
        );
        marketConfigurator.emergencyRevokeRole(role, account);

        // Test successful emergency role revocation
        vm.prank(emergencyAdmin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.EmergencyRevokeRole(role, account);
        marketConfigurator.emergencyRevokeRole(role, account);

        assertFalse(IACL(marketConfigurator.acl()).hasRole(role, account), "Role not revoked");
    }

    /// @notice Tests periphery contract management
    function test_MC_08_periphery_contracts() public {
        bytes32 domain = bytes32("TEST_DOMAIN");
        address peripheryContract = makeAddr("PERIPHERY_CONTRACT");

        // Mock the periphery contract to return correct domain
        vm.mockCall(
            peripheryContract,
            abi.encodeWithSignature("contractType()"),
            abi.encode(bytes32(abi.encodePacked(domain, bytes16(0))))
        );

        // Mock bytecode repository to recognize the contract
        vm.mockCall(
            bytecodeRepository,
            abi.encodeWithSignature("isDeployedFromRepository(address)", peripheryContract),
            abi.encode(true)
        );

        // Test that only admin can add periphery contracts
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.addPeripheryContract(peripheryContract);

        // Test successful periphery contract addition
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AddPeripheryContract(domain, peripheryContract);
        marketConfigurator.addPeripheryContract(peripheryContract);

        // Verify contract was added
        assertTrue(marketConfigurator.isPeripheryContract(domain, peripheryContract), "Contract not added");
        address[] memory contracts = marketConfigurator.getPeripheryContracts(domain);
        assertEq(contracts.length, 1, "Incorrect number of contracts");
        assertEq(contracts[0], peripheryContract, "Incorrect contract address");

        // Test adding same contract again (no event)
        vm.prank(admin);
        marketConfigurator.addPeripheryContract(peripheryContract);

        // Test that only admin can remove periphery contracts
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.removePeripheryContract(peripheryContract);

        // Test successful periphery contract removal
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.RemovePeripheryContract(domain, peripheryContract);
        marketConfigurator.removePeripheryContract(peripheryContract);

        // Verify contract was removed
        assertFalse(marketConfigurator.isPeripheryContract(domain, peripheryContract), "Contract not removed");
        contracts = marketConfigurator.getPeripheryContracts(domain);
        assertEq(contracts.length, 0, "Contract list not empty");

        // Test removing non-existent contract (no event)
        vm.prank(admin);
        marketConfigurator.removePeripheryContract(peripheryContract);

        // Test adding contract that's not in bytecode repository
        vm.mockCall(
            bytecodeRepository,
            abi.encodeWithSignature("isDeployedFromRepository(address)", peripheryContract),
            abi.encode(false)
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IMarketConfigurator.IncorrectPeripheryContractException.selector, peripheryContract)
        );
        marketConfigurator.addPeripheryContract(peripheryContract);

        // Test adding contract that doesn't implement IVersion
        address invalidContract = address(new GeneralMock());
        vm.mockCall(
            bytecodeRepository,
            abi.encodeWithSignature("isDeployedFromRepository(address)", peripheryContract),
            abi.encode(true)
        );
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IMarketConfigurator.IncorrectPeripheryContractException.selector, invalidContract)
        );
        marketConfigurator.addPeripheryContract(invalidContract);
    }

    /// @notice Tests factory authorization
    function test_MC_09_authorizeFactory() public {
        address factory = makeAddr("FACTORY");
        address suite = makeAddr("SUITE");
        address target = makeAddr("TARGET");

        // Test that only self can authorize factories
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotSelfException.selector, address(this)));
        marketConfigurator.authorizeFactory(factory, suite, target);

        // Test successful factory authorization
        vm.prank(address(marketConfigurator));
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(factory, suite, target);
        marketConfigurator.authorizeFactory(factory, suite, target);

        // Verify factory was authorized
        assertEq(marketConfigurator.getAuthorizedFactory(target), factory, "Factory not authorized");
        address[] memory targets = marketConfigurator.getFactoryTargets(factory, suite);
        assertEq(targets.length, 1, "Incorrect number of targets");
        assertEq(targets[0], target, "Incorrect target address");

        // Test no-op authorizing already authorized target
        vm.prank(address(marketConfigurator));
        marketConfigurator.authorizeFactory(factory, suite, target);

        // Test authorizing already authorized target by wrong factory
        address wrongFactory = makeAddr("WRONG_FACTORY");
        vm.prank(address(marketConfigurator));
        vm.expectRevert(
            abi.encodeWithSelector(IMarketConfigurator.UnauthorizedFactoryException.selector, wrongFactory, target)
        );
        marketConfigurator.authorizeFactory(wrongFactory, suite, target);
    }

    /// @notice Tests factory unauthorization
    function test_MC_10_unauthorizeFactory() public {
        address factory = makeAddr("FACTORY");
        address suite = makeAddr("SUITE");
        address target = makeAddr("TARGET");

        // Authorize factory first
        vm.prank(address(marketConfigurator));
        marketConfigurator.authorizeFactory(factory, suite, target);

        // Test that only self can unauthorize factories
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotSelfException.selector, address(this)));
        marketConfigurator.unauthorizeFactory(factory, suite, target);

        // Test unauthorizing target by wrong factory
        address wrongFactory = makeAddr("WRONG_FACTORY");
        vm.prank(address(marketConfigurator));
        vm.expectRevert(
            abi.encodeWithSelector(IMarketConfigurator.UnauthorizedFactoryException.selector, wrongFactory, target)
        );
        marketConfigurator.unauthorizeFactory(wrongFactory, suite, target);

        // Test successful factory unauthorized
        vm.prank(address(marketConfigurator));
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(factory, suite, target);
        marketConfigurator.unauthorizeFactory(factory, suite, target);

        // Verify factory was unauthorized
        assertEq(marketConfigurator.getAuthorizedFactory(target), address(0), "Factory not unauthorized");
        address[] memory targets = marketConfigurator.getFactoryTargets(factory, suite);
        assertEq(targets.length, 0, "Target list not empty");

        // Test no-op unauthorizing already unauthorized target
        vm.prank(address(marketConfigurator));
        marketConfigurator.unauthorizeFactory(factory, suite, target);
    }

    /// @notice Tests pool factory upgrade function
    function test_MC_11_upgradePoolFactory() public {
        // Test that only admin can upgrade factories
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.upgradePoolFactory(address(pool));

        // Test upgrading pool factory
        address oldFactory = marketConfigurator.getMarketFactories(address(pool)).poolFactory;
        address newFactory = makeAddr("NEW_FACTORY");
        address quotaKeeper = IPoolV3(pool).poolQuotaKeeper();

        vm.mockCall(newFactory, abi.encodeWithSignature("version()"), abi.encode(3_11));
        vm.mockCall(newFactory, abi.encodeWithSignature("contractType()"), abi.encode(bytes32("POOL_FACTORY")));

        vm.prank(Ownable(addressProvider).owner());
        IAddressProvider(addressProvider).setAddress("POOL_FACTORY", newFactory, true);

        // Expect factory authorization changes
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(oldFactory, address(pool), address(pool));
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(newFactory, address(pool), address(pool));
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(oldFactory, address(pool), quotaKeeper);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(newFactory, address(pool), quotaKeeper);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UpgradePoolFactory(address(pool), newFactory);
        marketConfigurator.upgradePoolFactory(address(pool));

        // Verify factory was upgraded and authorizations changed
        assertEq(
            marketConfigurator.getMarketFactories(address(pool)).poolFactory, newFactory, "Pool factory not upgraded"
        );
        assertEq(
            marketConfigurator.getAuthorizedFactory(address(pool)), newFactory, "Pool factory authorization not updated"
        );
        assertEq(
            marketConfigurator.getAuthorizedFactory(quotaKeeper),
            newFactory,
            "QuotaKeeper factory authorization not updated"
        );

        // Test upgrading from patch version
        address patchFactory = makeAddr("PATCH_FACTORY");
        vm.mockCall(patchFactory, abi.encodeWithSignature("version()"), abi.encode(3_12));
        vm.mockCall(patchFactory, abi.encodeWithSignature("contractType()"), abi.encode(bytes32("POOL_FACTORY")));

        vm.prank(Ownable(addressProvider).owner());
        IAddressProvider(addressProvider).setAddress("POOL_FACTORY", patchFactory, true);

        vm.prank(admin);
        marketConfigurator.upgradePoolFactory(address(pool));

        assertEq(
            marketConfigurator.getMarketFactories(address(pool)).poolFactory, patchFactory, "Pool factory not upgraded"
        );
    }

    /// @notice Tests credit factory upgrade function
    function test_MC_12_upgradeCreditFactory() public {
        // Test that only admin can upgrade factories
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.upgradeCreditFactory(address(creditManager));

        // Test upgrading credit factory
        address oldFactory = marketConfigurator.getCreditFactory(address(creditManager));
        address newFactory = makeAddr("NEW_FACTORY");

        vm.mockCall(newFactory, abi.encodeWithSignature("version()"), abi.encode(3_11));
        vm.mockCall(newFactory, abi.encodeWithSignature("contractType()"), abi.encode(bytes32("CREDIT_FACTORY")));

        vm.prank(Ownable(addressProvider).owner());
        IAddressProvider(addressProvider).setAddress("CREDIT_FACTORY", newFactory, true);

        // Expect factory authorization changes
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(oldFactory, address(creditManager), address(creditConfigurator));
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(newFactory, address(creditManager), address(creditConfigurator));
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(oldFactory, address(creditManager), address(creditFacade));
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(newFactory, address(creditManager), address(creditFacade));

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UpgradeCreditFactory(address(creditManager), newFactory);
        marketConfigurator.upgradeCreditFactory(address(creditManager));

        // Verify factory was upgraded and authorizations changed
        assertEq(marketConfigurator.getCreditFactory(address(creditManager)), newFactory, "Credit factory not upgraded");
        assertEq(
            marketConfigurator.getAuthorizedFactory(address(creditConfigurator)),
            newFactory,
            "Configurator factory authorization not updated"
        );
        assertEq(
            marketConfigurator.getAuthorizedFactory(address(creditFacade)),
            newFactory,
            "Facade factory authorization not updated"
        );

        // Test upgrading from patch version
        address patchFactory = makeAddr("PATCH_FACTORY");
        vm.mockCall(patchFactory, abi.encodeWithSignature("version()"), abi.encode(3_12));
        vm.mockCall(patchFactory, abi.encodeWithSignature("contractType()"), abi.encode(bytes32("CREDIT_FACTORY")));

        vm.prank(Ownable(addressProvider).owner());
        IAddressProvider(addressProvider).setAddress("CREDIT_FACTORY", patchFactory, true);

        vm.prank(admin);
        marketConfigurator.upgradeCreditFactory(address(creditManager));

        assertEq(
            marketConfigurator.getCreditFactory(address(creditManager)), patchFactory, "Credit factory not upgraded"
        );
    }

    /// @notice Tests price oracle factory upgrade function
    function test_MC_13_upgradePriceOracleFactory() public {
        // Test that only admin can upgrade factories
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.upgradePriceOracleFactory(address(pool));

        // Test upgrading price oracle factory
        address oldFactory = marketConfigurator.getMarketFactories(address(pool)).priceOracleFactory;
        address newFactory = makeAddr("NEW_FACTORY");

        vm.mockCall(newFactory, abi.encodeWithSignature("version()"), abi.encode(3_11));
        vm.mockCall(newFactory, abi.encodeWithSignature("contractType()"), abi.encode(bytes32("PRICE_ORACLE_FACTORY")));

        vm.prank(Ownable(addressProvider).owner());
        IAddressProvider(addressProvider).setAddress("PRICE_ORACLE_FACTORY", newFactory, true);

        // Expect factory authorization changes
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(oldFactory, address(pool), priceOracle);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(newFactory, address(pool), priceOracle);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UpgradePriceOracleFactory(address(pool), newFactory);
        marketConfigurator.upgradePriceOracleFactory(address(pool));

        // Verify factory was upgraded and authorizations changed
        assertEq(
            marketConfigurator.getMarketFactories(address(pool)).priceOracleFactory,
            newFactory,
            "Price oracle factory not upgraded"
        );
        assertEq(
            marketConfigurator.getAuthorizedFactory(priceOracle),
            newFactory,
            "Price oracle factory authorization not updated"
        );

        // Test upgrading from patch version
        address patchFactory = makeAddr("PATCH_FACTORY");
        vm.mockCall(patchFactory, abi.encodeWithSignature("version()"), abi.encode(3_12));
        vm.mockCall(
            patchFactory, abi.encodeWithSignature("contractType()"), abi.encode(bytes32("PRICE_ORACLE_FACTORY"))
        );

        vm.prank(Ownable(addressProvider).owner());
        IAddressProvider(addressProvider).setAddress("PRICE_ORACLE_FACTORY", patchFactory, true);

        vm.prank(admin);
        marketConfigurator.upgradePriceOracleFactory(address(pool));

        assertEq(
            marketConfigurator.getMarketFactories(address(pool)).priceOracleFactory,
            patchFactory,
            "Price oracle factory not upgraded"
        );
    }

    /// @notice Tests interest rate model factory upgrade function
    function test_MC_14_upgradeInterestRateModelFactory() public {
        // Test that only admin can upgrade factories
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.upgradeInterestRateModelFactory(address(pool));

        // Test upgrading interest rate model factory
        address oldFactory = marketConfigurator.getMarketFactories(address(pool)).interestRateModelFactory;
        address newFactory = makeAddr("NEW_FACTORY");
        address interestRateModel = IPoolV3(pool).interestRateModel();

        vm.mockCall(newFactory, abi.encodeWithSignature("version()"), abi.encode(3_11));
        vm.mockCall(
            newFactory, abi.encodeWithSignature("contractType()"), abi.encode(bytes32("INTEREST_RATE_MODEL_FACTORY"))
        );

        vm.prank(Ownable(addressProvider).owner());
        IAddressProvider(addressProvider).setAddress("INTEREST_RATE_MODEL_FACTORY", newFactory, true);

        // Expect factory authorization changes
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(oldFactory, address(pool), interestRateModel);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(newFactory, address(pool), interestRateModel);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UpgradeInterestRateModelFactory(address(pool), newFactory);
        marketConfigurator.upgradeInterestRateModelFactory(address(pool));

        // Verify factory was upgraded and authorizations changed
        assertEq(
            marketConfigurator.getMarketFactories(address(pool)).interestRateModelFactory,
            newFactory,
            "Interest rate model factory not upgraded"
        );
        assertEq(
            marketConfigurator.getAuthorizedFactory(interestRateModel),
            newFactory,
            "Interest rate model factory authorization not updated"
        );

        // Test upgrading from patch version
        address patchFactory = makeAddr("PATCH_FACTORY");
        vm.mockCall(patchFactory, abi.encodeWithSignature("version()"), abi.encode(3_12));
        vm.mockCall(
            patchFactory, abi.encodeWithSignature("contractType()"), abi.encode(bytes32("INTEREST_RATE_MODEL_FACTORY"))
        );

        vm.prank(Ownable(addressProvider).owner());
        IAddressProvider(addressProvider).setAddress("INTEREST_RATE_MODEL_FACTORY", patchFactory, true);

        vm.prank(admin);
        marketConfigurator.upgradeInterestRateModelFactory(address(pool));

        assertEq(
            marketConfigurator.getMarketFactories(address(pool)).interestRateModelFactory,
            patchFactory,
            "Interest rate model factory not upgraded"
        );
    }

    /// @notice Tests rate keeper factory upgrade function
    function test_MC_15_upgradeRateKeeperFactory() public {
        // Test that only admin can upgrade factories
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.upgradeRateKeeperFactory(address(pool));

        // Test upgrading rate keeper factory
        address oldFactory = marketConfigurator.getMarketFactories(address(pool)).rateKeeperFactory;
        address newFactory = makeAddr("NEW_FACTORY");
        address quotaKeeper = IPoolV3(pool).poolQuotaKeeper();
        address rateKeeper = IPoolQuotaKeeperV3(quotaKeeper).gauge();

        vm.mockCall(newFactory, abi.encodeWithSignature("version()"), abi.encode(3_11));
        vm.mockCall(newFactory, abi.encodeWithSignature("contractType()"), abi.encode(bytes32("RATE_KEEPER_FACTORY")));

        vm.prank(Ownable(addressProvider).owner());
        IAddressProvider(addressProvider).setAddress("RATE_KEEPER_FACTORY", newFactory, true);

        // Expect factory authorization changes
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(oldFactory, address(pool), rateKeeper);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(newFactory, address(pool), rateKeeper);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UpgradeRateKeeperFactory(address(pool), newFactory);
        marketConfigurator.upgradeRateKeeperFactory(address(pool));

        // Verify factory was upgraded and authorizations changed
        assertEq(
            marketConfigurator.getMarketFactories(address(pool)).rateKeeperFactory,
            newFactory,
            "Rate keeper factory not upgraded"
        );
        assertEq(
            marketConfigurator.getAuthorizedFactory(rateKeeper),
            newFactory,
            "Rate keeper factory authorization not updated"
        );

        // Test upgrading from patch version
        address patchFactory = makeAddr("PATCH_FACTORY");
        vm.mockCall(patchFactory, abi.encodeWithSignature("version()"), abi.encode(3_12));
        vm.mockCall(patchFactory, abi.encodeWithSignature("contractType()"), abi.encode(bytes32("RATE_KEEPER_FACTORY")));

        vm.prank(Ownable(addressProvider).owner());
        IAddressProvider(addressProvider).setAddress("RATE_KEEPER_FACTORY", patchFactory, true);

        vm.prank(admin);
        marketConfigurator.upgradeRateKeeperFactory(address(pool));

        assertEq(
            marketConfigurator.getMarketFactories(address(pool)).rateKeeperFactory,
            patchFactory,
            "Rate keeper factory not upgraded"
        );
    }

    /// @notice Tests loss policy factory upgrade function
    function test_MC_16_upgradeLossPolicyFactory() public {
        // Test that only admin can upgrade factories
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.upgradeLossPolicyFactory(address(pool));

        // Test upgrading loss policy factory
        address oldFactory = marketConfigurator.getMarketFactories(address(pool)).lossPolicyFactory;
        address newFactory = makeAddr("NEW_FACTORY");

        vm.mockCall(newFactory, abi.encodeWithSignature("version()"), abi.encode(3_11));
        vm.mockCall(newFactory, abi.encodeWithSignature("contractType()"), abi.encode(bytes32("LOSS_POLICY_FACTORY")));

        vm.prank(Ownable(addressProvider).owner());
        IAddressProvider(addressProvider).setAddress("LOSS_POLICY_FACTORY", newFactory, true);

        // Expect factory authorization changes
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(oldFactory, address(pool), lossPolicy);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(newFactory, address(pool), lossPolicy);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UpgradeLossPolicyFactory(address(pool), newFactory);
        marketConfigurator.upgradeLossPolicyFactory(address(pool));

        // Verify factory was upgraded and authorizations changed
        assertEq(
            marketConfigurator.getMarketFactories(address(pool)).lossPolicyFactory,
            newFactory,
            "Loss policy factory not upgraded"
        );
        assertEq(
            marketConfigurator.getAuthorizedFactory(lossPolicy),
            newFactory,
            "Loss policy factory authorization not updated"
        );

        // Test upgrading from patch version
        address patchFactory = makeAddr("PATCH_FACTORY");
        vm.mockCall(patchFactory, abi.encodeWithSignature("version()"), abi.encode(3_12));
        vm.mockCall(patchFactory, abi.encodeWithSignature("contractType()"), abi.encode(bytes32("LOSS_POLICY_FACTORY")));

        vm.prank(Ownable(addressProvider).owner());
        IAddressProvider(addressProvider).setAddress("LOSS_POLICY_FACTORY", patchFactory, true);

        vm.prank(admin);
        marketConfigurator.upgradeLossPolicyFactory(address(pool));

        assertEq(
            marketConfigurator.getMarketFactories(address(pool)).lossPolicyFactory,
            patchFactory,
            "Loss policy factory not upgraded"
        );
    }

    /// @notice Tests market creation
    function test_MC_17_createMarket() public {
        IERC20(USDC).transfer(address(marketConfigurator), 1e6);

        // Test that only admin can create markets
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.createMarket(
            3_10,
            USDC,
            "TEST",
            "TEST",
            DeployParams({
                postfix: "LINEAR",
                salt: bytes32(0),
                constructorParams: abi.encode(100, 200, 100, 100, 200, 300, false)
            }),
            DeployParams({postfix: "TUMBLER", salt: bytes32(0), constructorParams: abi.encode(address(0), 7 days)}),
            DeployParams({postfix: "MOCK", salt: bytes32(0), constructorParams: abi.encode(address(0), addressProvider)}),
            CHAINLINK_USDC_USD
        );

        // Compute expected addresses
        address expectedPool = IBytecodeRepository(bytecodeRepository).computeAddress(
            "POOL",
            3_10,
            abi.encode(
                marketConfigurator.acl(),
                marketConfigurator.contractsRegister(),
                USDC,
                marketConfigurator.treasury(),
                PoolFactory(poolFactory).defaultInterestRateModel(),
                type(uint256).max,
                "TEST",
                "TEST"
            ),
            bytes32(bytes20(address(marketConfigurator))),
            poolFactory
        );

        address expectedQuotaKeeper = IBytecodeRepository(bytecodeRepository).computeAddress(
            "POOL_QUOTA_KEEPER",
            3_10,
            abi.encode(expectedPool),
            bytes32(bytes20(address(marketConfigurator))),
            poolFactory
        );

        address expectedPriceOracle = IBytecodeRepository(bytecodeRepository).computeAddress(
            "PRICE_ORACLE",
            3_10,
            abi.encode(marketConfigurator.acl()),
            bytes32(bytes20(expectedPool)),
            priceOracleFactory
        );

        address expectedIRM = IBytecodeRepository(bytecodeRepository).computeAddress(
            "IRM::LINEAR",
            3_10,
            abi.encode(100, 200, 100, 100, 200, 300, false),
            keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator)),
            interestRateModelFactory
        );

        address expectedRateKeeper = IBytecodeRepository(bytecodeRepository).computeAddress(
            "RATE_KEEPER::GAUGE",
            3_10,
            abi.encode(expectedPool, gearStaking),
            keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator)),
            rateKeeperFactory
        );

        address expectedLossPolicy = IBytecodeRepository(bytecodeRepository).computeAddress(
            "LOSS_POLICY::MOCK",
            3_10,
            abi.encode(expectedPool, addressProvider),
            keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator)),
            lossPolicyFactory
        );
        {
            bytes memory poolParams = abi.encode(
                marketConfigurator.acl(),
                marketConfigurator.contractsRegister(),
                USDC,
                marketConfigurator.treasury(),
                PoolFactory(poolFactory).defaultInterestRateModel(),
                type(uint256).max,
                "TEST",
                "TEST"
            );

            address acl = marketConfigurator.acl();

            // Expect contract deployments
            vm.expectCall(
                bytecodeRepository,
                abi.encodeCall(
                    IBytecodeRepository.deploy,
                    ("POOL", 3_10, poolParams, bytes32(bytes20(address(marketConfigurator))))
                )
            );

            vm.expectCall(
                bytecodeRepository,
                abi.encodeCall(
                    IBytecodeRepository.deploy,
                    ("POOL_QUOTA_KEEPER", 3_10, abi.encode(expectedPool), bytes32(bytes20(address(marketConfigurator))))
                )
            );

            vm.expectCall(
                bytecodeRepository,
                abi.encodeCall(
                    IBytecodeRepository.deploy, ("PRICE_ORACLE", 3_10, abi.encode(acl), bytes32(bytes20(expectedPool)))
                )
            );
        }

        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (
                    "IRM::LINEAR",
                    3_10,
                    abi.encode(100, 200, 100, 100, 200, 300, false),
                    keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator))
                )
            )
        );

        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (
                    "RATE_KEEPER::GAUGE",
                    3_10,
                    abi.encode(expectedPool, gearStaking),
                    keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator))
                )
            )
        );

        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (
                    "LOSS_POLICY::MOCK",
                    3_10,
                    abi.encode(expectedPool, addressProvider),
                    keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator))
                )
            )
        );

        // Expect factory hooks
        vm.expectCall(
            poolFactory,
            abi.encodeCall(
                IMarketFactory.onCreateMarket,
                (
                    expectedPool,
                    expectedPriceOracle,
                    expectedIRM,
                    expectedRateKeeper,
                    expectedLossPolicy,
                    CHAINLINK_USDC_USD
                )
            )
        );

        // Expect hook calls from PoolFactory
        vm.expectCall(expectedPool, abi.encodeCall(IPoolV3.setInterestRateModel, (expectedIRM)));
        vm.expectCall(expectedQuotaKeeper, abi.encodeCall(IPoolQuotaKeeperV3.setGauge, (expectedRateKeeper)));

        // Expect hook calls from PriceOracleFactory
        vm.expectCall(
            expectedPriceOracle, abi.encodeCall(IPriceOracleV3.setPriceFeed, (USDC, CHAINLINK_USDC_USD, 1 days))
        );

        vm.expectCall(expectedRateKeeper, abi.encodeCall(IGaugeV3.setFrozenEpoch, (false)));

        vm.expectCall(
            priceOracleFactory,
            abi.encodeCall(
                IMarketFactory.onCreateMarket,
                (
                    expectedPool,
                    expectedPriceOracle,
                    expectedIRM,
                    expectedRateKeeper,
                    expectedLossPolicy,
                    CHAINLINK_USDC_USD
                )
            )
        );
        vm.expectCall(
            interestRateModelFactory,
            abi.encodeCall(
                IMarketFactory.onCreateMarket,
                (
                    expectedPool,
                    expectedPriceOracle,
                    expectedIRM,
                    expectedRateKeeper,
                    expectedLossPolicy,
                    CHAINLINK_USDC_USD
                )
            )
        );
        vm.expectCall(
            rateKeeperFactory,
            abi.encodeCall(
                IMarketFactory.onCreateMarket,
                (
                    expectedPool,
                    expectedPriceOracle,
                    expectedIRM,
                    expectedRateKeeper,
                    expectedLossPolicy,
                    CHAINLINK_USDC_USD
                )
            )
        );
        vm.expectCall(
            lossPolicyFactory,
            abi.encodeCall(
                IMarketFactory.onCreateMarket,
                (
                    expectedPool,
                    expectedPriceOracle,
                    expectedIRM,
                    expectedRateKeeper,
                    expectedLossPolicy,
                    CHAINLINK_USDC_USD
                )
            )
        );

        // Expect factory authorizations
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(poolFactory, expectedPool, expectedPool);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(poolFactory, expectedPool, expectedQuotaKeeper);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(priceOracleFactory, expectedPool, expectedPriceOracle);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(interestRateModelFactory, expectedPool, expectedIRM);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(rateKeeperFactory, expectedPool, expectedRateKeeper);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(lossPolicyFactory, expectedPool, expectedLossPolicy);

        // Create market
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.CreateMarket(
            expectedPool,
            expectedPriceOracle,
            expectedIRM,
            expectedRateKeeper,
            expectedLossPolicy,
            MarketFactories({
                poolFactory: poolFactory,
                priceOracleFactory: priceOracleFactory,
                interestRateModelFactory: interestRateModelFactory,
                rateKeeperFactory: rateKeeperFactory,
                lossPolicyFactory: lossPolicyFactory
            })
        );
        address newPool = marketConfigurator.createMarket(
            3_10,
            USDC,
            "TEST",
            "TEST",
            DeployParams({
                postfix: "LINEAR",
                salt: bytes32(uint256(1)),
                constructorParams: abi.encode(100, 200, 100, 100, 200, 300, false)
            }),
            DeployParams({
                postfix: "GAUGE",
                salt: bytes32(uint256(1)),
                constructorParams: abi.encode(expectedPool, gearStaking)
            }),
            DeployParams({
                postfix: "MOCK",
                salt: bytes32(uint256(1)),
                constructorParams: abi.encode(expectedPool, addressProvider)
            }),
            CHAINLINK_USDC_USD
        );

        assertEq(newPool, expectedPool, "Incorrect pool address");
    }

    /// @notice Tests market shutdown
    function test_MC_18_shutdownMarket() public {
        IERC20(USDC).transfer(address(marketConfigurator), 1e6);

        address expectedPool = IBytecodeRepository(bytecodeRepository).computeAddress(
            "POOL",
            3_10,
            abi.encode(
                marketConfigurator.acl(),
                marketConfigurator.contractsRegister(),
                USDC,
                marketConfigurator.treasury(),
                PoolFactory(poolFactory).defaultInterestRateModel(),
                type(uint256).max,
                "TEST",
                "TEST"
            ),
            bytes32(bytes20(address(marketConfigurator))),
            poolFactory
        );

        vm.prank(admin);
        address newPool = marketConfigurator.createMarket(
            3_10,
            USDC,
            "TEST",
            "TEST",
            DeployParams({
                postfix: "LINEAR",
                salt: bytes32(uint256(1)),
                constructorParams: abi.encode(100, 200, 100, 100, 200, 300, false)
            }),
            DeployParams({
                postfix: "GAUGE",
                salt: bytes32(uint256(1)),
                constructorParams: abi.encode(expectedPool, gearStaking)
            }),
            DeployParams({
                postfix: "MOCK",
                salt: bytes32(uint256(1)),
                constructorParams: abi.encode(expectedPool, addressProvider)
            }),
            CHAINLINK_USDC_USD
        );

        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.shutdownMarket(address(newPool));

        vm.expectCall(poolFactory, abi.encodeCall(IMarketFactory.onShutdownMarket, (address(newPool))));

        vm.expectCall(priceOracleFactory, abi.encodeCall(IMarketFactory.onShutdownMarket, (address(newPool))));

        vm.expectCall(interestRateModelFactory, abi.encodeCall(IMarketFactory.onShutdownMarket, (address(newPool))));

        vm.expectCall(rateKeeperFactory, abi.encodeCall(IMarketFactory.onShutdownMarket, (address(newPool))));

        vm.expectCall(lossPolicyFactory, abi.encodeCall(IMarketFactory.onShutdownMarket, (address(newPool))));

        vm.expectCall(
            marketConfigurator.contractsRegister(),
            abi.encodeCall(IContractsRegister.shutdownMarket, (address(newPool)))
        );

        address expectedRateKeeper = IPoolQuotaKeeperV3(IPoolV3(newPool).poolQuotaKeeper()).gauge();

        vm.expectCall(newPool, abi.encodeCall(IPoolV3.setTotalDebtLimit, (0)));
        vm.expectCall(expectedRateKeeper, abi.encodeCall(IGaugeV3.setFrozenEpoch, (true)));

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.ShutdownMarket(address(newPool));
        marketConfigurator.shutdownMarket(address(newPool));
    }

    /// @notice Tests adding token to market
    function test_MC_19_addToken() public {
        // Test that only admin can add tokens
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.addToken(address(pool), USDC, CHAINLINK_USDC_USD);

        address rateKeeper = IPoolQuotaKeeperV3(IPoolV3(pool).poolQuotaKeeper()).gauge();

        // Expect hook calls from PriceOracleFactory
        vm.expectCall(priceOracle, abi.encodeCall(IPriceOracleV3.setPriceFeed, (USDC, CHAINLINK_USDC_USD, 1 days)));

        // Expect hook calls from RateKeeperFactory
        vm.expectCall(rateKeeper, abi.encodeCall(IRateKeeper.addToken, (USDC)));

        // Expect factory hooks
        vm.expectCall(poolFactory, abi.encodeCall(IMarketFactory.onAddToken, (address(pool), USDC, CHAINLINK_USDC_USD)));

        vm.expectCall(
            priceOracleFactory, abi.encodeCall(IMarketFactory.onAddToken, (address(pool), USDC, CHAINLINK_USDC_USD))
        );
        vm.expectCall(
            interestRateModelFactory,
            abi.encodeCall(IMarketFactory.onAddToken, (address(pool), USDC, CHAINLINK_USDC_USD))
        );
        vm.expectCall(
            rateKeeperFactory, abi.encodeCall(IMarketFactory.onAddToken, (address(pool), USDC, CHAINLINK_USDC_USD))
        );
        vm.expectCall(
            lossPolicyFactory, abi.encodeCall(IMarketFactory.onAddToken, (address(pool), USDC, CHAINLINK_USDC_USD))
        );

        // Add token
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AddToken(address(pool), USDC);
        marketConfigurator.addToken(address(pool), USDC, CHAINLINK_USDC_USD);
    }

    // Expected addresses for credit suite creation
    address poolQuotaKeeper;
    address expectedAccountFactory;
    address expectedCreditManager;
    address expectedCreditConfigurator;
    address expectedCreditFacade;
    address expectedMasterCreditAccount;
    address botList;

    /// @notice Tests credit suite deployment
    function test_MC_20_deployCreditSuite() public {
        botList = CreditFactory(creditFactory).botList();
        lossPolicy = IContractsRegister(marketConfigurator.contractsRegister()).getLossPolicy(address(pool));
        poolQuotaKeeper = IPoolV3(pool).poolQuotaKeeper();
        // Prepare credit suite params
        DeployParams memory accountFactoryParams = DeployParams({
            postfix: "DEFAULT",
            salt: bytes32(uint256(1)),
            constructorParams: abi.encode(addressProvider)
        });

        CreditManagerParams memory creditManagerParams = CreditManagerParams({
            maxEnabledTokens: 4,
            feeInterest: 10_00,
            feeLiquidation: 1_50,
            liquidationPremium: 1_50,
            feeLiquidationExpired: 1_50,
            liquidationPremiumExpired: 1_50,
            minDebt: 1e18,
            maxDebt: 20e18,
            name: "Credit Manager ETH",
            accountFactoryParams: accountFactoryParams
        });

        CreditFacadeParams memory facadeParams =
            CreditFacadeParams({degenNFT: address(0), expirable: false, migrateBotList: false});

        bytes memory creditSuiteParams = abi.encode(creditManagerParams, facadeParams);

        // Test that only admin can deploy credit suites
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.createCreditSuite(3_10, address(pool), creditSuiteParams);

        expectedAccountFactory = IBytecodeRepository(bytecodeRepository).computeAddress(
            "ACCOUNT_FACTORY::DEFAULT",
            3_10,
            abi.encode(addressProvider),
            keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator)),
            creditFactory
        );

        // Compute expected addresses
        expectedCreditManager = IBytecodeRepository(bytecodeRepository).computeAddress(
            "CREDIT_MANAGER",
            3_10,
            abi.encode(
                address(pool),
                expectedAccountFactory,
                priceOracle,
                creditManagerParams.maxEnabledTokens,
                creditManagerParams.feeInterest,
                creditManagerParams.feeLiquidation,
                creditManagerParams.liquidationPremium,
                creditManagerParams.feeLiquidationExpired,
                creditManagerParams.liquidationPremiumExpired,
                creditManagerParams.name
            ),
            bytes32(bytes20(address(marketConfigurator))),
            creditFactory
        );

        expectedCreditConfigurator = IBytecodeRepository(bytecodeRepository).computeAddress(
            "CREDIT_CONFIGURATOR",
            3_10,
            abi.encode(expectedCreditManager),
            bytes32(bytes20(address(marketConfigurator))),
            creditFactory
        );

        expectedCreditFacade = IBytecodeRepository(bytecodeRepository).computeAddress(
            "CREDIT_FACADE",
            3_10,
            abi.encode(
                addressProvider,
                expectedCreditManager,
                lossPolicy,
                botList,
                WETH,
                facadeParams.degenNFT,
                facadeParams.expirable
            ),
            bytes32(bytes20(address(marketConfigurator))),
            creditFactory
        );

        // Expect contract deployments
        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (
                    "CREDIT_MANAGER",
                    3_10,
                    abi.encode(
                        address(pool),
                        expectedAccountFactory,
                        priceOracle,
                        creditManagerParams.maxEnabledTokens,
                        creditManagerParams.feeInterest,
                        creditManagerParams.feeLiquidation,
                        creditManagerParams.liquidationPremium,
                        creditManagerParams.feeLiquidationExpired,
                        creditManagerParams.liquidationPremiumExpired,
                        creditManagerParams.name
                    ),
                    bytes32(bytes20(address(marketConfigurator)))
                )
            )
        );

        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (
                    "CREDIT_CONFIGURATOR",
                    3_10,
                    abi.encode(expectedCreditManager),
                    bytes32(bytes20(address(marketConfigurator)))
                )
            )
        );

        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (
                    "CREDIT_FACADE",
                    3_10,
                    abi.encode(
                        addressProvider,
                        expectedCreditManager,
                        lossPolicy,
                        botList,
                        WETH,
                        facadeParams.degenNFT,
                        facadeParams.expirable
                    ),
                    bytes32(bytes20(address(marketConfigurator)))
                )
            )
        );

        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (
                    "ACCOUNT_FACTORY::DEFAULT",
                    3_10,
                    abi.encode(addressProvider),
                    keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator))
                )
            )
        );

        vm.expectCall(expectedAccountFactory, abi.encodeCall(IAccountFactory.addCreditManager, (expectedCreditManager)));
        vm.expectCall(
            expectedCreditManager, abi.encodeCall(ICreditManagerV3.setCreditConfigurator, (expectedCreditConfigurator))
        );

        // Expect factory hooks
        vm.expectCall(poolFactory, abi.encodeCall(IMarketFactory.onCreateCreditSuite, (expectedCreditManager)));
        vm.expectCall(priceOracleFactory, abi.encodeCall(IMarketFactory.onCreateCreditSuite, (expectedCreditManager)));
        vm.expectCall(
            interestRateModelFactory, abi.encodeCall(IMarketFactory.onCreateCreditSuite, (expectedCreditManager))
        );
        vm.expectCall(rateKeeperFactory, abi.encodeCall(IMarketFactory.onCreateCreditSuite, (expectedCreditManager)));
        vm.expectCall(lossPolicyFactory, abi.encodeCall(IMarketFactory.onCreateCreditSuite, (expectedCreditManager)));

        vm.expectCall(
            expectedCreditConfigurator,
            abi.encodeCall(ICreditConfiguratorV3.setCreditFacade, (expectedCreditFacade, false))
        );

        vm.expectCall(
            expectedCreditConfigurator,
            abi.encodeCall(
                ICreditConfiguratorV3.setDebtLimits, (creditManagerParams.minDebt, creditManagerParams.maxDebt)
            )
        );

        vm.expectCall(address(pool), abi.encodeCall(IPoolV3.setCreditManagerDebtLimit, (expectedCreditManager, 0)));

        vm.expectCall(poolQuotaKeeper, abi.encodeCall(IPoolQuotaKeeperV3.addCreditManager, (expectedCreditManager)));

        // Expect factory authorizations
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(creditFactory, expectedCreditManager, expectedCreditConfigurator);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(creditFactory, expectedCreditManager, expectedCreditFacade);

        // Deploy credit suite
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.CreateCreditSuite(expectedCreditManager, creditFactory);
        address newCreditManager = marketConfigurator.createCreditSuite(3_10, address(pool), creditSuiteParams);

        assertEq(newCreditManager, expectedCreditManager, "Incorrect credit manager address");
    }

    /// @notice Tests credit suite shutdown
    function test_MC_21_shutdownCreditSuite() public {
        address contractsRegister = marketConfigurator.contractsRegister();

        // Test that only admin can shutdown credit suites
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.shutdownCreditSuite(address(creditManager));

        // Test that credit suite with non-zero debt cannot be shutdown
        vm.mockCall(
            address(pool), abi.encodeCall(IPoolV3.creditManagerBorrowed, (address(creditManager))), abi.encode(1)
        );
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                PoolFactory.CantShutdownCreditSuiteWithNonZeroDebtException.selector, address(creditManager)
            )
        );
        marketConfigurator.shutdownCreditSuite(address(creditManager));
        vm.clearMockedCalls();

        // Expect factory hooks
        vm.expectCall(poolFactory, abi.encodeCall(IMarketFactory.onShutdownCreditSuite, (address(creditManager))));
        vm.expectCall(
            priceOracleFactory, abi.encodeCall(IMarketFactory.onShutdownCreditSuite, (address(creditManager)))
        );
        vm.expectCall(
            interestRateModelFactory, abi.encodeCall(IMarketFactory.onShutdownCreditSuite, (address(creditManager)))
        );
        vm.expectCall(rateKeeperFactory, abi.encodeCall(IMarketFactory.onShutdownCreditSuite, (address(creditManager))));
        vm.expectCall(lossPolicyFactory, abi.encodeCall(IMarketFactory.onShutdownCreditSuite, (address(creditManager))));

        // Expect hook calls from PoolFactory
        vm.expectCall(address(pool), abi.encodeCall(IPoolV3.setCreditManagerDebtLimit, (address(creditManager), 0)));

        // Expect call to ContractsRegister
        vm.expectCall(
            contractsRegister, abi.encodeCall(IContractsRegister.shutdownCreditSuite, (address(creditManager)))
        );

        // Shutdown credit suite
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.ShutdownCreditSuite(address(creditManager));
        marketConfigurator.shutdownCreditSuite(address(creditManager));
    }

    function _uploadPriceOraclePatch() internal {
        CrossChainCall[] memory calls = new CrossChainCall[](1);

        bytes32 bytecodeHash = _uploadByteCodeAndSign(
            bytecodeAuthor, auditor, type(MockPriceOraclePatch).creationCode, AP_PRICE_ORACLE, 3_11
        );

        calls[0] = _generateAllowSystemContractCall(bytecodeHash);

        _submitBatchAndSign("Allow system contracts", calls);
    }

    /// @notice Tests price oracle update
    function test_MC_22_updatePriceOracle() public {
        _uploadPriceOraclePatch();

        // Add USDC to the pool to have multiple tokens with price feeds
        _addUSDC();

        // Test that only admin can update price oracle
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.updatePriceOracle(address(pool));

        // Deploy new price oracle
        address newPriceOracle = IBytecodeRepository(bytecodeRepository).computeAddress(
            "PRICE_ORACLE",
            3_11,
            abi.encode(marketConfigurator.acl()),
            bytes32(bytes20(address(pool))),
            priceOracleFactory
        );

        // Expect contract deployment
        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                ("PRICE_ORACLE", 3_11, abi.encode(marketConfigurator.acl()), bytes32(bytes20(address(pool))))
            )
        );

        // Expect factory hooks
        vm.expectCall(
            priceOracleFactory,
            abi.encodeCall(IMarketFactory.onUpdatePriceOracle, (address(pool), newPriceOracle, priceOracle))
        );
        vm.expectCall(
            creditFactory,
            abi.encodeCall(IMarketFactory.onUpdatePriceOracle, (address(creditManager), newPriceOracle, priceOracle))
        );

        // Expect price feed transfers
        vm.expectCall(newPriceOracle, abi.encodeCall(IPriceOracleV3.setPriceFeed, (WETH, CHAINLINK_ETH_USD, 1 days)));
        vm.expectCall(newPriceOracle, abi.encodeCall(IPriceOracleV3.setPriceFeed, (USDC, CHAINLINK_USDC_USD, 1 days)));

        // Expect credit manager update
        vm.expectCall(
            address(creditConfigurator), abi.encodeCall(ICreditConfiguratorV3.setPriceOracle, (newPriceOracle))
        );

        // Expect factory authorization changes
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(priceOracleFactory, address(pool), newPriceOracle);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(priceOracleFactory, address(pool), priceOracle);

        // Update price oracle
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UpdatePriceOracle(address(pool), newPriceOracle);
        marketConfigurator.updatePriceOracle(address(pool));
    }

    /// @notice Tests interest rate model update
    function test_MC_23_updateInterestRateModel() public {
        // Test that only admin can update interest rate model
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.updateInterestRateModel(
            address(pool),
            DeployParams({
                postfix: "LINEAR",
                salt: bytes32(uint256(1)),
                constructorParams: abi.encode(100, 200, 100, 100, 200, 300, false)
            })
        );

        address oldInterestRateModel = IPoolV3(pool).interestRateModel();

        // Deploy new interest rate model
        address newInterestRateModel = IBytecodeRepository(bytecodeRepository).computeAddress(
            "IRM::LINEAR",
            3_10,
            abi.encode(100, 200, 100, 100, 200, 300, false),
            keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator)),
            interestRateModelFactory
        );

        // Expect contract deployment
        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (
                    "IRM::LINEAR",
                    3_10,
                    abi.encode(100, 200, 100, 100, 200, 300, false),
                    keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator))
                )
            )
        );

        // Expect factory hooks
        vm.expectCall(
            poolFactory,
            abi.encodeCall(
                IMarketFactory.onUpdateInterestRateModel, (address(pool), newInterestRateModel, oldInterestRateModel)
            )
        );
        vm.expectCall(
            interestRateModelFactory,
            abi.encodeCall(
                IMarketFactory.onUpdateInterestRateModel, (address(pool), newInterestRateModel, oldInterestRateModel)
            )
        );

        // Expect hook calls from PoolFactory
        vm.expectCall(address(pool), abi.encodeCall(IPoolV3.setInterestRateModel, (newInterestRateModel)));

        // Expect factory authorization changes
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(interestRateModelFactory, address(pool), newInterestRateModel);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(interestRateModelFactory, address(pool), oldInterestRateModel);

        // Update interest rate model
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UpdateInterestRateModel(address(pool), newInterestRateModel);
        marketConfigurator.updateInterestRateModel(
            address(pool),
            DeployParams({
                postfix: "LINEAR",
                salt: bytes32(uint256(1)),
                constructorParams: abi.encode(100, 200, 100, 100, 200, 300, false)
            })
        );
    }

    /// @notice Tests rate keeper update
    function test_MC_24_updateRateKeeper() public {
        // Test that only admin can update rate keeper
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.updateRateKeeper(
            address(pool),
            DeployParams({
                postfix: "GAUGE",
                salt: bytes32(uint256(1)),
                constructorParams: abi.encode(address(pool), gearStaking)
            })
        );

        address quotaKeeper = IPoolV3(pool).poolQuotaKeeper();
        address oldRateKeeper = IPoolQuotaKeeperV3(quotaKeeper).gauge();

        // Deploy new rate keeper
        address newRateKeeper = IBytecodeRepository(bytecodeRepository).computeAddress(
            "RATE_KEEPER::GAUGE",
            3_10,
            abi.encode(address(pool), gearStaking),
            keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator)),
            rateKeeperFactory
        );

        // Expect contract deployment
        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (
                    "RATE_KEEPER::GAUGE",
                    3_10,
                    abi.encode(address(pool), gearStaking),
                    keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator))
                )
            )
        );

        // Expect factory hooks
        vm.expectCall(
            poolFactory,
            abi.encodeCall(IMarketFactory.onUpdateRateKeeper, (address(pool), newRateKeeper, oldRateKeeper))
        );
        vm.expectCall(
            rateKeeperFactory,
            abi.encodeCall(IMarketFactory.onUpdateRateKeeper, (address(pool), newRateKeeper, oldRateKeeper))
        );

        // Expect hook calls from PoolFactory
        vm.expectCall(quotaKeeper, abi.encodeCall(IPoolQuotaKeeperV3.setGauge, (newRateKeeper)));

        // Expect factory authorization changes
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(rateKeeperFactory, address(pool), newRateKeeper);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(rateKeeperFactory, address(pool), oldRateKeeper);

        // Update rate keeper
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UpdateRateKeeper(address(pool), newRateKeeper);
        marketConfigurator.updateRateKeeper(
            address(pool),
            DeployParams({
                postfix: "GAUGE",
                salt: bytes32(uint256(1)),
                constructorParams: abi.encode(address(pool), gearStaking)
            })
        );
    }

    /// @notice Tests loss policy update
    function test_MC_25_updateLossPolicy() public {
        address contractsRegister = marketConfigurator.contractsRegister();

        // Test that only admin can update loss policy
        vm.expectRevert(abi.encodeWithSelector(IMarketConfigurator.CallerIsNotAdminException.selector, address(this)));
        marketConfigurator.updateLossPolicy(
            address(pool),
            DeployParams({
                postfix: "MOCK",
                salt: bytes32(uint256(1)),
                constructorParams: abi.encode(address(pool), addressProvider)
            })
        );

        address oldLossPolicy = IContractsRegister(marketConfigurator.contractsRegister()).getLossPolicy(address(pool));

        // Deploy new loss policy
        address newLossPolicy = IBytecodeRepository(bytecodeRepository).computeAddress(
            "LOSS_POLICY::MOCK",
            3_10,
            abi.encode(address(pool), addressProvider),
            keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator)),
            lossPolicyFactory
        );

        // Expect contract deployment
        vm.expectCall(
            bytecodeRepository,
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (
                    "LOSS_POLICY::MOCK",
                    3_10,
                    abi.encode(address(pool), addressProvider),
                    keccak256(abi.encode(bytes32(uint256(1)), marketConfigurator))
                )
            )
        );

        // Expect factory hooks
        vm.expectCall(
            poolFactory,
            abi.encodeCall(IMarketFactory.onUpdateLossPolicy, (address(pool), newLossPolicy, oldLossPolicy))
        );
        vm.expectCall(
            lossPolicyFactory,
            abi.encodeCall(IMarketFactory.onUpdateLossPolicy, (address(pool), newLossPolicy, oldLossPolicy))
        );
        vm.expectCall(
            creditFactory,
            abi.encodeCall(IMarketFactory.onUpdateLossPolicy, (address(creditManager), newLossPolicy, oldLossPolicy))
        );

        // Expect hook calls from CreditFactory
        vm.expectCall(address(creditConfigurator), abi.encodeCall(ICreditConfiguratorV3.setLossPolicy, (newLossPolicy)));

        vm.expectCall(
            contractsRegister, abi.encodeCall(IContractsRegister.setLossPolicy, (address(pool), newLossPolicy))
        );

        // Expect factory authorization changes
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.AuthorizeFactory(lossPolicyFactory, address(pool), newLossPolicy);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UnauthorizeFactory(lossPolicyFactory, address(pool), oldLossPolicy);

        // Update loss policy
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfigurator.UpdateLossPolicy(address(pool), newLossPolicy);
        marketConfigurator.updateLossPolicy(
            address(pool),
            DeployParams({
                postfix: "MOCK",
                salt: bytes32(uint256(1)),
                constructorParams: abi.encode(address(pool), addressProvider)
            })
        );
    }
}
