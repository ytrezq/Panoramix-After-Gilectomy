// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { RecapitalizationModule } from "../../contracts/RecapitalizationModule.sol";

contract RecapitalizationModuleHarness is RecapitalizationModule {

    constructor(address token_) RecapitalizationModule(token_) { }

    function findInsertionPoint(uint32 windowStart) external view returns (uint16 windowId) {
        windowId = super._findInsertionPoint(windowStart);
    }

}
