// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {
    IConcreteFactory,
    ConcreteFactory,
    ConcreteFactoryBaseSetup,
    VaultProxy
} from "../../common/ConcreteFactoryBaseSetup.t.sol";
import {IUpgradeableVault, UpgradeableVault} from "../../../src/common/UpgradeableVault.sol";
import {ConcreteFactory} from "../../../src/factory/ConcreteFactory.sol";
import {ConcreteStandardVaultImpl} from "../../../src/implementation/ConcreteStandardVaultImpl.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IVaultProxy} from "../../../src/interface/IVaultProxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ConcreteFactory2 is ConcreteFactory {
    uint8 public version;

    function initializeV2(uint8 version_) external reinitializer(version_) {
        version = version_;
    }
}

contract ConcreteFactoryUnitTest is ConcreteFactoryBaseSetup {
    function setUp() public override {
        ConcreteFactoryBaseSetup.setUp();
    }

    function testUpgradeFactory() public {
        address factoryImpl = address(new ConcreteFactory2());
        vm.startPrank(factoryOwner);
        factory.upgradeToAndCall(factoryImpl, abi.encodeCall(ConcreteFactory2.initializeV2, (2)));
        vm.stopPrank();
        assertEq(ConcreteFactory2(address(factory)).version(), 2);
    }

    function testUpgradeFactoryByNonOwner() public {
        address factoryImpl = address(new ConcreteFactory2());
        // OwnableUnauthorizedAccount(address account)
        address nonOwner = makeAddr("nonOwner");
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        factory.upgradeToAndCall(factoryImpl, abi.encodeCall(ConcreteFactory2.initializeV2, (2)));
    }

    function testApproveImplementation() public {
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));
        address fakeImpl = address(new Impl1(makeAddr("fakeFactory")));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        vm.stopPrank();

        assertEq(factory.getImplementationByVersion(1), impl1);
        assertEq(factory.getImplementationByVersion(2), impl2);

        vm.prank(factoryOwner);
        vm.expectRevert(IConcreteFactory.InvalidImplementation.selector);
        factory.approveImplementation(fakeImpl);

        // should revert approving an already approved implementation
        vm.prank(factoryOwner);
        vm.expectRevert(IConcreteFactory.AlreadyApproved.selector);
        factory.approveImplementation(impl1);
    }

    function testDeployProxyUsingImpl1() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        vm.stopPrank();

        address predicted = factory.predictVaultAddress(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"));

        vm.expectEmit(true, true, true, true);
        emit IConcreteFactory.Deployed(predicted, 1, vaultOwner);

        address proxy = factory.create(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"));

        assertEq(Impl1(proxy).implName(), "Vault with Impl1");
        assertEq(Impl1(proxy).implSymbol(), "Impl1Vault");
        assertEq(Impl1(proxy).implVersion(), 1);
        assertEq(Impl1(proxy).owner(), vaultOwner);

        // should revert using version == 0
        vm.expectRevert(IConcreteFactory.InvalidVersion.selector);
        factory.create(0, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"));

        // should revert using version > lastVersion
        uint64 versionTouse = factory.lastVersion() + 1;
        vm.expectRevert(IConcreteFactory.InvalidVersion.selector);
        factory.create(versionTouse, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"));
    }

    function testDeployVaultWithSalt() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        vm.stopPrank();

        bytes32 salt = bytes32(uint256(1));
        address predicted =
            factory.predictVaultAddress(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"), salt);

        vm.expectEmit(true, true, true, true);
        emit IConcreteFactory.Deployed(predicted, 1, vaultOwner);

        address proxy = factory.create(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"), salt);

        assertEq(Impl1(proxy).implName(), "Vault with Impl1");
        assertEq(Impl1(proxy).implSymbol(), "Impl1Vault");
        assertEq(Impl1(proxy).implVersion(), 1);
        assertEq(Impl1(proxy).owner(), vaultOwner);
    }

    function testDeployVaultWithSaultDifferentSenderCreatesDifferentAddress() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));

        bytes32 salt = bytes32(uint256(1));
        bytes32 salt2 = bytes32(uint256(2));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        vm.stopPrank();

        address predicted1 =
            factory.predictVaultAddress(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"), salt);
        address predicted2 =
            factory.predictVaultAddress(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"), salt2);

        assertNotEq(predicted1, predicted2);
    }

    function testDeployUsingBlockedImpl() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.blockImplementation(factory.lastVersion());
        vm.stopPrank();

        vm.expectRevert(IConcreteFactory.ImplementationBlocked.selector);
        factory.create(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"));
    }

    function testMigrateByNonVaultOwner() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        vm.stopPrank();

        address proxy = factory.create(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"));

        // should revert migration if called by non-owner
        vm.expectRevert(IConcreteFactory.NotOwner.selector);
        vm.prank(makeAddr("nonOwner"));
        factory.upgrade(proxy, 2, abi.encode("Vault with Impl2", "Impl2Vault"));
    }

    function testMigrateToOldVersion() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        vm.stopPrank();

        address proxy = factory.create(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"));

        // should revert migration if new version is not greater than current version
        vm.expectRevert(IConcreteFactory.OldVersion.selector);
        vm.prank(vaultOwner);
        factory.upgrade(proxy, 1, abi.encode("Vault with Impl2", "Impl2Vault"));
    }

    function testMigrateNotMigratableVersionParis() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        vm.stopPrank();

        address proxy = factory.create(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"));

        vm.expectRevert(IConcreteFactory.CanNotMigrate.selector);
        vm.prank(vaultOwner);
        factory.upgrade(proxy, 2, abi.encode("Vault with Impl2", "Impl2Vault"));
    }

    function testMigrateImpl1ToImpl2() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        vm.stopPrank();

        address proxy = factory.create(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"));

        assertEq(Impl1(proxy).implName(), "Vault with Impl1");
        assertEq(Impl1(proxy).implSymbol(), "Impl1Vault");
        assertEq(Impl1(proxy).implVersion(), 1);

        // approve migration from impl1 to impl2
        vm.startPrank(factoryOwner);
        factory.setMigratable(1, 2);
        vm.stopPrank();

        assertEq(factory.isMigratable(1, 2), true);
        assertEq(factory.isMigratable(2, 1), false);

        // migrate to impl2
        vm.prank(vaultOwner);
        factory.upgrade(proxy, 2, abi.encode("Vault with Impl2", "Impl2Vault"));

        assertEq(Impl2(proxy).implName(), "Vault with Impl2");
        assertEq(Impl2(proxy).implSymbol(), "Impl2Vault");
        assertEq(Impl2(proxy).implVersion(), 2);

        // should revert setting migration path from new version to old version
        vm.prank(factoryOwner);
        vm.expectRevert(IConcreteFactory.OldVersion.selector);
        factory.setMigratable(2, 1);

        // should revert when migrating to non existing version
        vm.expectRevert(IConcreteFactory.InvalidVersion.selector);
        vm.prank(vaultOwner);
        factory.upgrade(proxy, 3, abi.encode("Vault with Impl3", "Impl3Vault"));
    }

    function testMigrateToBlockedImpl() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        vm.stopPrank();

        address proxy = factory.create(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"));

        // approve migration from impl1 to impl2
        vm.startPrank(factoryOwner);
        factory.setMigratable(1, 2);
        factory.blockImplementation(factory.lastVersion());
        vm.stopPrank();

        assertEq(factory.isMigratable(1, 2), true);
        assertEq(factory.isBlocked(2), true);

        vm.expectRevert(IConcreteFactory.ImplementationBlocked.selector);
        vm.prank(vaultOwner);
        factory.upgrade(proxy, 2, abi.encode("Vault with Impl2", "Impl2Vault"));

        // should revert blocking an already blocked implementation
        vm.prank(factoryOwner);
        vm.expectRevert(IConcreteFactory.AlreadyBlocked.selector);
        factory.blockImplementation(2);
    }

    function testExplicitUpgradeToAndCall() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        vm.stopPrank();

        address proxy = factory.create(1, vaultOwner, abi.encode("Vault with Impl1", "Impl1Vault"));

        assertEq(Impl1(proxy).implName(), "Vault with Impl1");

        vm.prank(vaultOwner);
        vm.expectRevert(abi.encodeWithSelector(VaultProxy.CallerNotProxyAdmin.selector));
        VaultProxy(payable(proxy)).upgradeToAndCall(impl2, abi.encode("Vault with Impl2", "Impl2Vault"));
    }

    function testBatchMigrateSuccess() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        factory.setMigratable(1, 2);
        vm.stopPrank();

        // Create multiple vaults
        address[] memory vaults = new address[](3);
        vaults[0] = factory.create(1, vaultOwner, abi.encode("Vault1", "V1"));
        vaults[1] = factory.create(1, vaultOwner, abi.encode("Vault2", "V2"));
        vaults[2] = factory.create(1, vaultOwner, abi.encode("Vault3", "V3"));

        // Verify initial state
        for (uint256 i = 0; i < vaults.length; i++) {
            assertEq(Impl1(vaults[i]).implVersion(), 1);
        }

        bytes[] memory data = new bytes[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            data[i] = abi.encode("BatchMigrated", string.concat("BM", Strings.toString(i)));
        }

        // Perform batch migration
        vm.prank(vaultOwner);
        factory.batchUpgrade(vaults, 2, data);

        // Verify all vaults migrated successfully
        for (uint256 i = 0; i < vaults.length; i++) {
            assertEq(Impl2(vaults[i]).implVersion(), 2);
            assertEq(Impl2(vaults[i]).implName(), "BatchMigrated");
            assertEq(Impl2(vaults[i]).implSymbol(), string.concat("BM", Strings.toString(i)));
        }
    }

    function testBatchMigrateSingleVault() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        factory.setMigratable(1, 2);
        vm.stopPrank();

        address[] memory vaults = new address[](1);
        vaults[0] = factory.create(1, vaultOwner, abi.encode("SingleVault", "SV"));

        assertEq(Impl1(vaults[0]).implVersion(), 1);

        bytes[] memory data = new bytes[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            data[i] = abi.encode("Migrated", string.concat("M", Strings.toString(i)));
        }

        // Perform batch migration
        vm.prank(vaultOwner);
        factory.batchUpgrade(vaults, 2, data);

        assertEq(Impl2(vaults[0]).implVersion(), 2);
        assertEq(Impl2(vaults[0]).implName(), "Migrated");
        assertEq(Impl2(vaults[0]).implSymbol(), "M0");
    }

    function testBatchMigrateFailsWithDifferentOwners() public {
        address vaultOwner1 = makeAddr("vaultOwner1");
        address vaultOwner2 = makeAddr("vaultOwner2");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        factory.setMigratable(1, 2);
        vm.stopPrank();

        address[] memory vaults = new address[](2);
        vaults[0] = factory.create(1, vaultOwner1, abi.encode("Vault1", "V1"));
        vaults[1] = factory.create(1, vaultOwner2, abi.encode("Vault2", "V2"));

        bytes[] memory data = new bytes[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            data[i] = abi.encode("BatchMigrated", string.concat("BM", Strings.toString(i)));
        }

        // Should fail when trying to migrate vaults with different owners
        vm.expectRevert(IConcreteFactory.NotOwner.selector);
        vm.prank(vaultOwner1);
        factory.batchUpgrade(vaults, 2, data);

        // Verify no vaults were migrated
        assertEq(Impl1(vaults[0]).implVersion(), 1);
        assertEq(Impl1(vaults[1]).implVersion(), 1);
    }

    function testBatchMigrateWithMixedVersions() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        factory.setMigratable(1, 2);
        vm.stopPrank();

        address[] memory vaults = new address[](2);
        vaults[0] = factory.create(1, vaultOwner, abi.encode("Vault1", "V1"));
        vaults[1] = factory.create(1, vaultOwner, abi.encode("Vault2", "V2"));

        // Migrate first vault individually
        vm.prank(vaultOwner);
        factory.upgrade(vaults[0], 2, abi.encode("FirstMigrated", "FM"));

        bytes[] memory data = new bytes[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            data[i] = abi.encode("BatchMigrated", string.concat("BM", Strings.toString(i)));
        }

        // Now try batch migrate both (should fail on first vault - already v2)
        vm.expectRevert(IConcreteFactory.OldVersion.selector);
        vm.prank(vaultOwner);
        factory.batchUpgrade(vaults, 2, data);

        // Verify states
        assertEq(Impl2(vaults[0]).implVersion(), 2);
        assertEq(Impl2(vaults[0]).implName(), "FirstMigrated");
        assertEq(Impl1(vaults[1]).implVersion(), 1);
    }

    function testBatchMigrateWithBlockedImplementation() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        factory.setMigratable(1, 2);
        factory.blockImplementation(2); // Block version 2
        vm.stopPrank();

        address[] memory vaults = new address[](2);
        vaults[0] = factory.create(1, vaultOwner, abi.encode("Vault1", "V1"));
        vaults[1] = factory.create(1, vaultOwner, abi.encode("Vault2", "V2"));

        bytes[] memory data = new bytes[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            data[i] = abi.encode("BatchMigrated", string.concat("BM", Strings.toString(i)));
        }

        // Should fail due to blocked implementation
        vm.expectRevert(IConcreteFactory.ImplementationBlocked.selector);
        vm.prank(vaultOwner);
        factory.batchUpgrade(vaults, 2, data);

        // Verify no vaults were migrated
        assertEq(Impl1(vaults[0]).implVersion(), 1);
        assertEq(Impl1(vaults[1]).implVersion(), 1);
    }

    function testBatchMigrateWithNonMigratableVersions() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        // Don't set migratable path
        vm.stopPrank();

        address[] memory vaults = new address[](2);
        vaults[0] = factory.create(1, vaultOwner, abi.encode("Vault1", "V1"));
        vaults[1] = factory.create(1, vaultOwner, abi.encode("Vault2", "V2"));

        bytes[] memory data = new bytes[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            data[i] = abi.encode("BatchMigrated", string.concat("BM", Strings.toString(i)));
        }

        // Should fail due to non-migratable versions
        vm.expectRevert(IConcreteFactory.CanNotMigrate.selector);
        vm.prank(vaultOwner);
        factory.batchUpgrade(vaults, 2, data);

        // Verify no vaults were migrated
        assertEq(Impl1(vaults[0]).implVersion(), 1);
        assertEq(Impl1(vaults[1]).implVersion(), 1);
    }

    function testBatchMigrateWithInvalidVersion() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        vm.stopPrank();

        address[] memory vaults = new address[](1);
        vaults[0] = factory.create(1, vaultOwner, abi.encode("Vault1", "V1"));

        bytes[] memory data = new bytes[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            data[i] = abi.encode("BatchMigrated", string.concat("BM", Strings.toString(i)));
        }

        // Should fail due to invalid version (version 3 doesn't exist)
        vm.expectRevert(IConcreteFactory.InvalidVersion.selector);
        vm.prank(vaultOwner);
        factory.batchUpgrade(vaults, 3, data);

        // Verify vault wasn't migrated
        assertEq(Impl1(vaults[0]).implVersion(), 1);
    }

    function testRegisterVault() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));

        // Create an external implementation that doesn't enforce factory checks
        address externalImpl = address(new ExternalImpl(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        vm.stopPrank();

        // Create a vault through the factory
        address factoryVault = factory.create(1, vaultOwner, abi.encode("FactoryVault", "FV"));
        assertEq(factory.isRegisteredVault(factoryVault), true);

        // Create an external vault using the ExternalImpl, this mock proxy is pre-set to be owned by the factory
        // this external vault reports to be v1
        address externalVault = address(
            new MockVaultProxy(
                address(factory),
                externalImpl,
                abi.encodeCall(IUpgradeableVault.initialize, (1, vaultOwner, abi.encode("ExternalVault", "EV")))
            )
        );

        // Verify the external vault is not registered initially
        assertEq(factory.isRegisteredVault(externalVault), false);

        // Register the external vault
        vm.prank(factoryOwner);
        factory.registerVault(externalVault);
        assertEq(factory.isRegisteredVault(externalVault), true);

        // Verify the vault can now be upgraded through the factory
        address impl2 = address(new Impl2(address(factory)));
        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl2);
        factory.setMigratable(1, 2);
        vm.stopPrank();

        vm.prank(vaultOwner);
        factory.upgrade(externalVault, 2, abi.encode("ExternalVaultUpgraded", "EVU"));

        assertEq(Impl2(externalVault).implVersion(), 2);
        assertEq(Impl2(externalVault).implName(), "ExternalVaultUpgraded");
    }

    function testRegisterVaultAlreadyRegistered() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        vm.stopPrank();

        // Create a vault through the factory
        address factoryVault = factory.create(1, vaultOwner, abi.encode("FactoryVault", "FV"));
        assertEq(factory.isRegisteredVault(factoryVault), true);

        // Try to register the same vault again
        vm.prank(factoryOwner);
        vm.expectRevert(IConcreteFactory.VaultAlreadyRegistered.selector);
        factory.registerVault(factoryVault);
    }

    function testRegisterVaultInvalidFactory() public {
        address vaultOwner = makeAddr("vaultOwner");

        // Create a temporary factory with a different address
        address differentFactoryImpl = address(new ConcreteFactory());
        address differentFactory =
            address(new ERC1967Proxy(differentFactoryImpl, abi.encodeCall(ConcreteFactory.initialize, (factoryOwner))));

        address impl1 = address(new Impl1(differentFactory));

        vm.startPrank(factoryOwner);
        ConcreteFactory(differentFactory).approveImplementation(impl1);
        vm.stopPrank();

        // Create a vault with the different factory
        address externalVault =
            ConcreteFactory(differentFactory).create(1, vaultOwner, abi.encode("ExternalVault", "EV"));

        // Try to register a vault that doesn't belong to this factory
        vm.prank(factoryOwner);
        vm.expectRevert(IConcreteFactory.InvalidImplementation.selector);
        factory.registerVault(externalVault);
    }

    function testRegisterVaultNonOwner() public {
        address vaultOwner = makeAddr("vaultOwner");

        // Create a temporary factory
        address tempFactoryImpl = address(new ConcreteFactory());
        address tempFactory =
            address(new ERC1967Proxy(tempFactoryImpl, abi.encodeCall(ConcreteFactory.initialize, (factoryOwner))));

        address impl1 = address(new Impl1(tempFactory));

        vm.startPrank(factoryOwner);
        ConcreteFactory(tempFactory).approveImplementation(impl1);
        vm.stopPrank();

        // Create a vault with the temporary factory
        address externalVault = ConcreteFactory(tempFactory).create(1, vaultOwner, abi.encode("ExternalVault", "EV"));

        // Try to register as non-owner
        vm.prank(vaultOwner);
        vm.expectRevert();
        factory.registerVault(externalVault);
    }

    function testRegisterVaultZeroAddress() public {
        // Try to register zero address
        vm.prank(factoryOwner);
        vm.expectRevert(IConcreteFactory.ZeroAddress.selector);
        factory.registerVault(address(0));
    }

    function testUpgradeNotAVault() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        factory.setMigratable(1, 2);
        vm.stopPrank();

        // Create a vault through the factory
        factory.create(1, vaultOwner, abi.encode("FactoryVault", "FV"));

        // Create a random address that is not a vault
        address randomAddress = makeAddr("randomAddress");

        // Try to upgrade a non-vault address
        vm.prank(vaultOwner);
        vm.expectRevert(IConcreteFactory.NotRegisteredVault.selector);
        factory.upgrade(randomAddress, 2, abi.encode("Upgrade", "U"));
    }

    function testBatchUpgradeInvalidDataLength() public {
        // create array of fake vaults
        address[] memory vaults = new address[](1);
        vaults[0] = makeAddr("vault");
        bytes[] memory data = new bytes[](0);

        vm.expectRevert(IConcreteFactory.InvalidDataLength.selector);
        factory.batchUpgrade(vaults, 2, data);
    }

    function testBatchUpgradeNotAVault() public {
        address vaultOwner = makeAddr("vaultOwner");
        address impl1 = address(new Impl1(address(factory)));
        address impl2 = address(new Impl2(address(factory)));

        vm.startPrank(factoryOwner);
        factory.approveImplementation(impl1);
        factory.approveImplementation(impl2);
        factory.setMigratable(1, 2);
        vm.stopPrank();

        // Create a vault through the factory
        address factoryVault = factory.create(1, vaultOwner, abi.encode("FactoryVault", "FV"));

        // Create an array with a mix of valid vaults and invalid addresses
        address[] memory vaults = new address[](3);
        vaults[0] = factoryVault; // Valid vault
        vaults[1] = makeAddr("randomAddress1"); // Invalid address
        vaults[2] = makeAddr("randomAddress2"); // Invalid address

        bytes[] memory data = new bytes[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            data[i] = abi.encode("BatchUpgrade", string.concat("BU", Strings.toString(i)));
        }

        // Try to batch upgrade with invalid addresses
        vm.prank(vaultOwner);
        vm.expectRevert(IConcreteFactory.NotRegisteredVault.selector);
        factory.batchUpgrade(vaults, 2, data);
    }
}

