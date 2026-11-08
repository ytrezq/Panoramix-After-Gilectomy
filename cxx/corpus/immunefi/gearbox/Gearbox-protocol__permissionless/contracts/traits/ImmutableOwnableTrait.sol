// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IImmutableOwnableTrait} from "../interfaces/base/IImmutableOwnableTrait.sol";

abstract contract ImmutableOwnableTrait is IImmutableOwnableTrait {
    address public immutable override owner;

    modifier onlyOwner() {
        if (msg.sender != owner) revert CallerIsNotOwnerException(msg.sender);
        _;
    }

    constructor(address owner_) {
        owner = owner_;
    }
}
