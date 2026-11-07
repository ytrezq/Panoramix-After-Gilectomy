// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.5;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {EternalStorageProxy} from "../contracts/upgradeability/EternalStorageProxy.sol";

/**
 * @title UpgradeForeignOmnibridge
 * @dev Points the ForeignOmnibridge proxy at an already deployed implementation (see
 *      DeployForeignOmnibridge.s.sol) by calling `upgradeTo(version, implementation)`.
 *
 *      Usage:
 *        forge script foundry-scripts/UpgradeForeignOmnibridge.s.sol \
 *          --rpc-url $FOREIGN_RPC_URL --sig "run(address)" $NEW_IMPLEMENTATION
 */
contract UpgradeForeignOmnibridge is Script {
    // https://etherscan.io/address/0x88ad09518695c6c3712AC10a214bE5109a655671
    address constant FOREIGN_OMNIBRIDGE_PROXY = 0x88ad09518695c6c3712AC10a214bE5109a655671;
    address constant PROXY_OWNER = 0x42F38ec5A75acCEc50054671233dfAC9C0E7A3F6;

    function run(address implementation) external {
        EternalStorageProxy proxy = EternalStorageProxy(payable(FOREIGN_OMNIBRIDGE_PROXY));
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
