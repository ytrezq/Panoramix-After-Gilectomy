// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

contract MockContract is IVersion {
    bytes32 public immutable override contractType;
    uint256 public immutable override version;

    constructor(bytes32 contractType_, uint256 version_) {
        contractType = contractType_;
        version = version_;
    }
}
