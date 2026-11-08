// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IAddressProvider as IAddressProviderBase} from
    "@gearbox-protocol/core-v3/contracts/interfaces/base/IAddressProvider.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {IImmutableOwnableTrait} from "./base/IImmutableOwnableTrait.sol";
import {AddressProviderEntry} from "./Types.sol";

/// @title Address provider interface
interface IAddressProvider is IAddressProviderBase, IVersion, IImmutableOwnableTrait {
    // ------ //
    // EVENTS //
    // ------ //

    event SetAddress(bytes32 indexed key, uint256 indexed ver, address indexed value);

    // ------ //
    // ERRORS //
    // ------ //

    error AddressNotFoundException(bytes32 key, uint256 ver);
    error InvalidVersionException(bytes32 key, uint256 ver);
    error VersionNotFoundException(bytes32 key);
    error ZeroAddressException(bytes32 key);

    // ------- //
    // GETTERS //
    // ------- //

    function getAddress(bytes32 key, uint256 ver) external view returns (address);
    function getAddressOrRevert(bytes32 key, uint256 ver) external view override returns (address);
    function getKeys() external view returns (bytes32[] memory);
    function getVersions(bytes32 key) external view returns (uint256[] memory);
    function getAllEntries() external view returns (AddressProviderEntry[] memory);
    function getLatestVersion(bytes32 key) external view returns (uint256);
    function getLatestMinorVersion(bytes32 key, uint256 majorVersion) external view returns (uint256);
    function getLatestPatchVersion(bytes32 key, uint256 minorVersion) external view returns (uint256);

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function setAddress(bytes32 key, address value, bool saveVersion) external;
}
