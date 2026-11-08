// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SlotDataPointer {
    address public pointer;

    constructor(address a) {
        pointer = a;
    }
}
