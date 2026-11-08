// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISubcompressor} from "./ISubcompressor.sol";

interface IRWAUnderlyingSubcompressor is ISubcompressor {
    function getUnderlyingData(address underlying) external view returns (bytes memory);
}