contract Impl1 is ConcreteStandardVaultImpl {
    string public implName;
    string public implSymbol;
    uint64 public implVersion;

    constructor(address factory) ConcreteStandardVaultImpl(factory) {}

    function _initialize(
        uint64 initialVersion,
        address,
        /*owner*/
        bytes memory data
    )
        internal
        virtual
        override
    {
        (string memory name, string memory symbol) = abi.decode(data, (string, string));

        implName = name;
        implSymbol = symbol;
        implVersion = initialVersion;
    }

    function _upgrade(
        uint64,
        /* oldVersion */
        uint64,
        /* newVersion */
        bytes calldata /* data */
    )
        internal
        virtual
        override
    {
        revert();
    }
}

contract Impl2 is Impl1 {
    constructor(address factory) Impl1(factory) {}

    function _initialize(
        uint64 initialVersion,
        address,
        /*owner*/
        bytes memory data
    )
        internal
        virtual
        override
    {
        (string memory name, string memory symbol) = abi.decode(data, (string, string));

        implName = name;
        implSymbol = symbol;
        implVersion = initialVersion;
    }

    function _upgrade(
        uint64,
        /* oldVersion */
        uint64 newVersion,
        bytes calldata data
    )
        internal
        virtual
        override
    {
        (string memory name, string memory symbol) = abi.decode(data, (string, string));

        implName = name;
        implSymbol = symbol;
        implVersion = newVersion;
    }
}

