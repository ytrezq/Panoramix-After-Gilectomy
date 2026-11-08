// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {ComponentHarnessMixin} from "test/harnesses/utils/ComponentHarnessMixin.sol";

contract ValuationHandlerHarness is ValuationHandler, ComponentHarnessMixin {
    constructor(address _shares) ComponentHarnessMixin(_shares) {}

    function harness_setLastShareValue(uint256 _shareValue, uint256 _timestamp) public {
        ValuationHandlerStorage storage $ = __getValuationHandlerStorage();
        $.lastShareValue = uint128(_shareValue);
        $.lastShareValueTimestamp = uint40(_timestamp);
    }
}
