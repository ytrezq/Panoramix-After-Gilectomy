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
        vm.skip(block.chainid != 1, "Not Ethereum mainnet");
        _setUp();
        vm.skip(
            bytecodeRepository.getLatestPatchVersion("RATE_KEEPER_FACTORY", 3_10) != 3_10,
            "RateKeeperFactory is already patched"
        );

        _uploadContract("RATE_KEEPER_FACTORY", 3_11, type(RateKeeperFactory).creationCode);

        _allowPriceFeed(WETH, WETH_PRICE_FEED);
        _allowPriceFeed(USDC, USDC_PRICE_FEED);

        deal({token: WETH, to: address(marketConfigurator), give: 1e5});
        MarketParams memory marketParams = _getDefaultMarketParams(WETH);
        marketParams.underlyingPriceFeed = WETH_PRICE_FEED;
        pool = _createMockMarket(WETH, marketParams);

        TokenParams memory tokenParams = _getDefaultTokenParams(USDC);
        tokenParams.priceFeed = USDC_PRICE_FEED;
        _addToken(pool, tokenParams);
    }

    function test_rate_keeper_update_fails_with_old_rate_keeper_factory() public {
        vm.expectRevert(TokenIsNotQuotedException.selector);
        _omniPrank(riskCurator);
        marketConfigurator.updateRateKeeper(
            pool, DeployParams({postfix: "TUMBLER", salt: "NEW SALT", constructorParams: abi.encode(pool, 1 days)})
        );
    }

    function test_rate_keeper_update_succeeds_with_patched_rate_keeper_factory() public {
        _upgradeRateKeeperFactory();

        _omniPrank(riskCurator);
        marketConfigurator.updateRateKeeper(
            pool, DeployParams({postfix: "TUMBLER", salt: "NEW SALT", constructorParams: abi.encode(pool, 1 days)})
        );
    }

    function _upgradeRateKeeperFactory() internal {
        vm.prank(crossChainGovernance);
        instanceManager.deploySystemContract("RATE_KEEPER_FACTORY", 3_11, true);

        _omniPrank(riskCurator);
        marketConfigurator.upgradeRateKeeperFactory(pool);
    }
}
