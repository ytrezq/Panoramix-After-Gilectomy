// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IConcreteStandardVaultImpl} from "../../src/interface/IConcreteStandardVaultImpl.sol";
import {IStrategyTemplate} from "../../src/interface/IStrategyTemplate.sol";
import {IAllocateModule} from "../../src/interface/IAllocateModule.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../mock/ERC20Mock.sol";
import {TestBaseSetup} from "../common/TestBaseSetup.t.sol";
import {ConcreteStandardVaultImpl} from "../../src/implementation/ConcreteStandardVaultImpl.sol";
import {AllocateModule} from "../../src/module/AllocateModule.sol";
import {ActorUtil} from "./helpers/ActorUtil.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../src/lib/Roles.sol";

/**
 * @title InvariantTestBase
 * @dev Base contract for invariant testing
 */
abstract contract InvariantTestBase is Test, TestBaseSetup {
    uint256 public constant INITIAL_BALANCE = 1000000e18; // 1M tokens per user

    // Core contracts
    ConcreteStandardVaultImpl public vault;
    ERC20Mock public asset;
    AllocateModule public allocateModule;

    address public vaultManager;
    address public strategyOperator;
    address public allocator;
    address public feeRecipient;
    // Multi-user setup
    ActorUtil internal actorUtil;

    function setUp() public virtual override {
        TestBaseSetup.setUp();

        // Deploy asset token
        asset = new ERC20Mock();
        vm.label(address(asset), "asset");

        // Deploy AllocateModule
        allocateModule = new AllocateModule();
        vm.label(address(allocateModule), "allocateModule");

        // Create vault using factory
        vm.prank(factoryOwner);
        vaultManager = makeAddr("vaultManager");

        bytes memory vaultData = abi.encode(address(allocateModule), address(asset), vaultManager, "Test Vault", "TV");

        address vaultAddress = factory.create(1, vaultManager, vaultData);
        vault = ConcreteStandardVaultImpl(vaultAddress);
        vm.label(address(vault), "vault");

        // Setup roles
        strategyOperator = makeAddr("strategyOperator");
        allocator = makeAddr("allocator");
        feeRecipient = makeAddr("feeRecipient");

        vm.startPrank(vaultManager);
        vault.grantRole(RolesLib.STRATEGY_MANAGER, strategyOperator);
        vault.grantRole(RolesLib.ALLOCATOR, allocator);
        vm.stopPrank();

        // Setup users
        _setupActors();
    }

    function _setupActors() internal {
        actorUtil = new ActorUtil();
        actorUtil.includeActor(vaultManager); // index 0
        actorUtil.includeActor(strategyOperator); // index 1
        actorUtil.includeActor(allocator); // index 2
        actorUtil.includeActor(factoryOwner); // index 3
        actorUtil.includeActor(feeRecipient); // index 4

        address user = makeAddr("user1");
        actorUtil.includeActor(user); // index 5

        // Give each user initial token balance
        asset.mint(user, INITIAL_BALANCE);
    }
}
