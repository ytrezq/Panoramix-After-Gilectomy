// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { MapleStrategyFactory } from "../../contracts/proxy/MapleStrategyFactory.sol";
import { MapleAaveStrategy }    from "../../contracts/MapleAaveStrategy.sol";
import { MapleBasicStrategy }   from "../../contracts/MapleBasicStrategy.sol";
import { MapleSkyStrategy }     from "../../contracts/MapleSkyStrategy.sol";

import { MockVault }                                                        from "../utils/Mocks.sol";
import { AaveStrategyTestBase, BasicStrategyTestBase, SkyStrategyTestBase } from "../utils/TestBase.sol";

contract MapleBasicStrategyCreateInstanceTests is BasicStrategyTestBase {

    event Initialized(address indexed pool_, address indexed poolManager_, address indexed vault_);

    function setUp() public override {
        super.setUp();

        vm.startPrank(governor);
        factory = new MapleStrategyFactory(address(globals));
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);

        globals.__setCanDeploy(true);
        vm.stopPrank();
    }

    function test_createInstance_invalidCaller() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(vault));

        globals.__setCanDeploy(false);

        vm.expectRevert("MSF:CI:CANNOT_DEPLOY");
        factory.createInstance(calldata_, "SALT");

        globals.__setCanDeploy(true);

        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_zeroPool() external {
        bytes memory calldata_ = abi.encode(address(0));

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_invalidFactory() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(vault));

        globals.__setIsInstanceOf(false);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_invalidInstance() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(vault));

        poolManagerFactory.__setIsInstance(false);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_invalidStrategyAsset() external {
        vault = new MockVault(address(0));

        bytes memory calldata_ = abi.encode(address(poolManager), address(vault));

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_success() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(vault));

        vm.expectEmit();
        emit Initialized(address(pool), address(poolManager), address(vault));

        MapleBasicStrategy strategy_ = MapleBasicStrategy(factory.createInstance(calldata_, "SALT"));

        assertEq(strategy_.locked(), 1);

        assertEq(strategy_.fundsAsset(),    address(asset));
        assertEq(strategy_.pool(),          address(pool));
        assertEq(strategy_.poolManager(),   address(poolManager));
        assertEq(strategy_.strategyVault(), address(vault));
    }

}

contract MapleSkyStrategyCreateInstanceTests is SkyStrategyTestBase {

    event Initialized(
        address indexed pool,
        address indexed poolManager,
        address indexed psm,
        address savingsUsds,
        address usds
    );

    function setUp() public override {
        super.setUp();

        vm.startPrank(governor);
        factory = new MapleStrategyFactory(address(globals));
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);

        globals.__setCanDeploy(true);
        vm.stopPrank();
    }

    function test_createInstance_invalidCaller() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(vault), address(psm));

        globals.__setCanDeploy(false);

        vm.expectRevert("MSF:CI:CANNOT_DEPLOY");
        factory.createInstance(calldata_, "SALT");

        globals.__setCanDeploy(true);

        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_zeroPool() external {
        bytes memory calldata_ = abi.encode(address(0), address(vault), address(psm));

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_invalidFactory() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(vault), address(psm));

        globals.__setIsInstanceOf(false);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_invalidInstance() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(vault), address(psm));

        poolManagerFactory.__setIsInstance(false);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_invalidSavingsUsds() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(0), address(psm));

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_invalidPSM() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(vault), address(0));

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_nonAuthorizedPSM() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(vault), address(psm));

        globals.__setIsInstanceOf(false);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_invalidGemPSM() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(vault), address(psm));

        psm.__setGem(address(makeAddr("newGem")));

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_invalidUsdsPSM() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(vault), address(psm));

        psm.__setUsds(address(makeAddr("newUsds")));

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(calldata_, "SALT");
    }

    function test_createInstance_success() external {
        bytes memory calldata_ = abi.encode(address(poolManager), address(vault), address(psm));

        vm.expectEmit();
        emit Initialized(address(pool), address(poolManager), address(psm), address(vault), address(usds));

        MapleSkyStrategy strategy_ = MapleSkyStrategy(factory.createInstance(calldata_, "SALT"));

        assertEq(strategy_.locked(), 1);

        assertEq(strategy_.pool(),        address(pool));
        assertEq(strategy_.poolManager(), address(poolManager));
        assertEq(strategy_.fundsAsset(),  address(asset));
        assertEq(strategy_.usds(),        address(usds));
        assertEq(strategy_.psm(),         address(psm));
    }

}

contract MapleAaveStrategyCreateInstanceTests is AaveStrategyTestBase {

    event Initialized(
        address indexed aavePool,
        address indexed aaveToken,
        address indexed pool,
        address fundsAsset,
        address poolManager
    );

    bytes32 salt = "SALT";

    function setUp() public override {
        super.setUp();

        vm.startPrank(governor);
        factory = new MapleStrategyFactory(address(globals));
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);
        vm.stopPrank();
    }

    function test_createInstance_invalidCaller() external {
        globals.__setCanDeploy(false);

        vm.expectRevert("MSF:CI:CANNOT_DEPLOY");
        factory.createInstance(abi.encode(address(poolManager), address(aaveToken)), salt);
    }

    function test_createInstance_zeroPool() external {
        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(abi.encode(address(0), address(aaveToken)), salt);
    }

    function test_createInstance_zeroAaveToken() external {
        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(abi.encode(address(poolManager), address(0)), salt);
    }

    function test_createInstance_invalidPoolManagerFactory() external {
        globals.__setIsInstanceOf(false);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(abi.encode(address(poolManager), address(aaveToken)), salt);
    }

    function test_createInstance_invalidPoolManagerInstance() external {
        poolManagerFactory.__setIsInstance(false);

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(abi.encode(address(poolManager), address(aaveToken)), salt);
    }

    // TODO: Update `MapleGlobalsMock` to simulate this test case.
    // function test_createInstance_invalidAavePool() external {
    //     globals.__setIsInstanceOf(false);

    //     vm.expectRevert("MPF:CI:FAILED");
    //     factory.createInstance(abi.encode(address(pool), address(aaveToken)), salt);
    // }

    function test_createInstance_underlyingAssetMismatch() external {
        aaveToken.__setUnderlyingAsset(address(1337));

        vm.expectRevert("MPF:CI:FAILED");
        factory.createInstance(abi.encode(address(poolManager), address(aaveToken)), salt);
    }

    function test_createInstance_success() external {
        vm.expectEmit();
        emit Initialized(address(aavePool), address(aaveToken), address(pool), address(asset), address(poolManager));

        MapleAaveStrategy strategy_ = MapleAaveStrategy(factory.createInstance(
            abi.encode(address(poolManager), address(aaveToken)),
            salt
        ));

        assertEq(strategy_.aavePool(),    address(aavePool));
        assertEq(strategy_.aaveToken(),   address(aaveToken));
        assertEq(strategy_.fundsAsset(),  address(asset));
        assertEq(strategy_.locked(),      1);
        assertEq(strategy_.pool(),        address(pool));
        assertEq(strategy_.poolManager(), address(poolManager));
    }

}
