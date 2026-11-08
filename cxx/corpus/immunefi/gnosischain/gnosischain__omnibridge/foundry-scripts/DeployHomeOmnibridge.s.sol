// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.7.5;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {HomeOmnibridge} from "../contracts/upgradeable_contracts/HomeOmnibridge.sol";

/**
 * @title DeployHomeOmnibridge
 * @dev Deploys a HomeOmnibridge implementation. Nothing else: the proxy, its parameters and every
 *      module already exist on chain, and pointing the proxy at this implementation is a separate
 *      `upgradeTo` call from the proxy upgradeability owner.
 *
 *      Usage:
 *        forge script foundry-scripts/DeployHomeOmnibridge.s.sol \
 *          --rpc-url $HOME_RPC_URL --broadcast --private-key $DEPLOYMENT_ACCOUNT_PRIVATE_KEY
 */
contract DeployHomeOmnibridge is Script {
    function run() external returns (address implementation) {

        vm.startBroadcast();
        implementation = address(new HomeOmnibridge(" from Mainnet"));
        vm.stopBroadcast();
        //  https://gnosisscan.io/address/0x992685a4117a5c217f3a0e33f735565ad132b12a
        console.log("HomeOmnibridge implementation:", implementation);
    }
}
