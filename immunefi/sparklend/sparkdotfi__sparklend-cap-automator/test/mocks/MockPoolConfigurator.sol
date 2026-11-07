// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.22;

import { MockPool } from "./MockPool.sol";

contract MockPoolConfigurator {

    /**********************************************************************************************/
    /*** Declarations and Constructor                                                           ***/
    /**********************************************************************************************/

    address public mockPool;

    constructor(address mockPool_) {
        mockPool = mockPool_;
    }

    /**********************************************************************************************/
    /*** PoolConfigurator Functions                                                             ***/
    /**********************************************************************************************/

    function setSupplyCap(address, uint256 supplyCap) external {
        MockPool(mockPool).__setSupplyCap(supplyCap);
    }

    function setBorrowCap(address, uint256 borrowCap) external {
        MockPool(mockPool).__setBorrowCap(borrowCap);
    }

}
