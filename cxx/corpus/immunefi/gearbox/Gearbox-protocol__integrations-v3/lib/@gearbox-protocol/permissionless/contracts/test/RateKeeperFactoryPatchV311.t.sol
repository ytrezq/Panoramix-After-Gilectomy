// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {TokenIsNotQuotedException} from "@gearbox-protocol/core-v3/contracts/interfaces/IExceptions.sol";

import {DeployParams} from "../interfaces/Types.sol";
import {RateKeeperFactory} from "../factories/RateKeeperFactory.sol";

import {AttachTestBase} from "./suite/AttachTestBase.sol";

contract RateKeeperFactoryPatchV311Test is AttachTestBase {
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant USDC_PRICE_FEED = 0xb8087b4cEe6bD4AD1b5dEAD85DD27614d96c965a;

    address pool;

    function setUp() public {
        _attachCore();

        vm.skip(block.chainid != 1, "Not Ethereum mainnet");
        vm.skip(
            bytecodeRepository.getLatestPatchVersion("RATE_KEEPER_FACTORY", 3_10) != 3_10,
            "RateKeeperFactory is already patched"
        );

        _uploadContract("RATE_KEEPER_FACTORY", 3_11, type(RateKeeperFactory).creationCode);

        _attachMarketConfigurator();
        pool = _createMockMarket(WETH, WETH_PRICE_FEED);

        vm.prank(riskCurator);
        marketConfigurator.addToken({pool: pool, token: USDC, priceFeed: USDC_PRICE_FEED});
    }

    function test_rate_keeper_update_fails_with_old_rate_keeper_factory() public {
        vm.expectRevert(TokenIsNotQuotedException.selector);
        vm.prank(riskCurator);
        marketConfigurator.updateRateKeeper(
            pool, DeployParams({postfix: "TUMBLER", salt: "NEW SALT", constructorParams: abi.encode(pool, 1 days)})
        );
    }

    function test_rate_keeper_update_succeeds_with_patched_rate_keeper_factory() public {
        _upgradeRateKeeperFactory();

        vm.prank(riskCurator);
        marketConfigurator.updateRateKeeper(
            pool, DeployParams({postfix: "TUMBLER", salt: "NEW SALT", constructorParams: abi.encode(pool, 1 days)})
        );
    }

    function _upgradeRateKeeperFactory() internal {
        vm.prank(crossChainGovernance);
        instanceManager.deploySystemContract("RATE_KEEPER_FACTORY", 3_11, true);

        vm.prank(riskCurator);
        marketConfigurator.upgradeRateKeeperFactory(pool);
    }
}
