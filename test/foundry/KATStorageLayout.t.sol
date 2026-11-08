// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {EndpointV2Mock} from "@layerzerolabs/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol";

import {KATCustomOFTAdapterUpgradeable, IKATVault} from "../../contracts/KATCustomOFTAdapterUpgradeable.sol";
import {KATOFTAdapterUpgradeable} from "../../contracts/KATOFTAdapterUpgradeable.sol";
import {KATOFTAdapterStorageLayout} from "../../contracts/KATOFTAdapterStorageLayout.sol";
import {MyERC20Mock} from "../../contracts/mocks/MyERC20Mock.sol";
import {KATVaultMock} from "./utils/KATVaultMock.sol";

/**
 * @title KATStorageLayoutTest
 * @notice Tests for EIP-7201 storage layout and upgrade safety
 */
contract KATStorageLayoutTest is Test, KATOFTAdapterStorageLayout {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    MyERC20Mock public token;
    EndpointV2Mock public lzEndpoint;
    ProxyAdmin public proxyAdmin;
    KATVaultMock public vault;

    function setUp() public {
        token = new MyERC20Mock("Test Token", "TEST");
        lzEndpoint = new EndpointV2Mock(1, address(this));
        proxyAdmin = new ProxyAdmin(address(this));
        vault = new KATVaultMock();
    }

    /// @notice Verify EIP-7201 storage slot calculation
    function test_storageSlotCalculation() public pure {
        bytes32 namespaceHash = keccak256(bytes("kat.oft.adapter"));
        uint256 namespaceHashMinusOne = uint256(namespaceHash) - 1;
        bytes32 encoded = keccak256(abi.encode(namespaceHashMinusOne));
        bytes32 calculatedSlot = encoded & ~bytes32(uint256(0xff));

        assertEq(
            calculatedSlot, OFT_ADAPTER_STORAGE_LOCATION, "Storage slot calculation does not match EIP-7201 formula"
        );
    }

    /// @notice Verify vault storage persists after upgrade
    function test_vaultStoragePersistsAfterUpgrade() public {
        KATCustomOFTAdapterUpgradeable customImpl =
            new KATCustomOFTAdapterUpgradeable(address(token), address(lzEndpoint));

        bytes memory initData =
            abi.encodeWithSelector(KATCustomOFTAdapterUpgradeable.initialize.selector, address(this));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(customImpl), address(proxyAdmin), initData);

        KATCustomOFTAdapterUpgradeable customAdapter = KATCustomOFTAdapterUpgradeable(address(proxy));

        customAdapter.setVault(address(vault));

        assertEq(address(customAdapter.getVault()), address(vault), "Vault should be set in custom adapter");

        bytes32 vaultSlot = OFT_ADAPTER_STORAGE_LOCATION;
        address vaultFromStorage = address(uint160(uint256(vm.load(address(proxy), vaultSlot))));
        assertEq(vaultFromStorage, address(vault), "Vault should be in correct storage slot");

        KATOFTAdapterUpgradeable standardImpl = new KATOFTAdapterUpgradeable(address(token), address(lzEndpoint));

        bytes32 implSlot = IMPLEMENTATION_SLOT;
        vm.store(address(proxy), implSlot, bytes32(uint256(uint160(address(standardImpl)))));

        address vaultAfterUpgrade = address(uint160(uint256(vm.load(address(proxy), vaultSlot))));
        assertEq(vaultAfterUpgrade, address(vault), "Vault storage should persist after upgrade");

        address implAfterUpgrade = address(uint160(uint256(vm.load(address(proxy), implSlot))));
        assertEq(implAfterUpgrade, address(standardImpl), "Implementation should be updated");
    }

    /// @notice Verify vault can be updated
    function test_vaultStorageCanBeUpdated() public {
        KATCustomOFTAdapterUpgradeable customImpl =
            new KATCustomOFTAdapterUpgradeable(address(token), address(lzEndpoint));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(customImpl),
            address(proxyAdmin),
            abi.encodeWithSelector(KATCustomOFTAdapterUpgradeable.initialize.selector, address(this))
        );

        KATCustomOFTAdapterUpgradeable adapter = KATCustomOFTAdapterUpgradeable(address(proxy));

        adapter.setVault(address(vault));
        assertEq(address(adapter.getVault()), address(vault), "Initial vault should be set");

        KATVaultMock newVault = new KATVaultMock();

        vm.expectEmit(true, true, false, false);
        emit KATCustomOFTAdapterUpgradeable.VaultUpdated(address(vault), address(newVault));
        adapter.setVault(address(newVault));

        assertEq(address(adapter.getVault()), address(newVault), "Vault should be updated");

        bytes32 vaultSlot = OFT_ADAPTER_STORAGE_LOCATION;
        address vaultFromStorage = address(uint160(uint256(vm.load(address(proxy), vaultSlot))));
        assertEq(vaultFromStorage, address(newVault), "Updated vault should be in storage");
    }

    /// @notice Verify vault storage is independent from other state
    function test_vaultStorageIndependence() public {
        KATCustomOFTAdapterUpgradeable customImpl =
            new KATCustomOFTAdapterUpgradeable(address(token), address(lzEndpoint));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(customImpl),
            address(proxyAdmin),
            abi.encodeWithSelector(KATCustomOFTAdapterUpgradeable.initialize.selector, address(this))
        );

        KATCustomOFTAdapterUpgradeable adapter = KATCustomOFTAdapterUpgradeable(address(proxy));

        adapter.setVault(address(vault));

        address bridgeUser = makeAddr("bridgeUser");
        adapter.grantBridgeUser(bridgeUser);

        assertEq(address(adapter.getVault()), address(vault), "Vault should be unchanged after role grant");

        adapter.revokeBridgeUser(bridgeUser);

        assertEq(address(adapter.getVault()), address(vault), "Vault should be unchanged after role revoke");
    }

    /// @notice Verify uninitialized vault returns zero address
    function test_uninitializedVaultStorage() public {
        KATCustomOFTAdapterUpgradeable customImpl =
            new KATCustomOFTAdapterUpgradeable(address(token), address(lzEndpoint));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(customImpl),
            address(proxyAdmin),
            abi.encodeWithSelector(KATCustomOFTAdapterUpgradeable.initialize.selector, address(this))
        );

        KATCustomOFTAdapterUpgradeable adapter = KATCustomOFTAdapterUpgradeable(address(proxy));

        assertEq(address(adapter.getVault()), address(0), "Uninitialized vault should be zero address");

        bytes32 vaultSlot = OFT_ADAPTER_STORAGE_LOCATION;
        address vaultFromStorage = address(uint160(uint256(vm.load(address(proxy), vaultSlot))));
        assertEq(vaultFromStorage, address(0), "Uninitialized vault storage should be zero");
    }
}

