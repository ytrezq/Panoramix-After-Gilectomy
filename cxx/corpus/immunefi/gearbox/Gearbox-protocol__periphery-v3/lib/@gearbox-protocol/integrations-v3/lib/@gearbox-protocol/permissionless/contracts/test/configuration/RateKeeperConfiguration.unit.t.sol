// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {ConfigurationTestHelper} from "./ConfigurationTestHelper.sol";
import {TumblerV3} from "@gearbox-protocol/core-v3/contracts/pool/TumblerV3.sol";
import {ITumblerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ITumblerV3.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {IContractsRegister} from "../../interfaces/IContractsRegister.sol";

contract RateKeeperConfigurationUnitTest is ConfigurationTestHelper {
    address private _rateKeeper;
    address private _quotaKeeper;

    function setUp() public override {
        super.setUp();

        _quotaKeeper = IPoolV3(pool).poolQuotaKeeper();
        _rateKeeper = IPoolQuotaKeeperV3(_quotaKeeper).gauge();

        _addUSDC();
    }

    /// REGULAR CONFIGURATION TESTS ///

    function test_RK_01_setRate() public {
        address token = USDC;
        uint16 rate = 100; // 1%

        vm.expectCall(_rateKeeper, abi.encodeCall(ITumblerV3.setRate, (token, rate)));

        vm.prank(admin);
        marketConfigurator.configureRateKeeper(address(pool), abi.encodeCall(ITumblerV3.setRate, (token, rate)));

        address[] memory tokens = new address[](1);
        tokens[0] = token;

        uint16[] memory rates = ITumblerV3(_rateKeeper).getRates(tokens);
        assertEq(rates[0], rate, "Incorrect rate");
    }

    function test_RK_02_updateRates() public {
        vm.warp(block.timestamp + ITumblerV3(_rateKeeper).epochLength());

        vm.expectCall(_rateKeeper, abi.encodeCall(ITumblerV3.updateRates, ()));

        vm.prank(admin);
        marketConfigurator.configureRateKeeper(address(pool), abi.encodeCall(ITumblerV3.updateRates, ()));
    }

    function test_RK_03_addToken_reverts() public {
        address token = USDC;

        vm.expectRevert();

        vm.prank(admin);
        marketConfigurator.configureRateKeeper(address(pool), abi.encodeCall(TumblerV3.addToken, (token)));
    }
}
