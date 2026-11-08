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

import "./BaseRateProviderFactory.sol";
import "./CombinedRateProvider.sol";

/**
 * @title  Combined Rate Provider Factory
 * @notice This contract is a factory for creating instances of CombinedRateProvider.
 * @dev    This factory contract allows for the deployment of CombinedRateProvider contracts,
 *         which are used to combine market rates from two individual rate providers.
 */
contract CombinedRateProviderFactory is BaseRateProviderFactory {
    /**
     * @notice Deploys a new CombinedRateProvider contract using a price feed.
     * @param _rateProvider1 - The first of two rate providers the user wishes to multiply
     * @param _rateProvider2 - The second of two rate providers the user wishes to multiply
     */
    function create(address _rateProvider1, address _rateProvider2) external returns (CombinedRateProvider) {
        CombinedRateProvider rateProvider = new CombinedRateProvider(_rateProvider1, _rateProvider2);
        _onCreate(address(rateProvider));
        return rateProvider;
    }
}
