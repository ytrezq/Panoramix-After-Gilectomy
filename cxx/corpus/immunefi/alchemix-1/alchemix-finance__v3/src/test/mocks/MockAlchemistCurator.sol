// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AlchemistCurator} from "../../AlchemistCurator.sol";

contract MockAlchemistCurator is AlchemistCurator {
    constructor(address _admin, address _operator) AlchemistCurator(_admin, _operator) {}
}
