// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

interface ISubcompressor is IVersion {
    function getCompressedType() external view returns (bytes32 domain, bytes32 postfix);
}
