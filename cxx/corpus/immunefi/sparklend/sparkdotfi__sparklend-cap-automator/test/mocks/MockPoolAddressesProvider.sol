// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.22;

contract MockPoolAddressesProvider {

    /**********************************************************************************************/
    /*** Declarations and Constructor                                                           ***/
    /**********************************************************************************************/

    address public pool;
    address public poolConfigurator;

    constructor(address pool_, address poolConfigurator_) {
        pool             = pool_;
        poolConfigurator = poolConfigurator_;
    }

    /**********************************************************************************************/
    /*** PoolAddressesProvider Functions                                                        ***/
    /**********************************************************************************************/

    function getPool() public view returns (address) {
        return pool;
    }

    function getPoolConfigurator() public view returns (address) {
        return poolConfigurator;
    }

}
