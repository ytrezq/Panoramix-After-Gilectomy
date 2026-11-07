// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {ConfigurationTestHelper} from "./ConfigurationTestHelper.sol";
import {ILossPolicy} from "@gearbox-protocol/core-v3/contracts/interfaces/base/ILossPolicy.sol";
import {IContractsRegister} from "../../interfaces/IContractsRegister.sol";

contract LossPolicyConfigurationUnitTest is ConfigurationTestHelper {
    address private _lossPolicy;

    function setUp() public override {
        super.setUp();
        _lossPolicy = IContractsRegister(marketConfigurator.contractsRegister()).getLossPolicy(address(pool));
    }

    /// REGULAR CONFIGURATION TESTS ///

    function test_LP_01_configure() public {
        vm.expectCall(_lossPolicy, abi.encodeCall(ILossPolicy.setAccessMode, (ILossPolicy.AccessMode.Permissioned)));

        vm.prank(admin);
        marketConfigurator.configureLossPolicy(
            address(pool), abi.encodeCall(ILossPolicy.setAccessMode, (ILossPolicy.AccessMode.Permissioned))
        );

        assertEq(
            uint8(ILossPolicy(_lossPolicy).accessMode()),
            uint8(ILossPolicy.AccessMode.Permissioned),
            "Access mode must be PERMISSIONED"
        );

        vm.expectCall(_lossPolicy, abi.encodeCall(ILossPolicy.setChecksEnabled, (true)));

        vm.prank(admin);
        marketConfigurator.configureLossPolicy(address(pool), abi.encodeCall(ILossPolicy.setChecksEnabled, (true)));

        assertTrue(ILossPolicy(_lossPolicy).checksEnabled(), "Checks must be enabled");
    }

    /// EMERGENCY CONFIGURATION TESTS ///

    function test_LP_02_emergency_configure() public {
        vm.expectCall(_lossPolicy, abi.encodeCall(ILossPolicy.setAccessMode, (ILossPolicy.AccessMode.Forbidden)));

        vm.prank(emergencyAdmin);
        marketConfigurator.emergencyConfigureLossPolicy(
            address(pool), abi.encodeCall(ILossPolicy.setAccessMode, (ILossPolicy.AccessMode.Forbidden))
        );

        assertEq(
            uint8(ILossPolicy(_lossPolicy).accessMode()),
            uint8(ILossPolicy.AccessMode.Forbidden),
            "Access mode must be FORBIDDEN"
        );

        vm.expectCall(_lossPolicy, abi.encodeCall(ILossPolicy.setChecksEnabled, (false)));

        vm.prank(emergencyAdmin);
        marketConfigurator.emergencyConfigureLossPolicy(
            address(pool), abi.encodeCall(ILossPolicy.setChecksEnabled, (false))
        );

        assertFalse(ILossPolicy(_lossPolicy).checksEnabled(), "Checks must be disabled");
    }
}
