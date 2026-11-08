// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcreteFactoryBaseSetup} from "./ConcreteFactoryBaseSetup.t.sol";
import {ConcreteBridgedAsyncVaultImpl} from "../../src/implementation/ConcreteBridgedVaultImpl.sol";
import {IConcreteBridgedAsyncVaultImpl} from "../../src/interface/IConcreteBridgedAsyncVaultImpl.sol";
import {ERC20Mock} from "../mock/ERC20Mock.sol";
import {AllocateModule} from "../../src/module/AllocateModule.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../src/lib/Roles.sol";

contract TestBaseBridgedAsyncSetup is ConcreteFactoryBaseSetup {
    ConcreteBridgedAsyncVaultImpl public concreteBridgedAsyncVaultImpl;

    function setUp() public virtual override {
        ConcreteFactoryBaseSetup.setUp();

        concreteBridgedAsyncVaultImpl = new ConcreteBridgedAsyncVaultImpl(address(factory));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(address(concreteBridgedAsyncVaultImpl));
        vm.stopPrank();

        assertEq(factory.getImplementationByVersion(1), address(concreteBridgedAsyncVaultImpl));

        vm.label(address(factory), "factory");
        vm.label(address(factoryOwner), "factoryOwner");
        vm.label(address(concreteBridgedAsyncVaultImpl), "concreteBridgedAsyncVaultImpl");
    }
}

contract ConcreteBridgedAsyncVaultImplBaseSetup is TestBaseBridgedAsyncSetup {
    address public vaultOwner;
    address public vaultManager;
    address public hookManager;
    address public strategyOperator;
    address public allocator;
    address public withdrawalManager;

    ERC20Mock public asset;
    AllocateModule public allocateModule;
    ConcreteBridgedAsyncVaultImpl public concreteBridgedAsyncVault;

    function setUp() public virtual override {
        TestBaseBridgedAsyncSetup.setUp();

        vaultOwner = makeAddr("vaultOwner");
        vaultManager = makeAddr("vaultManager");
        hookManager = makeAddr("hookManager");
        strategyOperator = makeAddr("strategyOperator");
        allocator = makeAddr("allocator");
        withdrawalManager = makeAddr("withdrawalManager");

        asset = new ERC20Mock();
        allocateModule = new AllocateModule();

        concreteBridgedAsyncVault = ConcreteBridgedAsyncVaultImpl(
            factory.create(
                1,
                vaultOwner,
                abi.encode(
                    address(allocateModule), address(asset), vaultManager, "Concrete Bridged Async Vault", "CBAVault"
                )
            )
        );

        vm.label(address(allocateModule), "allocateModule");
        vm.label(address(concreteBridgedAsyncVault), "concreteBridgedAsyncVault");
        vm.label(address(asset), "asset");

        assertEq(concreteBridgedAsyncVault.asset(), address(asset));
        assertEq(concreteBridgedAsyncVault.name(), "Concrete Bridged Async Vault");
        assertEq(concreteBridgedAsyncVault.symbol(), "CBAVault");
        assertEq(concreteBridgedAsyncVault.allocateModule(), address(allocateModule));

        // Grant roles
        vm.startPrank(vaultManager);
        concreteBridgedAsyncVault.grantRole(RolesLib.STRATEGY_MANAGER, strategyOperator);
        concreteBridgedAsyncVault.grantRole(RolesLib.ALLOCATOR, allocator);
        concreteBridgedAsyncVault.grantRole(RolesLib.HOOK_MANAGER, hookManager);
        concreteBridgedAsyncVault.grantRole(RolesLib.WITHDRAWAL_MANAGER, withdrawalManager);
        vm.stopPrank();
    }
}

