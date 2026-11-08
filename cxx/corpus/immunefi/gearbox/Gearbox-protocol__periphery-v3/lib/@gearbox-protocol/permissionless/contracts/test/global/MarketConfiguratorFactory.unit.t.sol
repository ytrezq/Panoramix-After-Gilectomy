// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {MarketConfiguratorFactory} from "../../instance/MarketConfiguratorFactory.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {IMarketConfiguratorFactory} from "../../interfaces/IMarketConfiguratorFactory.sol";
import {IBytecodeRepository} from "../../interfaces/IBytecodeRepository.sol";
import {Call} from "../../interfaces/Types.sol";
import {IImmutableOwnableTrait} from "../../interfaces/base/IImmutableOwnableTrait.sol";

import {
    AP_BYTECODE_REPOSITORY,
    AP_CROSS_CHAIN_GOVERNANCE,
    AP_MARKET_CONFIGURATOR,
    NO_VERSION_CONTROL
} from "../../libraries/ContractLiterals.sol";

import {MarketConfiguratorFactoryHarness} from "./MarketConfiguratorFactoryHarness.sol";

contract MarketConfiguratorFactoryTest is Test {
    MarketConfiguratorFactoryHarness public factory;
    address public governance;
    address public configurator;
    IAddressProvider public addressProvider;
    IBytecodeRepository public bytecodeRepository;

    function setUp() public {
        governance = makeAddr("governance");
        configurator = makeAddr("configurator");
        addressProvider = IAddressProvider(makeAddr("addressProvider"));
        bytecodeRepository = IBytecodeRepository(makeAddr("bytecodeRepository"));

        vm.mockCall(configurator, abi.encodeWithSignature("curatorName()"), abi.encode("Test Curator"));

        vm.mockCall(
            address(addressProvider),
            abi.encodeWithSignature(
                "getAddressOrRevert(bytes32,uint256)", AP_CROSS_CHAIN_GOVERNANCE, NO_VERSION_CONTROL
            ),
            abi.encode(governance)
        );

        vm.mockCall(
            address(addressProvider),
            abi.encodeWithSignature("getAddressOrRevert(bytes32,uint256)", AP_BYTECODE_REPOSITORY, NO_VERSION_CONTROL),
            abi.encode(address(bytecodeRepository))
        );

        factory = new MarketConfiguratorFactoryHarness(address(addressProvider));
    }

    function test_U_MCF_01_create_market_configurator_works() public {
        address emergencyAdmin = makeAddr("emergencyAdmin");
        address adminFeeTreasury = makeAddr("treasury");
        string memory curatorName = "Test Curator";

        // Mock deployment
        vm.mockCall(
            address(bytecodeRepository),
            abi.encodeCall(IBytecodeRepository.getLatestPatchVersion, (AP_MARKET_CONFIGURATOR, 3_10)),
            abi.encode(3_11)
        );
        vm.mockCall(
            address(bytecodeRepository),
            abi.encodeCall(
                IBytecodeRepository.deploy,
                (
                    AP_MARKET_CONFIGURATOR,
                    3_11,
                    abi.encode(
                        address(addressProvider), address(this), emergencyAdmin, adminFeeTreasury, curatorName, false
                    ),
                    bytes32(bytes20(address(this)))
                )
            ),
            abi.encode(configurator)
        );

        // Expect CreateMarketConfigurator event
        vm.expectEmit(true, true, true, true);
        emit IMarketConfiguratorFactory.CreateMarketConfigurator(configurator, curatorName);

        factory.createMarketConfigurator(emergencyAdmin, adminFeeTreasury, curatorName, false);

        // Verify configurator was registered
        assertTrue(factory.isMarketConfigurator(configurator));
        assertEq(factory.getMarketConfigurators()[0], configurator);
        assertEq(factory.getNumMarketConfigurators(), 1);
    }

    function test_U_MCF_02_shutdown_market_configurator_works() public {
        address contractsRegister = makeAddr("contractsRegister");
        vm.mockCall(configurator, abi.encodeWithSignature("admin()"), abi.encode(address(this)));

        // Test it reverts if caller is not admin
        address notAdmin = makeAddr("notAdmin");
        vm.prank(notAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketConfiguratorFactory.CallerIsNotMarketConfiguratorAdminException.selector, notAdmin
            )
        );
        factory.shutdownMarketConfigurator(configurator);

        // Test it reverts if already shutdown
        vm.mockCall(configurator, abi.encodeWithSignature("admin()"), abi.encode(address(this)));
        factory.exposed_addShutdownConfigurator(configurator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketConfiguratorFactory.MarketConfiguratorIsAlreadyShutdownException.selector, configurator
            )
        );
        factory.shutdownMarketConfigurator(configurator);
        factory.exposed_removeShutdownConfigurator(configurator);

        // Test it reverts if configurator is not registered
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketConfiguratorFactory.MarketConfiguratorIsNotRegisteredException.selector, configurator
            )
        );
        factory.shutdownMarketConfigurator(configurator);

        // Test it reverts if configurator has pools
        factory.exposed_addRegisteredConfigurator(configurator);
        vm.mockCall(configurator, abi.encodeWithSignature("contractsRegister()"), abi.encode(contractsRegister));
        address[] memory pools = new address[](1);
        pools[0] = makeAddr("pool");
        vm.mockCall(contractsRegister, abi.encodeWithSignature("getPools()"), abi.encode(pools));
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketConfiguratorFactory.CantShutdownMarketConfiguratorException.selector, configurator
            )
        );
        factory.shutdownMarketConfigurator(configurator);

        // Test it is shutdown successfully
        vm.mockCall(contractsRegister, abi.encodeWithSignature("getPools()"), abi.encode(new address[](0)));
        vm.expectEmit(true, false, false, false);
        emit IMarketConfiguratorFactory.ShutdownMarketConfigurator(configurator);
        factory.shutdownMarketConfigurator(configurator);

        // Verify final state
        assertFalse(factory.isMarketConfigurator(configurator));
        assertEq(factory.getNumMarketConfigurators(), 0);
        assertEq(factory.getShutdownMarketConfigurators()[0], configurator);
    }

    function test_U_MCF_03_add_market_configurator_works() public {
        // Test it reverts if not governance
        address notGovernance = makeAddr("notGovernance");
        vm.prank(notGovernance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketConfiguratorFactory.CallerIsNotCrossChainGovernanceException.selector, notGovernance
            )
        );
        factory.addMarketConfigurator(configurator);

        // Test successful addition
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IMarketConfiguratorFactory.CreateMarketConfigurator(configurator, "Test Curator");
        factory.addMarketConfigurator(configurator);
        assertTrue(factory.isMarketConfigurator(configurator));
        assertEq(factory.getMarketConfigurators()[0], configurator);
        assertEq(factory.getNumMarketConfigurators(), 1);

        // Test it reverts on duplicate addition
        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketConfiguratorFactory.MarketConfiguratorIsAlreadyAddedException.selector, configurator
            )
        );
        factory.addMarketConfigurator(configurator);

        // Test it reverts if configurator is shutdown
        address shutdownConfigurator = makeAddr("shutdownConfigurator");
        vm.mockCall(shutdownConfigurator, abi.encodeWithSignature("curatorName()"), abi.encode("Shutdown Curator"));

        factory.exposed_addShutdownConfigurator(shutdownConfigurator);

        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketConfiguratorFactory.MarketConfiguratorIsAlreadyShutdownException.selector, shutdownConfigurator
            )
        );
        factory.addMarketConfigurator(shutdownConfigurator);
    }
}
