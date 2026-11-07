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

pragma solidity ^0.8.21;

interface AuthorityLike {
    function canCall(address, address, bytes4) external view returns (bool);
}

interface StUsdsLike {
    function drip() external returns (uint256);
    function file(bytes32, uint256) external;
}

interface RateSetterLike {
    function diss(address) external;
    function file(bytes32, uint256) external;
}

contract StUsdsMom {
    // --- Storage ---
    address public owner;
    address public authority;

    // --- Immutables ---
    StUsdsLike immutable public stusds;

    // --- Events ---
    event SetOwner(address indexed owner);
    event SetAuthority(address indexed authority);
    event DissRateSetterBud(address indexed rateSetter, address bud);
    event HaltRateSetter(address indexed rateSetter);
    event ZeroCap(address indexed rateSetter);
    event ZeroLine(address indexed rateSetter);

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "StUsdsMom/not-owner");
        _;
    }

    modifier auth() {
        require(isAuthorized(msg.sender, msg.sig), "StUsdsMom/not-authorized");
        _;
    }

    constructor(address stusds_) {
        stusds = StUsdsLike(stusds_);

        owner = msg.sender;
        emit SetOwner(msg.sender);
    }

    // --- Administration ---
    function setOwner(address owner_) external onlyOwner {
        owner = owner_;
        emit SetOwner(owner_);
    }

    function setAuthority(address authority_) external onlyOwner {
        authority = authority_;
        emit SetAuthority(authority_);
    }

    // --- Internal Functions ---
    function isAuthorized(address src, bytes4 sig) internal view returns (bool) {
        if (src == owner) {
            return true;
        } else if (authority == address(0)) {
            return false;
        } else {
            return AuthorityLike(authority).canCall(src, address(this), sig);
        }
    }

    // --- Emergency Actions ---
    function dissRateSetterBud(address rateSetter, address bud) external auth {
        RateSetterLike(rateSetter).diss(bud);
        emit DissRateSetterBud(rateSetter, bud);
    }

    function haltRateSetter(address rateSetter) external auth {
        RateSetterLike(rateSetter).file("bad", 1);
        emit HaltRateSetter(rateSetter);
    }

    function zeroCap(address rateSetter) external auth {
        stusds.file("cap", 0);
        RateSetterLike(rateSetter).file("maxCap", 0);
        emit ZeroCap(rateSetter);
    }

    // Sets the stUSDS line and the rate setter maxLine to zero, then calls
    // `stusds.drip()` to immediately halt LockStake borrowing.
    function zeroLine(address rateSetter) external auth {
        stusds.file("line", 0);
        RateSetterLike(rateSetter).file("maxLine", 0);
        stusds.drip();
        emit ZeroLine(rateSetter);
    }
}
