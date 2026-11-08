// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { Test } from "../../modules/forge-std/src/Test.sol";

import { SyrupRateProvider } from "../../contracts/utils/SyrupRateProvider.sol";

import { MockERC20, MockPool } from "../utils/Mocks.sol";

contract SyrupRateProviderTests is Test {

    MockERC20 asset;
    MockPool pool;

    SyrupRateProvider rateProvider;

    function setUp() public {
        asset = new MockERC20("USDC", "USDC", 6);
        pool  = new MockPool("MaplePool", "MP", 18, address(asset), address(0));

        rateProvider = new SyrupRateProvider(address(pool));

        pool.__setConversionRate(1e6);
    }

    function test_constructor_success() external {
        rateProvider = new SyrupRateProvider(address(pool));

        assertEq(rateProvider.pool(), address(pool));
    }

    function test_getRate() external {
        vm.expectCall(address(pool), abi.encodeWithSelector(MockPool.convertToExitAssets.selector, 1e18));

        uint256 rate = rateProvider.getRate();

        assertEq(rate, 1e6);

        pool.__setConversionRate(2e6);

        rate = rateProvider.getRate();

        assertEq(rate, 2e6);
    }

}
