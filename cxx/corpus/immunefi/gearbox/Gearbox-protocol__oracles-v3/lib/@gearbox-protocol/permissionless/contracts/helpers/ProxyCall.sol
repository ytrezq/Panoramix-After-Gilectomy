// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ImmutableOwnableTrait} from "../traits/ImmutableOwnableTrait.sol";

contract ProxyCall is ImmutableOwnableTrait {
    using Address for address;

    constructor() ImmutableOwnableTrait(msg.sender) {}

    function proxyCall(address target, bytes calldata data) external onlyOwner returns (bytes memory result) {
        return target.functionCall(data);
    }
}
