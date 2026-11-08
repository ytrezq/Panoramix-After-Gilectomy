// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {Shares} from "src/shares/Shares.sol";

/// @title FeeTrackerHelpersMixin Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Mixin of helpers for fee tracker implementations
abstract contract FeeTrackerHelpersMixin is ComponentHelpersMixin {
    error FeeTrackerHelpersMixin__OnlyFeeHandler__Unauthorized();

    modifier onlyFeeHandler() {
        require(
            msg.sender == Shares(__getShares()).getFeeHandler(), FeeTrackerHelpersMixin__OnlyFeeHandler__Unauthorized()
        );

        _;
    }
}
