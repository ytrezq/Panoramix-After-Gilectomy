// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

import {ConfigurationTestHelper} from "./ConfigurationTestHelper.sol";
import {PoolFactory} from "../../factories/PoolFactory.sol";
import {IContractsRegister} from "../../interfaces/IContractsRegister.sol";
import {IPoolConfigureActions} from "../../interfaces/factories/IPoolConfigureActions.sol";
import {IPoolEmergencyConfigureActions} from "../../interfaces/factories/IPoolEmergencyConfigureActions.sol";
import {IPriceOracleConfigureActions} from "../../interfaces/factories/IPriceOracleConfigureActions.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IPriceOracleV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPriceOracleV3.sol";
import {GeneralMock} from "@gearbox-protocol/core-v3/contracts/test/mocks/GeneralMock.sol";
import {PERCENTAGE_FACTOR} from "@gearbox-protocol/core-v3/contracts/libraries/Constants.sol";

contract PoolConfigurationUnitTest is ConfigurationTestHelper {
    address private _target;
    address private _quotaKeeper;

    function setUp() public override {
        super.setUp();

        _quotaKeeper = IPoolV3(pool).poolQuotaKeeper();
    }

    /// REGULAR CONFIGURATION TESTS ///

    function test_P_01_setTotalDebtLimit() public {
        uint256 limit = 1_000_000;

        vm.expectCall(address(pool), abi.encodeCall(IPoolV3.setTotalDebtLimit, (limit)));

        vm.prank(admin);
        marketConfigurator.configurePool(
            address(pool), abi.encodeCall(IPoolConfigureActions.setTotalDebtLimit, (limit))
        );

        assertEq(IPoolV3(pool).totalDebtLimit(), limit, "Incorrect total debt limit");
    }

    function test_P_02_setCreditManagerDebtLimit() public {
        uint256 limit = 500_000;

        vm.expectCall(address(pool), abi.encodeCall(IPoolV3.setCreditManagerDebtLimit, (address(creditManager), limit)));

        vm.prank(admin);
        marketConfigurator.configurePool(
            address(pool),
            abi.encodeCall(IPoolConfigureActions.setCreditManagerDebtLimit, (address(creditManager), limit))
        );

        assertEq(
            IPoolV3(pool).creditManagerDebtLimit(address(creditManager)), limit, "Incorrect credit manager debt limit"
        );
    }

    function test_P_03_setTokenLimit() public {
        _addUSDC();

        address token = USDC;
        uint96 limit = 100_000;

        vm.expectCall(_quotaKeeper, abi.encodeCall(IPoolQuotaKeeperV3.setTokenLimit, (token, limit)));

        vm.prank(admin);
        marketConfigurator.configurePool(
            address(pool), abi.encodeCall(IPoolConfigureActions.setTokenLimit, (token, limit))
        );

        (,,,, uint96 tokenLimit,) = IPoolQuotaKeeperV3(_quotaKeeper).getTokenQuotaParams(token);
        assertEq(tokenLimit, limit, "Incorrect token limit");

        // Test that it reverts when trying to set non-zero limit for token with zero price
        address priceOracle = IContractsRegister(marketConfigurator.contractsRegister()).getPriceOracle(address(pool));
        vm.mockCall(priceOracle, abi.encodeCall(IPriceOracleV3.getPrice, (token)), abi.encode(0));
        vm.expectRevert(abi.encodeWithSelector(PoolFactory.ZeroPriceFeedException.selector, token));

        vm.prank(admin);
        marketConfigurator.configurePool(
            address(pool), abi.encodeCall(IPoolConfigureActions.setTokenLimit, (token, limit + 1))
        );
    }

    function test_P_04_setTokenQuotaIncreaseFee() public {
        _addUSDC();

        address token = USDC;
        uint16 fee = 100; // 1%

        vm.expectCall(_quotaKeeper, abi.encodeCall(IPoolQuotaKeeperV3.setTokenQuotaIncreaseFee, (token, fee)));

        vm.prank(admin);
        marketConfigurator.configurePool(
            address(pool), abi.encodeCall(IPoolConfigureActions.setTokenQuotaIncreaseFee, (token, fee))
        );

        (,, uint16 quotaIncreaseFee,,,) = IPoolQuotaKeeperV3(_quotaKeeper).getTokenQuotaParams(token);
        assertEq(quotaIncreaseFee, fee, "Incorrect quota increase fee");
    }

    function test_P_05_pause_unpause() public {
        vm.startPrank(admin);

        vm.expectCall(address(pool), abi.encodeCall(IPoolV3.pause, ()));

        marketConfigurator.configurePool(address(pool), abi.encodeCall(IPoolConfigureActions.pause, ()));

        assertTrue(Pausable(address(pool)).paused(), "Pool must be paused");

        vm.expectCall(address(pool), abi.encodeCall(IPoolV3.unpause, ()));

        marketConfigurator.configurePool(address(pool), abi.encodeCall(IPoolConfigureActions.unpause, ()));
        vm.stopPrank();

        assertFalse(Pausable(address(pool)).paused(), "Pool must be unpaused");
    }

    /// EMERGENCY CONFIGURATION TESTS ///

    function test_P_06_emergency_setCreditManagerDebtLimitToZero() public {
        vm.expectCall(address(pool), abi.encodeCall(IPoolV3.setCreditManagerDebtLimit, (address(creditManager), 0)));

        vm.prank(emergencyAdmin);
        marketConfigurator.emergencyConfigurePool(
            address(pool),
            abi.encodeCall(IPoolEmergencyConfigureActions.setCreditManagerDebtLimitToZero, (address(creditManager)))
        );

        assertEq(
            IPoolV3(pool).creditManagerDebtLimit(address(creditManager)), 0, "Credit manager debt limit must be zero"
        );
    }

    function test_P_07_emergency_setTokenLimitToZero() public {
        _addUSDC();

        address token = USDC;

        vm.expectCall(_quotaKeeper, abi.encodeCall(IPoolQuotaKeeperV3.setTokenLimit, (token, 0)));

        vm.prank(emergencyAdmin);
        marketConfigurator.emergencyConfigurePool(
            address(pool), abi.encodeCall(IPoolEmergencyConfigureActions.setTokenLimitToZero, (token))
        );

        (,,,, uint96 tokenLimit,) = IPoolQuotaKeeperV3(_quotaKeeper).getTokenQuotaParams(token);
        assertEq(tokenLimit, 0, "Token limit must be zero");
    }

    function test_P_08_emergency_pause() public {
        vm.expectCall(address(pool), abi.encodeCall(IPoolV3.pause, ()));

        vm.prank(emergencyAdmin);
        marketConfigurator.emergencyConfigurePool(
            address(pool), abi.encodeCall(IPoolEmergencyConfigureActions.pause, ())
        );

        assertTrue(Pausable(address(pool)).paused(), "Pool must be paused");
    }
}
