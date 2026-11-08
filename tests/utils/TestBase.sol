// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { console2 as console, Test } from "../../modules/forge-std/src/Test.sol";
import { MockERC20 }                 from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { MapleWithdrawalManagerFactory }     from "../../contracts/proxy/MapleWithdrawalManagerFactory.sol";
import { MapleWithdrawalManagerInitializer } from "../../contracts/proxy/MapleWithdrawalManagerInitializer.sol";

import { MapleWithdrawalManagerHarness }                       from "./Harnesses.sol";
import { MockFactory, MockGlobals, MockPool, MockPoolManager } from "./Mocks.sol";

contract TestBase is Test {

    address internal governor         = makeAddr("governor");
    address internal lp               = makeAddr("lp");
    address internal operationalAdmin = makeAddr("operationalAdmin");
    address internal poolDelegate     = makeAddr("poolDelegate");
    address internal redeemer         = makeAddr("redeemer");
    address internal securityAdmin    = makeAddr("securityAdmin");

    address internal implementation;
    address internal initializer;
    address internal pm;
    address internal wm;

    MockERC20       internal asset;
    MockGlobals     internal globals;
    MockFactory     internal poolManagerFactory;
    MockPool        internal pool;
    MockPoolManager internal poolManager;

    MapleWithdrawalManagerFactory internal factory;
    MapleWithdrawalManagerHarness internal withdrawalManager;

    function setUp() public virtual {
        // Create all mocks.
        asset              = new MockERC20("Wrapped Ether", "WETH", 18);
        globals            = new MockGlobals(address(governor));
        pool               = new MockPool("Maple Pool", "MP-WETH", 18, address(asset), poolDelegate);
        poolManager        = new MockPoolManager(address(pool), poolDelegate, address(globals));
        poolManagerFactory = new MockFactory();

        pool.__setPoolManager(address(poolManager));

        poolManager.__setFactory(address(poolManagerFactory));

        poolManagerFactory.__setIsInstance(true);

        globals.__setCanDeploy(true);
        globals.__setIsInstanceOf(true);
        globals.__setOperationalAdmin(operationalAdmin);
        globals.__setSecurityAdmin(securityAdmin);

        implementation = address(new MapleWithdrawalManagerHarness());
        initializer    = address(new MapleWithdrawalManagerInitializer());

        vm.startPrank(governor);
        factory = new MapleWithdrawalManagerFactory(address(globals));
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);
        vm.stopPrank();

        // Create the withdrawal manager instance.
        withdrawalManager = MapleWithdrawalManagerHarness(factory.createInstance({
            arguments_: abi.encode(address(pool)),
            salt_:      "SALT"
        }));

        pm = address(poolManager);
        wm = address(withdrawalManager);
    }

    function assertRequest(uint128 requestId, address owner, uint256 shares) internal {
        ( address owner_, uint256 shares_ ) = withdrawalManager.requests(requestId);

        assertEq(owner_,  owner);
        assertEq(shares_, shares);
    }

    function assertQueue(uint128 nextRequestId, uint128 lastRequestId) internal {
        ( uint128 nextRequestId_, uint128 lastRequestId_ ) = withdrawalManager.queue();

        assertEq(nextRequestId_, nextRequestId);
        assertEq(lastRequestId_, lastRequestId);
    }

}
