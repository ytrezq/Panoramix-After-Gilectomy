// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {
    IConcreteFactory,
    ConcreteFactoryBaseSetup,
    VaultProxy,
    IConcreteAsyncVaultImpl,
    ConcreteAsyncVaultImpl,
    TestBaseAsyncSetup
} from "./TestBaseAsyncSetup.t.sol";
import {ConcreteAsyncVaultImpl} from "../../src/implementation/ConcreteAsyncVaultImpl.sol";
import {IConcreteAsyncVaultImpl} from "../../src/interface/IConcreteAsyncVaultImpl.sol";
import {ERC20Mock} from "../mock/ERC20Mock.sol";
import {AllocateModule} from "../../src/module/AllocateModule.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../src/lib/Roles.sol";

contract ConcreteAsyncVaultImplBaseSetup is TestBaseAsyncSetup {
    address public vaultOwner;
    address public vaultManager;
    address public hookManager;
    address public strategyOperator;
    address public allocator;
    address public withdrawalManager;

    ERC20Mock public asset;
    AllocateModule public allocateModule;
    ConcreteAsyncVaultImpl public concreteAsyncVault;

    function setUp() public virtual override {
        TestBaseAsyncSetup.setUp();

        vaultOwner = makeAddr("vaultOwner");
        vaultManager = makeAddr("vaultManager");
        hookManager = makeAddr("hookManager");
        strategyOperator = makeAddr("strategyOperator");
        allocator = makeAddr("allocator");
        withdrawalManager = makeAddr("withdrawalManager");

        asset = new ERC20Mock();
        allocateModule = new AllocateModule();
        concreteAsyncVault = ConcreteAsyncVaultImpl(
            factory.create(
                1,
                vaultOwner,
                abi.encode(address(allocateModule), address(asset), vaultManager, "Concrete Async Vault", "CAVault")
            )
        );

        vm.label(address(allocateModule), "allocateModule");
        vm.label(address(concreteAsyncVault), "concreteAsyncVault");
        vm.label(address(asset), "asset");

        assertEq(concreteAsyncVault.asset(), address(asset));
        assertEq(concreteAsyncVault.name(), "Concrete Async Vault");
        assertEq(concreteAsyncVault.symbol(), "CAVault");
        assertEq(concreteAsyncVault.allocateModule(), address(allocateModule));

        // grant strategy operator role to strategy operator
        vm.startPrank(vaultManager);
        concreteAsyncVault.grantRole(RolesLib.STRATEGY_MANAGER, strategyOperator);
        // grant allocator role to allocator
        concreteAsyncVault.grantRole(RolesLib.ALLOCATOR, allocator);
        // grant hook manager role to hook manager
        concreteAsyncVault.grantRole(RolesLib.HOOK_MANAGER, hookManager);
        // grant withdrawal manager role to withdrawal manager
        concreteAsyncVault.grantRole(RolesLib.WITHDRAWAL_MANAGER, withdrawalManager);
        vm.stopPrank();
    }
}
