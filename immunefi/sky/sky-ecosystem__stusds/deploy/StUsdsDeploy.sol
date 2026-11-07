// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 Dai Foundation
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

pragma solidity ^0.8.21;

import { ScriptTools } from "dss-test/ScriptTools.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "dss-interfaces/Interfaces.sol";

import { StUsds } from "src/StUsds.sol";
import { StUsdsRateSetter } from "src/StUsdsRateSetter.sol";
import { StUsdsMom } from "src/StUsdsMom.sol";
import { StUsdsInstance } from "./StUsdsInstance.sol";

interface SPBEAMLike {
    function conv() external view returns (address);
}

library StUsdsDeploy {
    function deploy(
        address deployer,
        address owner,
        address clip
    ) internal returns (StUsdsInstance memory instance) {
        ChainlogAbstract chainlog = ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

        address _stUsdsImp = address(new StUsds(
                                            chainlog.getAddress("USDS_JOIN"),
                                            chainlog.getAddress("MCD_JUG"),
                                            clip,
                                            chainlog.getAddress("MCD_VOW")
                                        )
                                    );
        address _stUsds = address(new ERC1967Proxy(_stUsdsImp, abi.encodeCall(StUsds.initialize, ())));
        ScriptTools.switchOwner(_stUsds, deployer, owner);

        address _rateSetter = address(new StUsdsRateSetter(
            _stUsds,
            SPBEAMLike(chainlog.getAddress("MCD_SPBEAM")).conv()
        ));
        ScriptTools.switchOwner(_rateSetter, deployer, owner);

        StUsdsMom _mom = new StUsdsMom(_stUsds);
        _mom.setOwner(owner);

        instance.stUsds      = _stUsds;
        instance.stUsdsImp   = _stUsdsImp;
        instance.rateSetter  = _rateSetter;
        instance.mom         = address(_mom);
    }

    function deployMom(
        address owner
    ) internal returns (address mom) {
        ChainlogAbstract chainlog = ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

        StUsdsMom _mom = new StUsdsMom(chainlog.getAddress("STUSDS"));
        _mom.setOwner(owner);

        mom = address(_mom);
    }
}