contract ExternalImpl is OwnableUpgradeable {
    string public implName;
    string public implSymbol;
    uint64 public implVersion;

    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function initialize(
        uint64,
        /**
         * initialVersion
         */
        address owner_,
        bytes calldata
    )
        /**
         * data
         */
        external
        initializer
    {
        __Ownable_init(owner_);
    }

    function upgrade(uint64 newVersion, bytes calldata data) external {}

    function version() external pure returns (uint64) {
        return 1;
    }
}

contract MockVaultProxy is ERC1967Proxy, IVaultProxy {
    // An immutable address for the admin to avoid unnecessary SLOADs before each call.
    address private immutable _admin;

    /**
     * @dev The proxy caller is the current admin, and can't fallback to the proxy target.
     */
    error ProxyDeniedAdminAccess();

    /**
     * @dev Initializes an upgradeable proxy managed by `msg.sender`,
     * backed by the implementation at `logic`, and optionally initialized with `data` as explained in
     * {ERC1967Proxy-constructor}.
     */
    constructor(address admin, address logic, bytes memory data) ERC1967Proxy(logic, data) {
        _admin = admin;
        // Set the storage value and emit an event for ERC-1967 compatibility
        ERC1967Utils.changeAdmin(_proxyAdmin());
    }

    function upgradeToAndCall(address newImplementation, bytes calldata data) external {
        if (msg.sender != _proxyAdmin()) {
            revert ProxyDeniedAdminAccess();
        }

        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }

    /**
     * @dev Returns the admin of this proxy.
     */
    function _proxyAdmin() internal view returns (address) {
        return _admin;
    }
}
