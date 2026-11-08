// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {IComponentProxy} from "src/interfaces/IComponentProxy.sol";

contract ComponentHarnessMixin is IComponentProxy {
    // OZ Initializable storage location (erc7201:openzeppelin.storage.Initializable)
    bytes32 private constant INITIALIZABLE_STORAGE_LOCATION =
        0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    address public SHARES;

    constructor(address _shares) {
        SHARES = _shares;

        // Re-enable initializers: implementation constructors call `_disableInitializers()`,
        // but harnesses are deployed and initialized directly rather than via a proxy
        assembly {
            sstore(INITIALIZABLE_STORAGE_LOCATION, 0)
        }
    }
}
