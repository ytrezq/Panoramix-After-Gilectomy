// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.0;

import "./interfaces/IRateProvider.sol";

contract CombinedRateProvider {
    address public rateProvider1;
    address public rateProvider2;

    constructor(address _rateProvider1, address _rateProvider2) {
        rateProvider1 = _rateProvider1;
        rateProvider2 = _rateProvider2;
    }

    // Function to combine both of the rate providers via multiplication
    function getRate() external view returns (uint256) {
        // rateProvider1 and rateProvider2 must respect the proper interface.
        uint256 rate1 = IRateProvider(rateProvider1).getRate();
        uint256 rate2 = IRateProvider(rateProvider2).getRate();
        return rate1 * rate2 / 1e18; // Multiplies the rates respecting the proper interface together and divides by 1e18 to normalize.
    }
}
