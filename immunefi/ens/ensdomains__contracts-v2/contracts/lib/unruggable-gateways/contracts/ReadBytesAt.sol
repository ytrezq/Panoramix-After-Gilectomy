// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ReadBytesAt {
    // NOTE: pure is the wrong mutability annotation but because of the direct use of inline assembly to set v.slot, Solidity can’t verify that it’s only reading storage and not modifying it
    function readBytesAt(uint256 slot) external pure returns (bytes memory) {
        bytes storage v;
        assembly {
            v.slot := slot
        }
        return v;
    }
}
