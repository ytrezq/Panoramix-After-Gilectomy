// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IRecapitalizationModule } from "../../contracts/interfaces/IRecapitalizationModule.sol";

import { TestBase } from "../utils/TestBase.sol";

contract ModuleInvariants is TestBase {

    // Recapitalization Module:
    // - Invariant A: traverseFrom(zeroWindowId) == lastScheduledWindowId
    // - Invariant B: windows.contains(lastClaimedWindow)
    // - Invariant C: zeroWindow.windowStart == 0
    // - Invariant D: zeroWindow.issuanceRate == 0
    // - Invariant E: lastScheduledWindow.nextWindowId == 0
    // - Invariant F: ∑window(windowId < window.nextWindowId)
    // - Invariant G: ∑window(window.windowStart < nextWindow.windowStart)
    // - Invariant H: lastClaimedTimestamp <= block.timestamp
    // - Invariant I: windowOf(lastClaimedTimestamp) == lastClaimedWindowId

    /**************************************************************************************************************************************/
    /*** Recapitalization Module Invariants                                                                                             ***/
    /**************************************************************************************************************************************/

    /**
     *  @notice Asserts the linked list of windows can be traversed from start to end.
     *  @dev    Invariant A: traverseFrom(zeroWindowId) == lastScheduledWindowId
     *  @param  module Address of the recapitalization module.
     */
    function assert_recapitalizationModule_invariant_A(IRecapitalizationModule module) internal {
        uint16 windowId;

        while (true) {
            ( uint16 nextWindowId, , ) = module.windows(windowId);

            if (nextWindowId == 0) break;

            windowId = nextWindowId;
        }

        assertEq(windowId, module.lastScheduledWindowId(), "Can't reach the last scheduled window.");
    }

    /**
     *  @notice Asserts the last claimed window is contained in the linked list.
     *  @dev    Invariant B: windows.contains(lastClaimedWindow)
     *  @param  module Address of the recapitalization module.
     */
    function assert_recapitalizationModule_invariant_B(IRecapitalizationModule module) internal {
        uint16 windowId;

        while (true) {
            if (windowId == module.lastClaimedWindowId()) return;

            ( uint16 nextWindowId, , ) = module.windows(windowId);

            assertTrue(nextWindowId != 0, "Last claimed window is unreachable.");

            windowId = nextWindowId;
        }
    }

    /**
     *  @notice Asserts the zero index window is the first starting window.
     *  @dev    Invariant C: zeroWindow.windowStart == 0
     *  @param  module Address of the recapitalization module.
     */
    function assert_recapitalizationModule_invariant_C(IRecapitalizationModule module) internal {
        ( , uint32 windowStart, ) = module.windows(0);

        assertEq(windowStart, 0, "Zero index window timestamp is invalid.");
    }

    /**
     *  @notice Asserts the zero index window is not issuing any tokens.
     *  @dev    Invariant D: zeroWindow.issuanceRate == 0
     *  @param  module Address of the recapitalization module.
     */
    function assert_recapitalizationModule_invariant_D(IRecapitalizationModule module) internal {
        ( , , uint208 issuanceRate ) = module.windows(0);

        assertEq(issuanceRate, 0, "Zero index window issuance rate is invalid.");
    }

    /**
     *  @notice Asserts the last scheduled window is the last one in the linked list.
     *  @dev    Invariant E: lastScheduledWindow.nextWindowId == 0
     *  @param  module Address of the recapitalization module.
     */
    function assert_recapitalizationModule_invariant_E(IRecapitalizationModule module) internal {
        ( uint16 nextWindowId, , ) = module.windows(module.lastScheduledWindowId());

        assertEq(nextWindowId, 0, "Last scheduled window is not the last window.");
    }

    /**
     *  @notice Asserts all window identifiers are in strictly ascending order.
     *  @dev    Invariant F: ∑window(windowId < window.nextWindowId)
     *  @param  module Address of the recapitalization module.
     */
    function assert_recapitalizationModule_invariant_F(IRecapitalizationModule module) internal {
        uint16 windowId;

        while (true) {
            ( uint16 nextWindowId, , ) = module.windows(windowId);

            if (nextWindowId == 0) break;

            assertLt(windowId, nextWindowId, "Window identifiers are not in strictly ascending order.");

            windowId = nextWindowId;
        }
    }

    /**
     *  @notice Asserts all window timestamps are in strictly ascending order.
     *  @dev    Invariant G: ∑window(window.windowStart < nextWindow.windowStart)
     *  @param  module Address of the recapitalization module.
     */
    function assert_recapitalizationModule_invariant_G(IRecapitalizationModule module) internal {
        uint16 windowId;

        while (true) {
            ( uint16 nextWindowId, uint32 windowStart, ) = module.windows(windowId);

            if (nextWindowId == 0) break;

            ( , uint32 nextWindowStart, ) = module.windows(nextWindowId);

            assertLt(windowStart, nextWindowStart, "Window timestamps are not in strictly ascending order.");

            windowId = nextWindowId;
        }
    }

    /**
     *  @notice Asserts tokens can only be claimed up to the current time.
     *  @dev    Invariant H: lastClaimedTimestamp <= block.timestamp
     *  @param  module Address of the recapitalization module.
     */
    function assert_recapitalizationModule_invariant_H(IRecapitalizationModule module, uint32 blockTimestamp) internal {
        assertLe(module.lastClaimedTimestamp(), blockTimestamp, "Last claimed timestamp is greater than the current time.");
    }

    /**
     *  @notice Asserts the window of the last claim is set correctly based on the timestamp of the last claim.
     *  @dev    Invariant I: windowOf(lastClaimedTimestamp) == lastClaimedWindowId
     *  @param  module Address of the recapitalization module.
     */
    function assert_recapitalizationModule_invariant_I(IRecapitalizationModule module) internal {
        ( uint16 nextWindowId, uint32 windowStart, ) = module.windows(module.lastClaimedWindowId());

        assertGe(module.lastClaimedTimestamp(), windowStart, "Last claimed window is invalid.");

        if (nextWindowId == 0) return;

        ( , uint32 windowEnd, ) = module.windows(nextWindowId);

        assertLt(module.lastClaimedTimestamp(), windowEnd, "Last claimed window is invalid.");
    }

}
