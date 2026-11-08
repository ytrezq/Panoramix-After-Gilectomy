// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.22;

contract MockToken {

    /**********************************************************************************************/
    /*** Declarations and Constructor                                                           ***/
    /**********************************************************************************************/

    uint256 public totalSupply;
    uint256 public scaledTotalSupply;
    uint256 public decimals;

    /**********************************************************************************************/
    /*** Mock Functions                                                                         ***/
    /**********************************************************************************************/

    function __setTotalSupply(uint256 totalSupply_) public {
        totalSupply = totalSupply_;
    }

    function __setScaledTotalSupply(uint256 scaledTotalSupply_) public {
        scaledTotalSupply = scaledTotalSupply_;
    }

    function __setDecimals(uint256 decimals_) public {
        decimals = decimals_;
    }

}
