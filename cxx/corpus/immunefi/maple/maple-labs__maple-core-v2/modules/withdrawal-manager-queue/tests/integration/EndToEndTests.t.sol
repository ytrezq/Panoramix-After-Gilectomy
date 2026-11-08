// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { console, TestBase } from "../utils/TestBase.sol";

contract EndToEndTests is TestBase {

    // Helper storage variable for fuzz test
    mapping(uint128 => address) lpsRequest;
    mapping(address => bool)    manualLps;
    mapping(address => uint256) lpShares;

    function setUp() public override {
        super.setUp();
    }

    function test_e2e_fullFlow() external {
        // Start with 3 users
        address lp1 = makeAddr("lp1");  // Automatic
        address lp2 = makeAddr("lp2");  // Manual
        address lp3 = makeAddr("lp3");  // Automatic

        uint256 shares1 = 100e18;
        uint256 shares2 = 200e18;
        uint256 shares3 = 300e18;

        uint256 totalInitialShares = shares1 + shares2 + shares3;

        // Simulate shares being sent to PM
        pool.mint(pm, totalInitialShares);

        vm.prank(pm);
        pool.approve(address(withdrawalManager), totalInitialShares);

        vm.prank(poolDelegate);
        withdrawalManager.setManualWithdrawal(lp2, true);

        assertFalse(withdrawalManager.isManualWithdrawal(lp1));
        assertTrue(withdrawalManager.isManualWithdrawal(lp2));
        assertFalse(withdrawalManager.isManualWithdrawal(lp3));

        // All users are added to the queue
        vm.startPrank(pm);
        withdrawalManager.addShares(shares1, lp1);
        assertQueue({  nextRequestId: 1, lastRequestId: 1 });
        assertRequest({ requestId: 1, shares: shares1, owner: lp1 });

        assertEq(withdrawalManager.requestIds(lp1),          1);
        assertEq(pool.balanceOf(address(withdrawalManager)), shares1);

        withdrawalManager.addShares(shares2, lp2);
        assertQueue({ nextRequestId: 1, lastRequestId: 2 });
        assertRequest({ requestId: 2, shares: shares2, owner: lp2 });

        assertEq(withdrawalManager.requestIds(lp2),          2);
        assertEq(pool.balanceOf(address(withdrawalManager)), shares1 + shares2);

        withdrawalManager.addShares(shares3, lp3);
        assertQueue({ nextRequestId: 1, lastRequestId: 3 });
        assertRequest({ requestId: 3, shares: shares3, owner: lp3 });

        assertEq(withdrawalManager.requestIds(lp3),          3);
        assertEq(pool.balanceOf(address(withdrawalManager)), shares1 + shares2 + shares3);

        vm.stopPrank();

        assertEq(withdrawalManager.totalShares(),            totalInitialShares);
        assertEq(pool.balanceOf(address(withdrawalManager)), totalInitialShares);

        // Pool Delegate process first request partially
        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(shares1 / 2);

        assertEq(withdrawalManager.totalShares(), totalInitialShares - shares1 / 2);

        // LP1 is still in the queue, but request has been updated
        assertQueue({ nextRequestId: 1, lastRequestId: 3 });
        assertRequest({ requestId: 1, shares: shares1 / 2, owner: lp1 });

        assertEq(withdrawalManager.requestIds(lp1), 1);

        // Pool Delegate process rest of request 1 + half of request 2
        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(shares1 / 2 + shares2 / 2);

        // Shares of lp2 remain locked in wm
        assertEq(withdrawalManager.totalShares(), totalInitialShares - shares1);

        // Lp1 is removed from queue, although the `request` data structure remains populated.
        assertQueue({ nextRequestId: 2, lastRequestId: 3 });
        assertRequest({ requestId: 1, shares: 0, owner: address(0) });
        assertEq(withdrawalManager.requestIds(lp1), 0);

        // Lp2 is still on the queue, and had it's manual shares incremented.
        assertRequest({ requestId: 2, shares: shares2 / 2, owner: lp2 });

        assertEq(withdrawalManager.requestIds(lp2),            2);
        assertEq(withdrawalManager.manualSharesAvailable(lp2), shares2 / 2);

        vm.prank(pm);
        withdrawalManager.processExit(shares2 / 2, lp2);

        assertEq(withdrawalManager.manualSharesAvailable(lp2), 0);

        // PD processes remaining shares
        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(shares2 / 2 + shares3);

        assertQueue({ nextRequestId: 4, lastRequestId: 3 });

        // Only half of manual shares are remaining.
        assertEq(withdrawalManager.totalShares(), shares2 / 2);

        assertEq(withdrawalManager.manualSharesAvailable(lp2), shares2 / 2);

        // Assert requests
        assertRequest({ requestId: 2, shares: 0, owner: address(0) });
        assertRequest({ requestId: 3, shares: 0, owner: address(0) });
    }

    function testFuzz_fullFLow_fixedExchangeRate(address[10] memory lps, bool[10] memory isManual, uint256[10] memory shares) external {
        uint256 totalShares;
        uint128 inQueue;

        // Iterate through all users and add shares to pool manager
        for (uint256 i = 0; i < 10; i++) {
            vm.assume(lps[i] != address(0));
            // If it's a unique user, add to the queue
            if (withdrawalManager.requestIds(lps[i]) == 0) {
                uint256 sharesRequested = bound(shares[i], 1, 1e18);

                // Save each LP value to verify later
                lpsRequest[++inQueue] = lps[i];
                lpShares[lps[i]]      = sharesRequested;
                totalShares           += sharesRequested;

                _addSharesToPoolManager(sharesRequested);

                if (isManual[i]) {
                    vm.prank(poolDelegate);
                    withdrawalManager.setManualWithdrawal(lps[i], true);
                    manualLps[lps[i]] = true;
                }

                vm.prank(pm);
                withdrawalManager.addShares(sharesRequested, lps[i]);
            }
        }

        // Assert queue state
        assertQueue({ nextRequestId: 1, lastRequestId: inQueue });

        assertEq(withdrawalManager.totalShares(), totalShares);

        // Determine a random amount of shares to process
        uint256 sharesToProcess;
        sharesToProcess = bound(sharesToProcess, 100, totalShares);

        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(sharesToProcess);

        // To avoid doing the same iteration as the function `processRedemptions`, fetch the queue state, then check it's integrity.
        ( uint128 nextRequestId_, uint128 lastRequestId_ ) = withdrawalManager.queue();

        uint256 sharesProcessed;

        // First, check that the requests processes are correct
        for (uint128 i = 1; i < nextRequestId_; i++) {
            address lp = lpsRequest[i];

            assertRequest({ requestId: i, shares: 0, owner: address(0) });

            // If the request is manual, then it should have manual shares available.
            if (manualLps[lp]) assertEq(withdrawalManager.manualSharesAvailable(lp), lpShares[lp]);

            sharesProcessed += lpShares[lp];
        }

        // Check the possible partial request that is first on the queue.
        address firstLp = lpsRequest[nextRequestId_];

        assertRequest({ requestId: nextRequestId_, shares: lpShares[firstLp] - (sharesToProcess - sharesProcessed), owner: firstLp });

        // If the LP is manual, then it should have shares to withdraw.
        if (manualLps[firstLp]) {
            assertEq(withdrawalManager.manualSharesAvailable(firstLp), sharesToProcess - sharesProcessed);
        }

        // Finally, check that all subsequent requests are still on the queue.
        for (uint128 i = nextRequestId_ + 1; i <= lastRequestId_; i++) {
            address lp = lpsRequest[i];

            assertRequest({ requestId: i, shares: lpShares[lp], owner: lp });
        }

    }

    function _addSharesToPoolManager(uint256 shares_) internal {
        pool.mint(pm, shares_);

        vm.prank(pm);
        pool.approve(address(withdrawalManager), shares_);
    }

}
