// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IRecapitalizationModule } from "../../contracts/interfaces/IRecapitalizationModule.sol";

contract RecapitalizationModuleHealthChecker {

    struct Invariants {
        bool invariantA;  // Invariant A: traverseFrom(zeroWindowId) == lastScheduledWindowId
        bool invariantB;  // Invariant B: windows.contains(lastClaimedWindow)
        bool invariantC;  // Invariant C: zeroWindow.windowStart == 0
        bool invariantD;  // Invariant D: zeroWindow.issuanceRate == 0
        bool invariantE;  // Invariant E: lastScheduledWindow.nextWindowId == 0
        bool invariantF;  // Invariant F: ∑window(windowId < window.nextWindowId)
        bool invariantG;  // Invariant G: ∑window(window.windowStart < nextWindow.windowStart)
        bool invariantH;  // Invariant H: lastClaimedTimestamp <= block.timestamp
        bool invariantI;  // Invariant I: windowOf(lastClaimedTimestamp) == lastClaimedWindowId
    }

    function checkInvariants(IRecapitalizationModule module) external view returns (Invariants memory invariants) {
        invariants.invariantA = check_invariant_A(module);
        invariants.invariantB = check_invariant_B(module);
        invariants.invariantC = check_invariant_C(module);
        invariants.invariantD = check_invariant_D(module);
        invariants.invariantE = check_invariant_E(module);
        invariants.invariantF = check_invariant_F(module);
        invariants.invariantG = check_invariant_G(module);
        invariants.invariantH = check_invariant_H(module);
        invariants.invariantI = check_invariant_I(module);
    }

    /**************************************************************************************************************************************/
    /*** Invariants Checkers                                                                                                            ***/
    /**************************************************************************************************************************************/

    function check_invariant_A(IRecapitalizationModule module) public view returns (bool isMaintained) {
        uint16 windowId;

        while (true) {
            ( uint16 nextWindowId, , ) = module.windows(windowId);

            if (nextWindowId == 0) break;

            windowId = nextWindowId;
        }

        isMaintained = windowId == module.lastScheduledWindowId();
    }

    function check_invariant_B(IRecapitalizationModule module) public view returns (bool isMaintained) {
        uint16 windowId;

        while (true) {
            if (windowId == module.lastClaimedWindowId()) return true;

            ( uint16 nextWindowId, , ) = module.windows(windowId);

            if (nextWindowId == 0) return false;

            windowId = nextWindowId;
        }
    }

    function check_invariant_C(IRecapitalizationModule module) public view returns (bool isMaintained) {
        ( , uint32 windowStart, ) = module.windows(0);

        isMaintained = windowStart == 0;
    }

    function check_invariant_D(IRecapitalizationModule module) public view returns (bool isMaintained) {
        ( , , uint208 issuanceRate ) = module.windows(0);

        isMaintained = issuanceRate == 0;
    }

    function check_invariant_E(IRecapitalizationModule module) public view returns (bool isMaintained) {
        ( uint16 nextWindowId, , ) = module.windows(module.lastScheduledWindowId());

        isMaintained = nextWindowId == 0;
    }

    function check_invariant_F(IRecapitalizationModule module) public view returns (bool isMaintained) {
        uint16 windowId;

        while (true) {
            ( uint16 nextWindowId, , ) = module.windows(windowId);

            if (nextWindowId == 0) return true;
            if (windowId >= nextWindowId) return false;

            windowId = nextWindowId;
        }
    }

    function check_invariant_G(IRecapitalizationModule module) public view returns (bool isMaintained) {
        uint16 windowId;

        while (true) {
            ( uint16 nextWindowId, uint32 windowStart, ) = module.windows(windowId);

            if (nextWindowId == 0) return true;

            ( , uint32 nextWindowStart, ) = module.windows(nextWindowId);

            if (windowStart >= nextWindowStart) return false;

            windowId = nextWindowId;
        }
    }

    function check_invariant_H(IRecapitalizationModule module) public view returns (bool isMaintained) {
        isMaintained = module.lastClaimedTimestamp() <= block.timestamp;
    }

    function check_invariant_I(IRecapitalizationModule module) public view returns (bool isMaintained) {
        ( uint16 nextWindowId, uint32 windowStart, ) = module.windows(module.lastClaimedWindowId());

        if (module.lastClaimedTimestamp() < windowStart) return false;

        if (nextWindowId == 0) return true;

        ( , uint32 windowEnd, ) = module.windows(nextWindowId);

        isMaintained = module.lastClaimedTimestamp() < windowEnd;
    }

}
