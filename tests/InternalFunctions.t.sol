// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { LoanManagerHarness } from "./utils/Harnesses.sol";
import { TestBase }           from "./utils/TestBase.sol";

contract InternalTestBase is TestBase {

    LoanManagerHarness loanManager = new LoanManagerHarness();

}

contract UpdatePrincipalOutTests is InternalTestBase {

    function testFuzz_updatePrincipalOut(uint256 startingPrincipal, int256 principalUpdate) external {
        startingPrincipal = bound(startingPrincipal,  0,    1e30);
        principalUpdate   = bound(principalUpdate,   -1e30, 1e30);

        loanManager.__setPrincipalOut(startingPrincipal);

        loanManager.__updatePrincipalOut(principalUpdate);

        // If it's being decreased, assert that there's no underflow.
        if (principalUpdate < 0 && uint256(-principalUpdate) > startingPrincipal) {
            assertEq(loanManager.principalOut(), 0);
            return;
        }

        // If not, should just be the difference.
        assertEq(loanManager.principalOut(), uint256(int256(startingPrincipal) + principalUpdate));
    }

}

contract UpdateUnrealizedLossesTests is InternalTestBase {

    function testFuzz_updateUnrealizedLosses(uint256 startingLosses, int256 lossesUpdate) external {
        startingLosses = bound(startingLosses,  0,    1e30);
        lossesUpdate   = bound(lossesUpdate,   -1e30, 1e30);

        loanManager.__setUnrealizedLosses(startingLosses);

        loanManager.__updateUnrealizedLosses(lossesUpdate);

        uint256 unrealizedLosses = loanManager.unrealizedLosses();

        // If it's being decreased, assert that there's no underflow.
        if (lossesUpdate < 0 && uint256(-lossesUpdate) > startingLosses) {
            assertEq(unrealizedLosses, 0);
            return;
        }

        // If not, should just be the difference.
        assertEq(unrealizedLosses, uint256(int256(startingLosses) + lossesUpdate));
    }

}

contract UpdateAccountingStateTests is InternalTestBase {

    function testFuzz_updateInterestAccounting(
        uint256 periodElapsed,
        uint256 initialAccountedInterest,
        uint256 initialIssuanceRate,
        int256  accountedInterestAdjustment,
        int256  issuanceRateAdjustment
    )
        external
    {
        initialAccountedInterest    = bound(initialAccountedInterest,     0,    1e30);
        initialIssuanceRate         = bound(initialIssuanceRate,          0,    1e40);
        accountedInterestAdjustment = bound(accountedInterestAdjustment, -1e30, 1e30);
        issuanceRateAdjustment      = bound(issuanceRateAdjustment,      -1e40, 1e40);
        periodElapsed               = bound(periodElapsed,                0,    365 days);

        loanManager.__setAccountedInterest(initialAccountedInterest);
        loanManager.__setIssuanceRate(initialIssuanceRate);
        loanManager.__setDomainStart(block.timestamp);

        vm.warp(block.timestamp + periodElapsed);

        uint256 accruedInterest = loanManager.accruedInterest();

        loanManager.__updateInterestAccounting(accountedInterestAdjustment, issuanceRateAdjustment);

        assertEq(loanManager.domainStart(), block.timestamp);

        uint256 accountedInterest = loanManager.accountedInterest();
        uint256 issuanceRate      = loanManager.issuanceRate();

        // Check accounted interest
        if (accountedInterestAdjustment < 0 && uint256(-accountedInterestAdjustment) > initialAccountedInterest + accruedInterest) {
            // If it's being decreased, assert that there's no underflow
            assertEq(accountedInterest, 0);
        } else {
            // If not, should just be the difference.
            assertEq(accountedInterest, uint256(int256(initialAccountedInterest + accruedInterest) + accountedInterestAdjustment));
        }

        // Check issuance rate
        if (issuanceRateAdjustment < 0 && uint256(-issuanceRateAdjustment) > initialIssuanceRate) {
            // If it's being decreased, assert that there's no underflow
            assertEq(issuanceRate, 0);
        } else {
            // If not, should just be the difference.
            assertEq(issuanceRate, uint256(int256(initialIssuanceRate) + issuanceRateAdjustment));
        }
    }

}
