// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { TimelockController as TimelockBase } from "@openzeppelin/contracts/governance/TimelockController.sol";

contract StrataMasterChef is TimelockBase {

    constructor(address[] memory proposers, address[] memory executors) TimelockBase(
        24 hours, proposers, executors, address(0)
    ) {

    }
}
