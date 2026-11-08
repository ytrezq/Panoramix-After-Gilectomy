// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {AddressProviderEntry} from "../interfaces/Types.sol";
import {AP_ADDRESS_PROVIDER, NO_VERSION_CONTROL} from "../libraries/ContractLiterals.sol";
import {ImmutableOwnableTrait} from "../traits/ImmutableOwnableTrait.sol";

/// @title Address provider
/// @notice Stores addresses of important contracts
contract AddressProvider is ImmutableOwnableTrait, IAddressProvider {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @dev Internal struct with version info for a given key
    struct VersionInfo {
        uint256 latest;
        mapping(uint256 majorVersion => uint256) latestByMajor;
        mapping(uint256 minorVersion => uint256) latestByMinor;
        EnumerableSet.UintSet versionsSet;
    }

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_ADDRESS_PROVIDER;

    /// @dev Set of saved entry keys
    EnumerableSet.Bytes32Set internal _keysSet;

    /// @dev Mapping from `key` to version info
    mapping(bytes32 key => VersionInfo) internal _versionInfo;

    /// @dev Mapping from `(key, ver)` pair to saved address
    mapping(bytes32 key => mapping(uint256 ver => address)) internal _addresses;

    /// @notice Constructor
    /// @param owner_ Contract owner
    constructor(address owner_) ImmutableOwnableTrait(owner_) {}

    // ------- //
    // GETTERS //
    // ------- //

    /// @notice Returns the address by given `key` and `ver`
    function getAddress(bytes32 key, uint256 ver) external view override returns (address) {
        return _addresses[key][ver];
    }

    /// @notice Returns the address by given `key` and `ver`, reverts if not found
    function getAddressOrRevert(bytes32 key, uint256 ver) external view override returns (address result) {
        result = _addresses[key][ver];
        if (result == address(0)) revert AddressNotFoundException(key, ver);
    }

    /// @notice Returns all known keys
    function getKeys() external view override returns (bytes32[] memory) {
        return _keysSet.values();
    }

    /// @notice Returns all known versions for given `key`
    function getVersions(bytes32 key) external view override returns (uint256[] memory) {
        return _versionInfo[key].versionsSet.values();
    }

    /// @notice Returns all saved entries
    function getAllEntries() external view override returns (AddressProviderEntry[] memory entries) {
        uint256 numKeys = _keysSet.length();

        uint256 numEntries;
        for (uint256 i; i < numKeys; ++i) {
            numEntries += _versionInfo[_keysSet.at(i)].versionsSet.length();
        }

        entries = new AddressProviderEntry[](numEntries);
        uint256 idx;
        for (uint256 i; i < numKeys; ++i) {
            bytes32 key = _keysSet.at(i);
            VersionInfo storage info = _versionInfo[key];
            uint256 numVersions = info.versionsSet.length();
            for (uint256 j; j < numVersions; ++j) {
                uint256 ver = info.versionsSet.at(j);
                entries[idx++] = AddressProviderEntry(key, ver, _addresses[key][ver]);
            }
        }
    }

    /// @notice Returns the latest version for given `key` (excluding `NO_VERSION_CONTROL`)
    /// @dev Reverts if `key` has no versions except `NO_VERSION_CONTROL`
    function getLatestVersion(bytes32 key) external view override returns (uint256 ver) {
        ver = _versionInfo[key].latest;
        if (ver == 0) revert VersionNotFoundException(key);
    }

    /// @notice Returns the latest minor version for given `majorVersion`
    /// @dev Reverts if `majorVersion` is less than `100` or greater than `999`
    /// @dev Reverts if `key` has no entries with matching `majorVersion`
    function getLatestMinorVersion(bytes32 key, uint256 majorVersion) external view override returns (uint256 ver) {
        _validateVersion(key, majorVersion);
        ver = _versionInfo[key].latestByMajor[_getMajorVersion(majorVersion)];
        if (ver == 0) revert VersionNotFoundException(key);
    }

    /// @notice Returns the latest patch version for given `minorVersion`
    /// @dev Reverts if `minorVersion` is less than `100` or greater than `999`
    /// @dev Reverts if `key` has no entries with matching `minorVersion`
    function getLatestPatchVersion(bytes32 key, uint256 minorVersion) external view override returns (uint256 ver) {
        _validateVersion(key, minorVersion);
        ver = _versionInfo[key].latestByMinor[_getMinorVersion(minorVersion)];
        if (ver == 0) revert VersionNotFoundException(key);
    }

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    /// @notice Sets the address for given `key` to `value`, optionally saving contract's version
    /// @dev Reverts if caller is not the owner
    /// @dev Reverts if `value` is zero address
    /// @dev If `saveVersion` is true, reverts if version is less than `100` or greater than `999`
    function setAddress(bytes32 key, address value, bool saveVersion) external override onlyOwner {
        if (value == address(0)) revert ZeroAddressException(key);
        uint256 ver = NO_VERSION_CONTROL;
        if (saveVersion) {
            ver = IVersion(value).version();
            _validateVersion(key, ver);
        }

        if (_addresses[key][ver] == value) return;
        _keysSet.add(key);
        VersionInfo storage info = _versionInfo[key];
        info.versionsSet.add(ver);
        _addresses[key][ver] = value;
        emit SetAddress(key, ver, value);

        if (ver == NO_VERSION_CONTROL) return;
        if (ver > info.latest) info.latest = ver;
        uint256 majorVersion = _getMajorVersion(ver);
        if (ver > info.latestByMajor[majorVersion]) info.latestByMajor[majorVersion] = ver;
        uint256 minorVersion = _getMinorVersion(ver);
        if (ver > info.latestByMinor[minorVersion]) info.latestByMinor[minorVersion] = ver;
    }

    // --------- //
    // INTERNALS //
    // --------- //

    /// @dev Returns the major version of a given version
    function _getMajorVersion(uint256 ver) internal pure returns (uint256) {
        return ver - ver % 100;
    }

    /// @dev Returns the minor version of a given version
    function _getMinorVersion(uint256 ver) internal pure returns (uint256) {
        return ver - ver % 10;
    }

    /// @dev Reverts if `ver` is less than `100` or greater than `999`
    function _validateVersion(bytes32 key, uint256 ver) internal pure {
        if (ver < 100 || ver > 999) revert InvalidVersionException(key, ver);
    }
}
