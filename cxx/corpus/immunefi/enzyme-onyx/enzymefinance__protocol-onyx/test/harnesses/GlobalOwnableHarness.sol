// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {GlobalOwnable} from "src/global/utils/GlobalOwnable.sol";

contract GlobalOwnableHarness is GlobalOwnable {
    constructor(address _global) GlobalOwnable(_global) {}

    function exposed_isOwner(address _who) external view returns (bool) {
        return __isOwner(_who);
    }

    function modifier_onlyOwner() external view onlyOwner {
        // do nothing
    }
}
