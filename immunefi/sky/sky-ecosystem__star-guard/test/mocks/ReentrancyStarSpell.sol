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

interface StarGuardLike {
    function exec() external;
}

contract ReentrancyStarSpell {
    address internal immutable starGuard;

    event ReentrancySucceeded();

    constructor(address starGuard_) {
        starGuard = starGuard_;
    }

    function isExecutable() external pure returns (bool) {
        return true;
    }

    function execute() external {
        bytes32 slot = keccak256("random slot number");
        uint256 iteration;
        assembly {
            iteration := sload(slot) // read
            sstore(slot, 1) // set to 1
        }
        if (iteration == 0) {
            StarGuardLike(starGuard).exec();
        } else {
            emit ReentrancySucceeded();
        }
    }
}
