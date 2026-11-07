// SPDX-FileCopyrightText: 2025 Dai Foundation <www.daifoundation.org>
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

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MCD, DssInstance} from "dss-test/MCD.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";
import {DssBlow2Deploy, DssBlow2DeployParams} from "src/deployment/DssBlow2Deploy.sol";
import {DssBlow2Instance} from "src/deployment/DssBlow2Instance.sol";

contract DssBlow2DeployScript is Script {
    using stdJson for string;
    using ScriptTools for string;

    string constant NAME = "dss-blow-2-deploy";

    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    DssInstance dss = MCD.loadFromChainlog(CHAINLOG);
    address usdsJoin = dss.chainlog.getAddress("USDS_JOIN");
    DssBlow2Instance inst;

    function run() external {
        vm.startBroadcast();

        inst = DssBlow2Deploy.deploy(
            DssBlow2DeployParams({daiJoin: address(dss.daiJoin), usdsJoin: usdsJoin, vow: address(dss.vow)})
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(NAME, "blow2", inst.blow);
        ScriptTools.exportContract(NAME, "daiJoin", address(dss.daiJoin));
        ScriptTools.exportContract(NAME, "usdsJoin", usdsJoin);
        ScriptTools.exportContract(NAME, "vow", address(dss.vow));
    }
}
