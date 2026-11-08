// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { ISyrupRateProvider } from "../interfaces/ISyrupRateProvider.sol";

import { IPoolLike } from "../interfaces/Interfaces.sol";

contract SyrupRateProvider is ISyrupRateProvider {

    uint256 public constant FIXED_POINT_ONE = 1e18;  // 18 decimal fixed point number.

    address public immutable override pool;

    constructor(address pool_) {
        pool = pool_;
    }

    function getRate() external view override returns (uint256) {
        return IPoolLike(pool).convertToExitAssets(FIXED_POINT_ONE);
    }

}
