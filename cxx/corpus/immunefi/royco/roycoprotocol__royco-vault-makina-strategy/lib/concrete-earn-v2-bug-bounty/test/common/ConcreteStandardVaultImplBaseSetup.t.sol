// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {
    IConcreteFactory,
    ConcreteFactoryBaseSetup,
    VaultProxy,
    IConcreteStandardVaultImpl,
    ConcreteStandardVaultImpl,
    TestBaseSetup
} from "./TestBaseSetup.t.sol";
import {ERC20Mock} from "../mock/ERC20Mock.sol";
import {AllocateModule} from "../../src/module/AllocateModule.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../src/lib/Roles.sol";

contract ConcreteStandardVaultImplBaseSetup is TestBaseSetup {
    address public vaultOwner;
    address public vaultManager;
    address public hookManager;
    address public strategyOperator;
    address public allocator;

    ERC20Mock public asset;
    AllocateModule public allocateModule;
    ConcreteStandardVaultImpl public concreteStandardVault;

    function setUp() public virtual override {
        TestBaseSetup.setUp();

        vaultOwner = makeAddr("vaultOwner");
        vaultManager = makeAddr("vaultManager");
        hookManager = makeAddr("hookManager");
        strategyOperator = makeAddr("strategyOperator");
        allocator = makeAddr("allocator");

        asset = new ERC20Mock();
        allocateModule = new AllocateModule();
        concreteStandardVault = ConcreteStandardVaultImpl(
            factory.create(
                1,
                vaultOwner,
                abi.encode(address(allocateModule), address(asset), vaultManager, "Concrete Standard Vault", "CSVault")
            )
        );

        vm.label(address(allocateModule), "allocateModule");
        vm.label(address(concreteStandardVault), "concreteStandardVault");
        vm.label(address(asset), "asset");

        assertEq(concreteStandardVault.asset(), address(asset));
        assertEq(concreteStandardVault.name(), "Concrete Standard Vault");
        assertEq(concreteStandardVault.symbol(), "CSVault");
        assertEq(concreteStandardVault.allocateModule(), address(allocateModule));

        // grant strategy operator role to strategy operator
        vm.startPrank(vaultManager);
        concreteStandardVault.grantRole(RolesLib.STRATEGY_MANAGER, strategyOperator);
        // grant allocator role to allocator
        concreteStandardVault.grantRole(RolesLib.ALLOCATOR, allocator);
        // grant hook manager role to hook manager
        concreteStandardVault.grantRole(RolesLib.HOOK_MANAGER, hookManager);
        vm.stopPrank();
    }
}
