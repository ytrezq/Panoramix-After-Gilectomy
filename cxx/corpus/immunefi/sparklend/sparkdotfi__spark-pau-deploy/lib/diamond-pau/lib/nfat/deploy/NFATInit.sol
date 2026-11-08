// SPDX-FileCopyrightText: © 2026 Dai Foundation <www.daifoundation.org>
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

pragma solidity >=0.8.0;

import { DssInstance } from "dss-test/MCD.sol";

interface NFATFacilityLike {
    function gem() external view returns (address);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function file(bytes32, address) external;
    function file(bytes32, string calldata) external;
    function kiss(address) external;
    function addFreezer(address) external;
}

struct NFATConfig {
    string    name;
    string    symbol;
    address   almProxy;
    address   identityNetwork;
    string    baseURI;
    address   operator;
    address[] freezers;
    bytes32   facilityKey;
}

// Note: deployment scripts assume L1; adapt for L2
// Note: `stopped` is initially false
library NFATInit {

    function init(
        DssInstance memory dss,
        address     facility_,
        NFATConfig  memory cfg
    ) internal {
        NFATFacilityLike facility = NFATFacilityLike(facility_);

        require(facility.gem() == dss.chainlog.getAddress("SUSDS"), "NFATInit/gem-mismatch");
        require(keccak256(bytes(facility.name()))   == keccak256(bytes(cfg.name)),   "NFATInit/name-mismatch");
        require(keccak256(bytes(facility.symbol())) == keccak256(bytes(cfg.symbol)), "NFATInit/symbol-mismatch");

        facility.file("recipient", cfg.almProxy);
        facility.file("identityNetwork", cfg.identityNetwork);
        facility.file("baseURI", cfg.baseURI);

        facility.kiss(cfg.operator);
        for (uint256 i = 0; i < cfg.freezers.length; ++i) {
            facility.addFreezer(cfg.freezers[i]);
        }

        dss.chainlog.setAddress(cfg.facilityKey, facility_);
    }
}
