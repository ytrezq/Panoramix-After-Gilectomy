// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {IContractsRegister} from "../interfaces/IContractsRegister.sol";

import {ACL} from "../market/ACL.sol";
import {ContractsRegister} from "../market/ContractsRegister.sol";

contract ContractsRegisterUnitTest is Test {
    ContractsRegister register;
    ACL acl;

    address configurator;
    address pool1;
    address pool2;
    address priceOracle1;
    address priceOracle2;
    address lossPolicy1;
    address lossPolicy2;
    address creditManager1;
    address creditManager2;

    function setUp() public {
        configurator = makeAddr("Configurator");
        pool1 = makeAddr("Pool1");
        pool2 = makeAddr("Pool2");
        priceOracle1 = makeAddr("PriceOracle1");
        priceOracle2 = makeAddr("PriceOracle2");
        lossPolicy1 = makeAddr("LossPolicy1");
        lossPolicy2 = makeAddr("LossPolicy2");
        creditManager1 = makeAddr("CreditManager1");
        vm.mockCall(creditManager1, abi.encodeWithSignature("pool()"), abi.encode(pool1));
        creditManager2 = makeAddr("CreditManager2");
        vm.mockCall(creditManager2, abi.encodeWithSignature("pool()"), abi.encode(pool2));

        acl = new ACL(configurator);
        register = new ContractsRegister(address(acl));
    }

    /// @notice U:[CR-1]: Constructor works correctly
    function test_U_CR_01_constructor_works_correctly() public view {
        assertEq(address(register.acl()), address(acl));
        assertEq(register.getPools().length, 0);
        assertEq(register.getShutdownPools().length, 0);
        assertEq(register.getCreditManagers().length, 0);
        assertEq(register.getShutdownCreditManagers().length, 0);
    }

    /// @notice U:[CR-2]: Only configurator can call functions
    function test_U_CR_02_onlyConfigurator_can_call_functions() public {
        vm.expectRevert(abi.encodeWithSignature("CallerNotConfiguratorException()"));
        register.registerMarket(pool1, priceOracle1, lossPolicy1);

        vm.expectRevert(abi.encodeWithSignature("CallerNotConfiguratorException()"));
        register.shutdownMarket(pool1);

        vm.expectRevert(abi.encodeWithSignature("CallerNotConfiguratorException()"));
        register.setPriceOracle(pool1, priceOracle2);

        vm.expectRevert(abi.encodeWithSignature("CallerNotConfiguratorException()"));
        register.setLossPolicy(pool1, lossPolicy2);

        vm.expectRevert(abi.encodeWithSignature("CallerNotConfiguratorException()"));
        register.registerCreditSuite(creditManager1);

        vm.expectRevert(abi.encodeWithSignature("CallerNotConfiguratorException()"));
        register.shutdownCreditSuite(creditManager1);
    }

    // --------------//
    // MARKETS TESTS //
    // ------------- //

    /// @notice U:[CR-3]: `registerMarket` works correctly
    function test_U_CR_03_registerMarket_works_correctly() public {
        vm.startPrank(configurator);

        // Zero address checks
        vm.expectRevert(abi.encodeWithSignature("ZeroAddressException()"));
        register.registerMarket(pool1, address(0), lossPolicy1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddressException()"));
        register.registerMarket(pool1, priceOracle1, address(0));

        // Successfully registers new market
        assertFalse(register.isPool(pool1));

        vm.expectEmit(true, true, true, true);
        emit IContractsRegister.RegisterMarket(pool1, priceOracle1, lossPolicy1);
        register.registerMarket(pool1, priceOracle1, lossPolicy1);

        assertTrue(register.isPool(pool1));
        assertEq(register.getPools().length, 1);
        assertEq(register.getPools()[0], pool1);

        assertEq(register.getPriceOracle(pool1), priceOracle1);
        assertEq(register.getLossPolicy(pool1), lossPolicy1);

        // Second registration should be no-op
        register.registerMarket(pool1, priceOracle2, lossPolicy2);
        assertEq(register.getPriceOracle(pool1), priceOracle1);
        assertEq(register.getLossPolicy(pool1), lossPolicy1);

        vm.stopPrank();
    }

    /// @notice U:[CR-4]: `registerMarket` reverts for shutdown markets
    function test_U_CR_04_registerMarket_reverts_for_shutdown_markets() public {
        vm.startPrank(configurator);

        register.registerMarket(pool1, priceOracle1, lossPolicy1);
        register.shutdownMarket(pool1);

        vm.expectRevert(abi.encodeWithSelector(IContractsRegister.MarketShutDownException.selector, pool1));
        register.registerMarket(pool1, priceOracle1, lossPolicy1);

        vm.stopPrank();
    }

    /// @notice U:[CR-5]: `shutdownMarket` works correctly
    function test_U_CR_05_shutdownMarket_works_correctly() public {
        vm.startPrank(configurator);

        // Market must be registered
        vm.expectRevert(abi.encodeWithSelector(IContractsRegister.MarketNotRegisteredException.selector, pool1));
        register.shutdownMarket(pool1);

        register.registerMarket(pool1, priceOracle1, lossPolicy1);

        // Successfully shuts down market
        vm.expectEmit(true, true, true, true);
        emit IContractsRegister.ShutdownMarket(pool1);
        register.shutdownMarket(pool1);

        assertFalse(register.isPool(pool1));
        assertEq(register.getPools().length, 0);
        assertEq(register.getShutdownPools().length, 1);
        assertEq(register.getShutdownPools()[0], pool1);

        // Getters should revert for shutdown markets
        vm.expectRevert(abi.encodeWithSelector(IContractsRegister.MarketNotRegisteredException.selector, pool1));
        register.getPriceOracle(pool1);
        vm.expectRevert(abi.encodeWithSelector(IContractsRegister.MarketNotRegisteredException.selector, pool1));
        register.getLossPolicy(pool1);
        vm.expectRevert(abi.encodeWithSelector(IContractsRegister.MarketNotRegisteredException.selector, pool1));
        register.getCreditManagers(pool1);
        // This one should work though
        assertEq(register.getShutdownCreditManagers(pool1).length, 0);

        // Second shutdown should be no-op
        register.shutdownMarket(pool1);

        vm.stopPrank();
    }

    /// @notice U:[CR-6]: `shutdownMarket` reverts if market has credit managers
    function test_U_CR_06_shutdownMarket_reverts_if_market_has_credit_managers() public {
        vm.startPrank(configurator);

        register.registerMarket(pool1, priceOracle1, lossPolicy1);
        register.registerCreditSuite(creditManager1);

        vm.expectRevert(abi.encodeWithSelector(IContractsRegister.MarketNotEmptyException.selector, pool1));
        register.shutdownMarket(pool1);

        vm.stopPrank();
    }

    /// @notice U:[CR-7]: Market parameters update works correctly
    function test_U_CR_07_market_parameters_update_works_correctly() public {
        vm.startPrank(configurator);

        // Market must be registered
        vm.expectRevert(abi.encodeWithSelector(IContractsRegister.MarketNotRegisteredException.selector, pool1));
        register.setPriceOracle(pool1, priceOracle1);
        vm.expectRevert(abi.encodeWithSelector(IContractsRegister.MarketNotRegisteredException.selector, pool1));
        register.setLossPolicy(pool1, lossPolicy1);

        register.registerMarket(pool1, priceOracle1, lossPolicy1);

        // Zero address checks
        vm.expectRevert(abi.encodeWithSignature("ZeroAddressException()"));
        register.setPriceOracle(pool1, address(0));
        vm.expectRevert(abi.encodeWithSignature("ZeroAddressException()"));
        register.setLossPolicy(pool1, address(0));

        // Test price oracle update
        vm.expectEmit(true, true, true, true);
        emit IContractsRegister.SetPriceOracle(pool1, priceOracle2);
        register.setPriceOracle(pool1, priceOracle2);
        assertEq(register.getPriceOracle(pool1), priceOracle2);

        // Test loss policy update
        vm.expectEmit(true, true, true, true);
        emit IContractsRegister.SetLossPolicy(pool1, lossPolicy2);
        register.setLossPolicy(pool1, lossPolicy2);
        assertEq(register.getLossPolicy(pool1), lossPolicy2);

        // Setting same values should be no-op
        register.setPriceOracle(pool1, priceOracle2);
        register.setLossPolicy(pool1, lossPolicy2);

        vm.stopPrank();
    }

    // ------------------ //
    // CREDIT SUITE TESTS //
    // ------------------ //

    /// @notice U:[CR-8]: `registerCreditSuite` works correctly
    function test_U_CR_08_registerCreditSuite_works_correctly() public {
        vm.startPrank(configurator);

        // market must be registered
        vm.expectRevert(abi.encodeWithSelector(IContractsRegister.MarketNotRegisteredException.selector, pool1));
        register.registerCreditSuite(creditManager1);

        register.registerMarket(pool1, priceOracle1, lossPolicy1);

        // Successfully registers new credit suite
        assertFalse(register.isCreditManager(creditManager1));

        vm.expectEmit(true, true, true, true);
        emit IContractsRegister.RegisterCreditSuite(pool1, creditManager1);
        register.registerCreditSuite(creditManager1);

        assertTrue(register.isCreditManager(creditManager1));
        assertEq(register.getCreditManagers().length, 1);
        assertEq(register.getCreditManagers()[0], creditManager1);
        assertEq(register.getCreditManagers(pool1).length, 1);
        assertEq(register.getCreditManagers(pool1)[0], creditManager1);

        // Second registration should be no-op
        register.registerCreditSuite(creditManager1);
    }

    /// @notice U:[CR-9]: `registerCreditSuite` reverts for shutdown suites
    function test_U_CR_09_registerCreditSuite_reverts_for_shutdown_suites() public {
        vm.startPrank(configurator);

        register.registerMarket(pool1, priceOracle1, lossPolicy1);
        register.registerCreditSuite(creditManager1);
        register.shutdownCreditSuite(creditManager1);

        vm.expectRevert(
            abi.encodeWithSelector(IContractsRegister.CreditSuiteShutDownException.selector, creditManager1)
        );
        register.registerCreditSuite(creditManager1);

        vm.stopPrank();
    }

    /// @notice U:[CR-10]: `shutdownCreditSuite` works correctly
    function test_U_CR_10_shutdownCreditSuite_works_correctly() public {
        vm.startPrank(configurator);

        // Credit suite must be registered
        vm.expectRevert(
            abi.encodeWithSelector(IContractsRegister.CreditSuiteNotRegisteredException.selector, creditManager1)
        );
        register.shutdownCreditSuite(creditManager1);

        register.registerMarket(pool1, priceOracle1, lossPolicy1);
        register.registerCreditSuite(creditManager1);

        vm.expectEmit(true, true, true, true);
        emit IContractsRegister.ShutdownCreditSuite(pool1, creditManager1);
        register.shutdownCreditSuite(creditManager1);

        assertFalse(register.isCreditManager(creditManager1));
        assertEq(register.getCreditManagers(pool1).length, 0);
        assertEq(register.getShutdownCreditManagers(pool1)[0], creditManager1);

        // Second shutdown should be no-op
        register.shutdownCreditSuite(creditManager1);

        //
        vm.stopPrank();
    }
}
