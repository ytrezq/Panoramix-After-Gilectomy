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

contract MaliciousStarSpell {
    address internal immutable starGuard;

    constructor(address starGuard_) {
        starGuard = starGuard_;
    }

    function isExecutable() external pure returns (bool) {
        return true;
    }

    function execute() external {
        address _starGuard = starGuard;
        assembly {
            // get free memory pointer
            let ptr := mload(64)
            // store starGuard address in the first 32 bytes
            mstore(ptr, _starGuard)
            // store slot index at the next 32 bytes
            mstore(add(ptr, 32), 0)
            // set 0 at the wards[starGuard] slot
            sstore(keccak256(ptr, 64), 0)
        }
    }
}
