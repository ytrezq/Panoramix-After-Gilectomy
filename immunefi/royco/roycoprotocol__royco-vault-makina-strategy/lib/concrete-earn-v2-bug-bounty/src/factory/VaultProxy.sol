// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IVaultProxy} from "../interface/IVaultProxy.sol";

contract VaultProxy is ERC1967Proxy, IVaultProxy {
    // An immutable address for the admin to avoid unnecessary SLOADs before each call.
    address private immutable _admin;

    /**
     * @dev The proxy caller is not the current admin.
     */
    error CallerNotProxyAdmin();

    /**
     * @dev Initializes an upgradeable proxy managed by `msg.sender`,
     * backed by the implementation at `logic`, and optionally initialized with `data` as explained in
     * {ERC1967Proxy-constructor}.
     */
    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) {
        _admin = msg.sender;
        // Set the storage value and emit an event for ERC-1967 compatibility
        ERC1967Utils.changeAdmin(_proxyAdmin());
    }

    /**
     * @dev Simplified pattern - upgradeToAndCall will not fallback to implementation via this proxy
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external {
        if (msg.sender != _proxyAdmin()) {
            revert CallerNotProxyAdmin();
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
