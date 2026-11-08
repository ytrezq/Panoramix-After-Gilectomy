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

import {DssBlow2} from "src/DssBlow2.sol";
import {DssBlow2Instance} from "./DssBlow2Instance.sol";

struct DssBlow2DeployParams {
    address daiJoin;
    address usdsJoin;
    address vow;
}

library DssBlow2Deploy {
    function deploy(DssBlow2DeployParams memory p) internal returns (DssBlow2Instance memory r) {
        r.blow = address(new DssBlow2({daiJoin_: p.daiJoin, usdsJoin_: p.usdsJoin, vow_: p.vow}));
    }
}
