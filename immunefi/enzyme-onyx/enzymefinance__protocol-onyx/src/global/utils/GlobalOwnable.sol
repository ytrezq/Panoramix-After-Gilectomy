// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Global} from "src/global/Global.sol";

/// @title GlobalOwnable Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Mixin for contracts that defer ownership to the Global contract's owner
abstract contract GlobalOwnable {
    Global public immutable GLOBAL;

    error GlobalOwnable__OnlyOwner__Unauthorized();

    constructor(address _global) {
        GLOBAL = Global(_global);
    }

    modifier onlyOwner() {
        require(__isOwner(msg.sender), GlobalOwnable__OnlyOwner__Unauthorized());
        _;
    }

    function __isOwner(address _who) internal view returns (bool) {
        return _who == GLOBAL.owner();
    }
}
