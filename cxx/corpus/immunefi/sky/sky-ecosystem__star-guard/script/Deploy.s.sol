// SPDX-FileCopyrightText: © 2025 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";
import {StarGuard} from "../src/StarGuard.sol";

interface ChainlogLike {
    function getAddress(bytes32 _key) external view returns (address addr);
}

// To run this script, use the following command:
// ETHERSCAN_API_KEY="<KEY>" RPC_URL="<RPC_URL>" forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --sender $(cast wallet address --account $ACCOUNT) --account $ACCOUNT --sig "run(address)" $SUBPROXY_ADDRESS 

contract Deploy is Script {
    ChainlogLike internal constant chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    function run(address subProxy) public {
        // Check that deployer is not Foundry default
        // https://www.getfoundry.sh/config/reference/testing#sender
        address deployer = msg.sender;
        require(
            deployer != 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38,
            "msg.sender is not set correctly, ensure you provided --sender"
        );

        // Debug information
        console.log("Using deployer: %s", deployer);
        console.log("Using SubProxy address: %s", subProxy);

        address MCD_PAUSE_PROXY = chainlog.getAddress("MCD_PAUSE_PROXY");
        console.log("Using MCD_PAUSE_PROXY at %s", MCD_PAUSE_PROXY);

        vm.startBroadcast(deployer);
        address starGuard = address(new StarGuard(subProxy));
        ScriptTools.switchOwner(starGuard, deployer, MCD_PAUSE_PROXY);
        vm.stopBroadcast();

        console.log("Deployed StarGuard at %s", subProxy);
    }
}
