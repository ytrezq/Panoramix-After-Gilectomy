// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {AddressProvider} from "../../instance/AddressProvider.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {AddressProviderEntry} from "../../interfaces/Types.sol";
import {IImmutableOwnableTrait} from "../../interfaces/base/IImmutableOwnableTrait.sol";
import {AP_ADDRESS_PROVIDER, NO_VERSION_CONTROL} from "../../libraries/ContractLiterals.sol";

contract AddressProviderTest is Test {
    AddressProvider public provider;
    address public owner;

    function setUp() public {
        owner = makeAddr("owner");
        provider = new AddressProvider(owner);
    }

    /// @notice Test constructor sets up initial state correctly
    function test_U_AP_01_constructor_sets_initial_state() public view {
        assertEq(provider.owner(), owner);
        assertEq(provider.getKeys().length, 0);
    }

    /// @notice Test address setting functionality
    function test_U_AP_02_setAddress_works() public {
        bytes32 key = "TEST";
        address value = makeAddr("test");

        // Test it reverts if not owner
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(IImmutableOwnableTrait.CallerIsNotOwnerException.selector, notOwner));
        provider.setAddress(key, value, false);

        // Test it reverts if zero address
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IAddressProvider.ZeroAddressException.selector, key));
        provider.setAddress(key, address(0), false);

        // Test successful address setting without version
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IAddressProvider.SetAddress(key, NO_VERSION_CONTROL, value);
        provider.setAddress(key, value, false);

        assertEq(provider.getAddress(key, NO_VERSION_CONTROL), value);
        assertEq(provider.getAddressOrRevert(key, NO_VERSION_CONTROL), value);

        // Test successful address setting with version
        address versionedValue = makeAddr("versioned");
        uint256 version = 310;
        vm.mockCall(versionedValue, abi.encodeWithSignature("version()"), abi.encode(version));

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IAddressProvider.SetAddress(key, version, versionedValue);
        provider.setAddress(key, versionedValue, true);

        assertEq(provider.getAddress(key, version), versionedValue);
        assertEq(provider.getAddressOrRevert(key, version), versionedValue);

        // Test setting same address twice doesn't emit event
        vm.recordLogs();
        vm.prank(owner);
        provider.setAddress(key, versionedValue, true);

        // Verify no SetAddress event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);

        // Test it reverts if version is less than 100
        address invalidVersionValue = makeAddr("invalidVersion");
        vm.mockCall(invalidVersionValue, abi.encodeWithSignature("version()"), abi.encode(99));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IAddressProvider.InvalidVersionException.selector, key, 99));
        provider.setAddress(key, invalidVersionValue, true);

        // Test it reverts if version is greater than 999
        vm.mockCall(invalidVersionValue, abi.encodeWithSignature("version()"), abi.encode(1000));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IAddressProvider.InvalidVersionException.selector, key, 1000));
        provider.setAddress(key, invalidVersionValue, true);
    }

    /// @notice Test version tracking functionality
    function test_U_AP_03_version_tracking_works() public {
        bytes32 key = "TEST";
        uint256[] memory versions = new uint256[](6);
        versions[0] = 310; // 3.1.0
        versions[1] = 311; // 3.1.1
        versions[2] = 320; // 3.2.0
        versions[3] = 321; // 3.2.1
        versions[4] = 400; // 4.0.0
        versions[5] = 401; // 4.0.1

        // Add addresses with different versions
        for (uint256 i = 0; i < versions.length; i++) {
            address value = makeAddr(string(abi.encode(versions[i])));
            vm.mockCall(value, abi.encodeWithSignature("version()"), abi.encode(versions[i]));
            vm.prank(owner);
            provider.setAddress(key, value, true);
        }

        // Test latest version tracking
        assertEq(provider.getLatestVersion(key), 401);

        // Test latest minor version tracking
        assertEq(provider.getLatestMinorVersion(key, 300), 321); // Latest 3.x.x is 3.2.1
        assertEq(provider.getLatestMinorVersion(key, 400), 401); // Latest 4.x.x is 4.0.1

        // Test latest patch version tracking
        assertEq(provider.getLatestPatchVersion(key, 310), 311); // Latest 3.1.x is 3.1.1
        assertEq(provider.getLatestPatchVersion(key, 320), 321); // Latest 3.2.x is 3.2.1
        assertEq(provider.getLatestPatchVersion(key, 400), 401); // Latest 4.0.x is 4.0.1

        // Test version not found cases
        bytes32 unknownKey = "UNKNOWN";
        vm.expectRevert(abi.encodeWithSelector(IAddressProvider.VersionNotFoundException.selector, unknownKey));
        provider.getLatestVersion(unknownKey);

        vm.expectRevert(abi.encodeWithSelector(IAddressProvider.VersionNotFoundException.selector, key));
        provider.getLatestMinorVersion(key, 500); // No 5.x.x versions

        vm.expectRevert(abi.encodeWithSelector(IAddressProvider.VersionNotFoundException.selector, key));
        provider.getLatestPatchVersion(key, 330); // No 3.3.x versions

        // Test invalid version cases
        vm.expectRevert(abi.encodeWithSelector(IAddressProvider.InvalidVersionException.selector, key, 99));
        provider.getLatestMinorVersion(key, 99); // Version < 100

        vm.expectRevert(abi.encodeWithSelector(IAddressProvider.InvalidVersionException.selector, key, 1000));
        provider.getLatestMinorVersion(key, 1000); // Version > 999

        vm.expectRevert(abi.encodeWithSelector(IAddressProvider.InvalidVersionException.selector, key, 99));
        provider.getLatestPatchVersion(key, 99); // Version < 100

        vm.expectRevert(abi.encodeWithSelector(IAddressProvider.InvalidVersionException.selector, key, 1000));
        provider.getLatestPatchVersion(key, 1000); // Version > 999
    }

    /// @notice Test getters functionality
    function test_U_AP_04_getters_work() public {
        bytes32 key = "TEST";
        uint256 version = 310;
        address value = makeAddr("test");
        vm.mockCall(value, abi.encodeWithSignature("version()"), abi.encode(version));
        address noVersionValue = makeAddr("noVersion");

        // Test getAddress returns zero for non-existent entry
        assertEq(provider.getAddress(key, version), address(0));

        // Test getAddressOrRevert reverts for non-existent entry
        vm.expectRevert(abi.encodeWithSelector(IAddressProvider.AddressNotFoundException.selector, key, version));
        provider.getAddressOrRevert(key, version);

        // Add some entries
        vm.startPrank(owner);
        provider.setAddress(key, value, true);
        provider.setAddress(key, noVersionValue, false);
        vm.stopPrank();

        // Test getKeys
        bytes32[] memory keys = provider.getKeys();
        assertEq(keys.length, 1);
        assertEq(keys[0], key);

        // Test getVersions
        uint256[] memory versions = provider.getVersions(key);
        assertEq(versions.length, 2); // 310 + NO_VERSION_CONTROL
        assertTrue(
            (versions[0] == version && versions[1] == NO_VERSION_CONTROL)
                || (versions[0] == NO_VERSION_CONTROL && versions[1] == version)
        );

        // Test getAllEntries
        AddressProviderEntry[] memory entries = provider.getAllEntries();
        assertEq(entries.length, 2); // 310 + NO_VERSION_CONTROL

        // Find and verify versioned entry
        bool foundVersioned = false;
        bool foundNoVersion = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].ver == version) {
                assertEq(entries[i].key, key);
                assertEq(entries[i].value, value);
                foundVersioned = true;
            } else if (entries[i].ver == NO_VERSION_CONTROL) {
                assertEq(entries[i].key, key);
                assertEq(entries[i].value, noVersionValue);
                foundNoVersion = true;
            }
        }
        assertTrue(foundVersioned, "Versioned entry not found");
        assertTrue(foundNoVersion, "Non-versioned entry not found");
    }
}
