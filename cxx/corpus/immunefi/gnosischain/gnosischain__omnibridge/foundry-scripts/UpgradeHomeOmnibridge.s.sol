// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.5;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {EternalStorageProxy} from "../contracts/upgradeability/EternalStorageProxy.sol";

/**
 * @title UpgradeHomeOmnibridge
 * @dev Points the HomeOmnibridge proxy at an already deployed implementation (see
 *      DeployHomeOmnibridge.s.sol) by calling `upgradeTo(version, implementation)`.
 *
 *      Usage:
 *        forge script foundry-scripts/UpgradeHomeOmnibridge.s.sol \
 *          --rpc-url $HOME_RPC_URL --sig "run(address)" $NEW_IMPLEMENTATION
 */
contract UpgradeHomeOmnibridge is Script {
    // https://gnosisscan.io/address/0xf6A78083ca3e2a662D6dd1703c939c8aCE2e268d
    address constant HOME_OMNIBRIDGE_PROXY = 0xf6A78083ca3e2a662D6dd1703c939c8aCE2e268d;
    // Safe that owns the proxy — the only account `upgradeTo` accepts.
    address constant PROXY_OWNER = 0x7a48Dac683DA91e4faa5aB13D91AB5fd170875bd;

    function run(address implementation) external {
        EternalStorageProxy proxy = EternalStorageProxy(payable(HOME_OMNIBRIDGE_PROXY));
        uint256 nextVersion = proxy.version() + 1;

        console.log("current implementation:", proxy.implementation());
        console.log("new implementation:    ", implementation);
        console.log("next version:          ", nextVersion);
        console.log("submit this from the Safe:", PROXY_OWNER);
        console.logBytes(abi.encodeWithSelector(proxy.upgradeTo.selector, nextVersion, implementation));

        vm.startBroadcast(PROXY_OWNER);
        proxy.upgradeTo(nextVersion, implementation);
        vm.stopBroadcast();

        console.log("upgraded, implementation is now:", proxy.implementation());
    }
}
