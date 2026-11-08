// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { console2 as console, Script } from "../modules/forge-std/src/Script.sol";

import { MapleToken }             from "../contracts/MapleToken.sol";
import { MapleTokenInitializer }  from "../contracts/MapleTokenInitializer.sol";
import { MapleTokenProxy }        from "../contracts/MapleTokenProxy.sol";
import { RecapitalizationModule } from "../contracts/RecapitalizationModule.sol";

contract DeployToken is Script {

    function run() external {
        address ETH_SENDER = vm.envAddress("ETH_SENDER");

        address mapleGlobals = 0x804a6F5F667170F545Bf14e5DDB48C70B788390C;
        address migrator = computeCreateAddress(ETH_SENDER, 4); // 0x7b0267C13B994cdb58b8ED3a65b7A09a07432A76,

        vm.startBroadcast(ETH_SENDER);

        address tokenImplementation = address(new MapleToken());
        address tokenInitializer    = address(new MapleTokenInitializer());

        console.log("Token Implementation: %s", tokenImplementation);
        console.log("Token Initializer:    %s", tokenInitializer);

        address tokenProxy = address(new MapleTokenProxy(mapleGlobals, tokenImplementation, tokenInitializer, migrator));

        console.log("Token Proxy:          %s", tokenProxy);

        address recapitalizationModule = address(new RecapitalizationModule(tokenProxy));

        console.log("Recapitalization Module:     %s", recapitalizationModule);

        vm.stopBroadcast();
    }

}
