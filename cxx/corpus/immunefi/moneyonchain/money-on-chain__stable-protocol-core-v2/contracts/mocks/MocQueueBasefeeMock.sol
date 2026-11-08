// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocQueue } from "../queue/MocQueue.sol";

/**
 * @title MocQueueBasefeeMock
 * @dev allows basefee manipulation to simplify tests
 */
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract MocQueueBasefeeMock is MocQueue {
    /**
     * @dev by returning 1 on basefee == 0 scenarios, we allow retro-compatibility with tests
     * that expected fixed executionCost, as those will be multiplied by "one".
     */
    function _getBaseFee() internal view override returns (uint256) {
        if (block.basefee == 0) return 1;
        else return super._getBaseFee();
    }
}
