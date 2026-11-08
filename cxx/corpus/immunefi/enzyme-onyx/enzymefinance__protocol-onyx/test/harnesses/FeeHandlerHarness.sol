// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {FeeHandler} from "src/components/fees/FeeHandler.sol";
import {ComponentHarnessMixin} from "test/harnesses/utils/ComponentHarnessMixin.sol";

contract FeeHandlerHarness is FeeHandler, ComponentHarnessMixin {
    constructor(address _shares) ComponentHarnessMixin(_shares) {}

    function exposed_decreaseValueOwed(address _user, uint256 _delta) external {
        __decreaseValueOwed({_user: _user, _delta: _delta});
    }

    function exposed_increaseValueOwed(address _user, uint256 _delta) external {
        __increaseValueOwed({_user: _user, _delta: _delta});
    }
}
