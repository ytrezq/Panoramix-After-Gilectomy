// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.5;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {ForeignOmnibridge} from "../contracts/upgradeable_contracts/ForeignOmnibridge.sol";

/**
 * @title DeployForeignOmnibridge
 * @dev Deploys a ForeignOmnibridge implementation. Nothing else: the proxy, its parameters and
 *      every module already exist on chain, and pointing the proxy at this implementation is a
 *      separate `upgradeTo` call from the proxy upgradeability owner.
 *
 *      Usage:
 *        forge script foundry-scripts/DeployForeignOmnibridge.s.sol \
 *          --rpc-url $FOREIGN_RPC_URL --broadcast --private-key $DEPLOYMENT_ACCOUNT_PRIVATE_KEY
 */
contract DeployForeignOmnibridge is Script {
    function run() external returns (address implementation) {

        vm.startBroadcast(); 
        implementation = address(new ForeignOmnibridge(" from xDai"));
        vm.stopBroadcast();
        //  https://etherscan.io/address/0x00e7097e9c1ce7121fc466ff31a7c742d5a26ea2
        console.log("ForeignOmnibridge implementation:", implementation);
    }
}
