// SPDX-License-Identifier: UNlICENSED
pragma solidity 0.8.24;

import { BaseFork, IMocCoreLegacy, IMocQueueLegacy } from "./helpers/BaseFork.sol";
import { MocQueueExecFees } from "moc-main-latest/contracts/queue/MocQueueExecFees.sol";
import { MocReverseAuction } from "moc-main-latest/contracts/auxiliary/MocReverseAuction.sol";

/// @title Fork Tests with Ignition Deployed Contracts
/// @notice Fork tests that use contracts deployed by Hardhat Ignition
contract MigrationForkTests is BaseFork {
    // State before upgrade
    uint256 public coverageBefore;
    uint256 public tcAvailableBefore;
    uint256 public tpAvailableBefore;
    uint256 public operIdCountBefore;

    // Block/time tracking for timestamp migration verification
    uint256 public nextEmaCalculation;
    uint256 public nextTCInterestPayment;
    uint256 public nextSettlementBlockNumber;
    uint256 public emaCalculationBlockSpan;
    uint256 public tcInterestPaymentBlockSpan;
    uint256 public bes;
    uint256 public decayBlockSpan;

    // ============ Setup ============

    /// @notice Set up the fork test environment using Ignition deployed contracts
    function setUp() public override {
        super.setUp();
    }

    /// @notice Capture state before the upgrade for comparison
    function captureStateBefore() internal {
        coverageBefore = rifBucket.getCglb();
        tcAvailableBefore = rifBucket.getTCAvailableToRedeem();
        int256 tpAvailableInt = rifBucket.getTPAvailableToMint(address(usdRifToken));
        tpAvailableBefore = tpAvailableInt > 0 ? uint256(tpAvailableInt) : 0;
        operIdCountBefore = rifQueueOld.operIdCount();

        // Capture time-related values before upgrade (block-based)
        IMocCoreLegacy legacyMoc = IMocCoreLegacy(address(rifBucket));
        nextEmaCalculation = legacyMoc.nextEmaCalculation();
        nextTCInterestPayment = legacyMoc.nextTCInterestPayment();
        nextSettlementBlockNumber = legacyMoc.bns();
        emaCalculationBlockSpan = legacyMoc.emaCalculationBlockSpan();
        tcInterestPaymentBlockSpan = legacyMoc.tcInterestPaymentBlockSpan();
        bes = legacyMoc.bes();
        decayBlockSpan = legacyMoc.decayBlockSpan();
    }

    // ============ Tests: Changer Execution ============

    /// @notice Test that the new MocQueue is set on MocCore after upgrade
    function test_NewMocQueueIsSetOnMocCore() public {
        _executeChanger();

        // Verify the upgrade was successful
        assertEq(rifBucket.mocQueue(), address(rifQueue), "New MocQueue should be set on MocCore");
    }

    /// @notice Test that MocCore is registered on MocQueue after upgrade
    function test_MocCoreIsRegisteredOnMocQueue() public {
        _executeChanger();

        assertEq(address(rifQueue.mocOperations()), address(rifBucket), "MocCore should be registered on MocQueue");
    }

    /// @notice Test that MocCore is registered on MocMultiCollateralGuard
    function test_MocCoreIsRegisteredOnMocMultiCollateralGuard() public {
        _executeChanger();

        assertEq(
            address(mocMultiCollateralGuard.buckets(0)),
            address(rifBucket),
            "MocCore should be registered on MocMultiCollateralGuard"
        );
    }

    /// @notice Test that protected threshold is updated with the changer value
    function test_ProtectedThresholdIsUpdated() public {
        _executeChanger();

        assertEq(
            rifBucket.protThrld(),
            changer.rifNewProtectedThrld(),
            "Protected threshold should be updated on RIF bucket"
        );
    }

    /// @notice Test that params passed as current values to setters remain unchanged after upgrade
    function test_UnchangedSetterParamsRemainEqualAfterUpgrade() public {
        address maxAbsoluteOpProviderBefore = address(rifBucket.maxAbsoluteOpProvider());
        address maxOpDiffProviderBefore = address(rifBucket.maxOpDiffProvider());
        address tcInterestCollectorBefore = rifBucket.tcInterestCollectorAddress();
        uint256 tcInterestRateBefore = rifBucket.tcInterestRate();
        uint256 liqThrldBefore = rifBucket.liqThrld();

        _executeChanger();

        assertEq(
            address(rifBucket.maxAbsoluteOpProvider()),
            maxAbsoluteOpProviderBefore,
            "maxAbsoluteOpProvider should not change"
        );
        assertEq(
            address(rifBucket.maxOpDiffProvider()),
            maxOpDiffProviderBefore,
            "maxOpDiffProvider should not change"
        );
        assertEq(
            rifBucket.tcInterestCollectorAddress(),
            tcInterestCollectorBefore,
            "tcInterestCollector should not change"
        );
        assertEq(rifBucket.tcInterestRate(), tcInterestRateBefore, "tcInterestRate should not change");
        assertEq(rifBucket.liqThrld(), liqThrldBefore, "liqThrld should not change");
    }

    /// @notice Test that OperIdCount is maintained after upgrade
    function test_OperIdCountIsMaintained() public {
        captureStateBefore();
        _executeChanger();

        assertEq(rifQueue.operIdCount(), operIdCountBefore, "OperIdCount should be maintained");
        assertEq(rifQueue.firstOperId(), operIdCountBefore, "firstOperId should equal operIdCount");
    }

    /// @notice Test that global coverage did not change after upgrade
    function test_GlobalCoverageDidNotChange() public {
        captureStateBefore();
        _executeChanger();

        assertEq(rifBucket.getCglb(), coverageBefore, "Global coverage should not change");
    }

    /// @notice Test that TC available to redeem did not change after upgrade
    function test_TCAvailableToRedeemDidNotChange() public {
        captureStateBefore();
        _executeChanger();

        assertEq(rifBucket.getTCAvailableToRedeem(), tcAvailableBefore, "TC available to redeem should not change");
    }

    /// @notice Test that TP available to mint did not change after upgrade
    function test_TPAvailableToMintDidNotChange() public {
        captureStateBefore();
        _executeChanger();

        int256 tpAvailableAfter = rifBucket.getTPAvailableToMint(address(usdRifToken));
        assertEq(tpAvailableAfter, int256(tpAvailableBefore), "TP available to mint should not change");
    }

    /// @notice Test that nextEmaCalculation is migrated to timestamp correctly
    function test_NextEmaCalculationMigratedToTimestamp() public {
        captureStateBefore();
        _executeChanger();

        uint256 remainingBlocks = nextEmaCalculation - executeBlockNumber;
        uint256 expectedTimestamp = executeTimestamp + (remainingBlocks * BLOCK_SPAN);

        assertEq(
            rifBucket.nextEmaCalculation(),
            expectedTimestamp,
            "nextEmaCalculation should be migrated to timestamp"
        );
        assertEq(
            rifBucket.emaCalculationTimeSpan(),
            emaCalculationBlockSpan * BLOCK_SPAN,
            "emaCalculationTimeSpan should be converted correctly"
        );
    }

    /// @notice Test that nextTCInterestPayment is migrated to timestamp correctly
    function test_NextTCInterestPaymentMigratedToTimestamp() public {
        captureStateBefore();
        _executeChanger();

        uint256 remainingBlocks = nextTCInterestPayment - executeBlockNumber;
        uint256 expectedTimestamp = executeTimestamp + (remainingBlocks * BLOCK_SPAN);

        assertEq(
            rifBucket.nextTCInterestPayment(),
            expectedTimestamp,
            "nextTCInterestPayment should be migrated to timestamp"
        );
        assertEq(
            rifBucket.tcInterestPaymentTimeSpan(),
            tcInterestPaymentBlockSpan * BLOCK_SPAN,
            "tcInterestPaymentTimeSpan should be converted correctly"
        );
    }

    /// @notice Test that nextSettlementTime is migrated to timestamp correctly
    function test_NextSettlementTimeMigratedToTimestamp() public {
        captureStateBefore();
        _executeChanger();

        uint256 remainingBlocks = nextSettlementBlockNumber - executeBlockNumber;
        uint256 expectedTimestamp = executeTimestamp + (remainingBlocks * BLOCK_SPAN);

        assertEq(
            rifBucket.nextSettlementTime(),
            expectedTimestamp,
            "nextSettlementTime should be migrated to timestamp"
        );
        assertEq(rifBucket.settlementTimeSpan(), bes * BLOCK_SPAN, "settlementTimeSpan should be converted correctly");
    }

    /// @notice Test that lastOperationTimeStamp is set correctly
    function test_LastOperationTimeStampMigrated() public {
        captureStateBefore();
        _executeChanger();

        assertEq(
            rifBucket.lastOperationTimeStamp(),
            executeTimestamp,
            "lastOperationTimeStamp should be set to execute timestamp"
        );
        assertEq(rifBucket.decayTimeSpan(), decayBlockSpan * BLOCK_SPAN, "decayTimeSpan should be converted correctly");
    }

    // ============ Tests: Operations After Upgrade ============

    /// @notice Test that mintTP operation executes successfully after upgrade
    function test_MintTPOperationExecutesSuccessfully() public {
        _executeChanger();

        uint256 initialRifBalance = rifToken.balanceOf(holder);
        uint256 initialTpBalance = usdRifToken.balanceOf(holder);

        uint256 qTP = 0.1 ether;
        uint256 maxAC = qTP * 100;
        uint256 execCost = _getExecCost(rifQueue, MocQueueExecFees.OperType.mintTP);

        vm.prank(holder);
        rifBucket.mintTP{ value: execCost }(address(usdRifToken), qTP, maxAC, holder, VENDOR);

        vm.roll(block.number + rifQueue.minOperWaitingBlk());
        mocMultiCollateralGuard.execute();

        assertLt(rifToken.balanceOf(holder), initialRifBalance, "RIF balance should decrease after mintTP");
        assertEq(usdRifToken.balanceOf(holder), initialTpBalance + qTP, "USD RIF balance should increase after mintTP");
    }

    /// @notice Test that redeemTC operation executes successfully after upgrade
    function test_RedeemTCOperationExecutesSuccessfully() public {
        _executeChanger();

        uint256 initialRifBalance = rifToken.balanceOf(holder);
        uint256 initialTcBalance = rifProToken.balanceOf(holder);
        require(initialTcBalance > 0, "Holder should have TC tokens");

        uint256 qTC = 0.1 ether;
        uint256 execCost = _getExecCost(rifQueue, MocQueueExecFees.OperType.redeemTC);

        vm.prank(holder);
        rifBucket.redeemTC{ value: execCost }(qTC, 0, holder, VENDOR);

        vm.roll(block.number + rifQueue.minOperWaitingBlk());
        mocMultiCollateralGuard.execute();

        assertGt(rifToken.balanceOf(holder), initialRifBalance, "RIF balance should increase after redeemTC");
        assertEq(rifProToken.balanceOf(holder), initialTcBalance - qTC, "TC balance should decrease after redeemTC");
    }

    /// @notice Test that mintTCandTP operation executes successfully after upgrade
    function test_MintTCandTPOperationExecutesSuccessfully() public {
        _executeChanger();

        uint256 initialRifBalance = rifToken.balanceOf(holder);
        uint256 initialTpBalance = usdRifToken.balanceOf(holder);

        uint256 qTP = 0.1 ether;
        uint256 maxAC = qTP * 500;
        uint256 execCost = _getExecCost(rifQueue, MocQueueExecFees.OperType.mintTCandTP);

        vm.prank(holder);
        rifBucket.mintTCandTP{ value: execCost }(address(usdRifToken), qTP, maxAC, holder, VENDOR);

        vm.roll(block.number + rifQueue.minOperWaitingBlk());
        mocMultiCollateralGuard.execute();

        assertLt(rifToken.balanceOf(holder), initialRifBalance, "RIF balance should decrease after mintTCandTP");
        assertEq(
            usdRifToken.balanceOf(holder),
            initialTpBalance + qTP,
            "USD RIF balance should increase after mintTCandTP"
        );
    }

    /// @notice Test that lastOperationTimeStamp is updated after operation
    function test_LastOperationTimeStampUpdatedAfterOperation() public {
        _executeChanger();

        // Execute a mintTP operation
        uint256 qTP = 0.1 ether;
        uint256 maxAC = qTP * 100;
        uint256 execCost = _getExecCost(rifQueue, MocQueueExecFees.OperType.mintTP);

        vm.prank(holder);
        rifBucket.mintTP{ value: execCost }(address(usdRifToken), qTP, maxAC, holder, VENDOR);

        vm.roll(block.number + rifQueue.minOperWaitingBlk());
        mocMultiCollateralGuard.execute();

        assertEq(rifBucket.lastOperationTimeStamp(), block.timestamp, "lastOperationTimeStamp should be updated");
    }

    /// @notice Test that TC interest payment executes and updates nextTCInterestPayment
    function test_TCInterestPaymentExecutesSuccessfully() public {
        _executeChanger();

        // Warp to after nextTCInterestPayment
        uint256 nextPayment = rifBucket.nextTCInterestPayment();
        vm.warp(nextPayment + 1);

        rifBucket.tcHoldersInterestPayment();

        assertEq(
            rifBucket.nextTCInterestPayment(),
            block.timestamp + rifBucket.tcInterestPaymentTimeSpan(),
            "nextTCInterestPayment should be updated"
        );
    }

    /// @notice Test that EMA update executes and updates nextEmaCalculation
    function test_EMAUpdateExecutesSuccessfully() public {
        _executeChanger();

        // Warp to after nextEmaCalculation
        uint256 nextEma = rifBucket.nextEmaCalculation();
        vm.warp(nextEma + 1);

        rifBucket.updateEmas();

        assertEq(
            rifBucket.nextEmaCalculation(),
            block.timestamp + rifBucket.emaCalculationTimeSpan(),
            "nextEmaCalculation should be updated"
        );
    }

    /// @notice Test that settlement executes and updates nextSettlementTime
    function test_SettlementExecutesSuccessfully() public {
        _executeChanger();

        // Warp to after nextSettlementTime
        uint256 nextSettlement = rifBucket.nextSettlementTime();
        vm.warp(nextSettlement + 1);

        rifBucket.execSettlement();

        assertEq(
            rifBucket.nextSettlementTime(),
            block.timestamp + rifBucket.settlementTimeSpan(),
            "nextSettlementTime should be updated"
        );
    }

    /// @notice Test all time-based tasks execute after sufficient time has elapsed
    function test_AllTimeBasedTasksExecuteAfterTimeElapsed() public {
        _executeChanger();

        // Find the maximum of all next times
        uint256 maxTime = _max(
            _max(rifBucket.nextTCInterestPayment(), rifBucket.nextEmaCalculation()),
            rifBucket.nextSettlementTime()
        );

        // Warp to after all scheduled times
        vm.warp(maxTime + 1);

        // Execute TC interest payment
        rifBucket.tcHoldersInterestPayment();
        assertEq(
            rifBucket.nextTCInterestPayment(),
            block.timestamp + rifBucket.tcInterestPaymentTimeSpan(),
            "nextTCInterestPayment should be updated after execution"
        );

        // Execute EMA update
        rifBucket.updateEmas();
        assertEq(
            rifBucket.nextEmaCalculation(),
            block.timestamp + rifBucket.emaCalculationTimeSpan(),
            "nextEmaCalculation should be updated after execution"
        );

        // Execute settlement
        rifBucket.execSettlement();
        assertEq(
            rifBucket.nextSettlementTime(),
            block.timestamp + rifBucket.settlementTimeSpan(),
            "nextSettlementTime should be updated after execution"
        );
    }

    // ============ Tests: Operation Results Comparison (Before vs After Upgrade) ============

    /// @notice Struct to store operation results for comparison
    struct MintTPResult {
        uint256 coverage;
        uint256 tcAvailable;
        uint256 tpAvailable;
        uint256 acSpent;
        uint256 tpEarn;
    }

    struct RedeemTCResult {
        uint256 coverage;
        uint256 tcAvailable;
        uint256 tpAvailable;
        uint256 acEarn;
        uint256 tcSpent;
    }

    struct MintTCandTPResult {
        uint256 coverage;
        uint256 tcAvailable;
        uint256 tpAvailable;
        uint256 acSpent;
        uint256 tcEarn;
        uint256 tpEarn;
    }

    /// @notice Test that mintTP operation results are the same before and after upgrade
    function test_MintTPResultsMatchBeforeAndAfterUpgrade() public {
        // Take snapshot before any operations
        uint256 snapshotId = vm.snapshot();

        // === Execute mintTP BEFORE upgrade (single-collateral) ===
        MintTPResult memory resultBefore;
        {
            uint256 acBalanceBefore = rifToken.balanceOf(holder);
            uint256 tpBalanceBefore = usdRifToken.balanceOf(holder);

            // Get exec fee for single-collateral queue
            uint256 execFee = rifQueueOld.execFee(MocQueueExecFees.OperType.mintTP);

            vm.prank(holder);
            rifBucket.mintTP{ value: execFee }(address(usdRifToken), 0.1 ether, 10 ether, holder, VENDOR);

            // Execute operation (single-collateral uses MocQueue directly)
            vm.roll(block.number + rifQueueOld.minOperWaitingBlk());
            rifQueueOld.execute(holder);

            // Capture results
            resultBefore.coverage = rifBucket.getCglb();
            resultBefore.tcAvailable = rifBucket.getTCAvailableToRedeem();
            int256 tpAvailableInt = rifBucket.getTPAvailableToMint(address(usdRifToken));
            resultBefore.tpAvailable = tpAvailableInt > 0 ? uint256(tpAvailableInt) : 0;
            resultBefore.acSpent = acBalanceBefore - rifToken.balanceOf(holder);
            resultBefore.tpEarn = usdRifToken.balanceOf(holder) - tpBalanceBefore;
        }

        // Revert to snapshot (restore state before the operation)
        vm.revertTo(snapshotId);

        // === Execute mintTP AFTER upgrade (multi-collateral) ===
        MintTPResult memory resultAfter;
        {
            _executeChanger();

            uint256 acBalanceBefore = rifToken.balanceOf(holder);
            uint256 tpBalanceBefore = usdRifToken.balanceOf(holder);
            uint256 execCost = _getExecCost(rifQueue, MocQueueExecFees.OperType.mintTP);

            vm.prank(holder);
            rifBucket.mintTP{ value: execCost }(address(usdRifToken), 0.1 ether, 10 ether, holder, VENDOR);

            // Execute operation (multi-collateral uses MocMultiCollateralGuard)
            vm.roll(block.number + rifQueue.minOperWaitingBlk());
            mocMultiCollateralGuard.execute();

            // Capture results
            resultAfter.coverage = rifBucket.getCglb();
            resultAfter.tcAvailable = rifBucket.getTCAvailableToRedeem();
            int256 tpAvailableInt = rifBucket.getTPAvailableToMint(address(usdRifToken));
            resultAfter.tpAvailable = tpAvailableInt > 0 ? uint256(tpAvailableInt) : 0;
            resultAfter.acSpent = acBalanceBefore - rifToken.balanceOf(holder);
            resultAfter.tpEarn = usdRifToken.balanceOf(holder) - tpBalanceBefore;
        }

        // Compare results
        assertEq(resultBefore.coverage, resultAfter.coverage, "Coverage should match");
        assertEq(resultBefore.tcAvailable, resultAfter.tcAvailable, "TC available should match");
        assertEq(resultBefore.tpAvailable, resultAfter.tpAvailable, "TP available should match");
        assertEq(resultBefore.acSpent, resultAfter.acSpent, "AC spent should match");
        assertEq(resultBefore.tpEarn, resultAfter.tpEarn, "TP earned should match");
    }

    /// @notice Test that redeemTC operation results are the same before and after upgrade
    function test_RedeemTCResultsMatchBeforeAndAfterUpgrade() public {
        // Holder already has TC tokens on mainnet
        uint256 initialTcBalance = rifProToken.balanceOf(holder);
        require(initialTcBalance > 0, "Holder should have TC tokens");

        // Take snapshot before any operations
        uint256 snapshotId = vm.snapshot();

        // === Execute redeemTC BEFORE upgrade (single-collateral) ===
        RedeemTCResult memory resultBefore;
        {
            uint256 acBalanceBefore = rifToken.balanceOf(holder);
            uint256 tcBalanceBefore = rifProToken.balanceOf(holder);

            // Get exec fee for single-collateral queue
            uint256 execFee = rifQueueOld.execFee(MocQueueExecFees.OperType.redeemTC);

            vm.prank(holder);
            rifBucket.redeemTC{ value: execFee }(
                0.1 ether,
                0, // minAC
                holder,
                VENDOR
            );

            // Execute operation (single-collateral uses MocQueue directly)
            vm.roll(block.number + rifQueueOld.minOperWaitingBlk());
            rifQueueOld.execute(holder);

            // Capture results
            resultBefore.coverage = rifBucket.getCglb();
            resultBefore.tcAvailable = rifBucket.getTCAvailableToRedeem();
            int256 tpAvailableInt = rifBucket.getTPAvailableToMint(address(usdRifToken));
            resultBefore.tpAvailable = tpAvailableInt > 0 ? uint256(tpAvailableInt) : 0;
            resultBefore.acEarn = rifToken.balanceOf(holder) - acBalanceBefore;
            resultBefore.tcSpent = tcBalanceBefore - rifProToken.balanceOf(holder);
        }

        // Revert to snapshot (restore state before the operation)
        vm.revertTo(snapshotId);

        // === Execute redeemTC AFTER upgrade (multi-collateral) ===
        RedeemTCResult memory resultAfter;
        {
            _executeChanger();

            uint256 acBalanceBefore = rifToken.balanceOf(holder);
            uint256 tcBalanceBefore = rifProToken.balanceOf(holder);
            uint256 execCost = _getExecCost(rifQueue, MocQueueExecFees.OperType.redeemTC);

            vm.prank(holder);
            rifBucket.redeemTC{ value: execCost }(
                0.1 ether,
                0, // minAC
                holder,
                VENDOR
            );

            // Execute operation (multi-collateral uses MocMultiCollateralGuard)
            vm.roll(block.number + rifQueue.minOperWaitingBlk());
            mocMultiCollateralGuard.execute();

            // Capture results
            resultAfter.coverage = rifBucket.getCglb();
            resultAfter.tcAvailable = rifBucket.getTCAvailableToRedeem();
            int256 tpAvailableInt = rifBucket.getTPAvailableToMint(address(usdRifToken));
            resultAfter.tpAvailable = tpAvailableInt > 0 ? uint256(tpAvailableInt) : 0;
            resultAfter.acEarn = rifToken.balanceOf(holder) - acBalanceBefore;
            resultAfter.tcSpent = tcBalanceBefore - rifProToken.balanceOf(holder);
        }

        // Compare results
        assertEq(resultBefore.coverage, resultAfter.coverage, "Coverage should match");
        assertEq(resultBefore.tcAvailable, resultAfter.tcAvailable, "TC available should match");
        assertEq(resultBefore.tpAvailable, resultAfter.tpAvailable, "TP available should match");
        assertEq(resultBefore.acEarn, resultAfter.acEarn, "AC earned should match");
        assertEq(resultBefore.tcSpent, resultAfter.tcSpent, "TC spent should match");
    }

    /// @notice Test that mintTCandTP operation results are the same before and after upgrade
    function test_MintTCandTPResultsMatchBeforeAndAfterUpgrade() public {
        // Take snapshot before any operations
        uint256 snapshotId = vm.snapshot();

        // === Execute mintTCandTP BEFORE upgrade (single-collateral) ===
        MintTCandTPResult memory resultBefore;
        {
            uint256 acBalanceBefore = rifToken.balanceOf(holder);
            uint256 tcBalanceBefore = rifProToken.balanceOf(holder);
            uint256 tpBalanceBefore = usdRifToken.balanceOf(holder);

            // Get exec fee for single-collateral queue
            uint256 execFee = rifQueueOld.execFee(MocQueueExecFees.OperType.mintTCandTP);

            vm.prank(holder);
            rifBucket.mintTCandTP{ value: execFee }(address(usdRifToken), 0.1 ether, 50 ether, holder, VENDOR);

            // Execute operation (single-collateral uses MocQueue directly)
            vm.roll(block.number + rifQueueOld.minOperWaitingBlk());
            rifQueueOld.execute(holder);

            // Capture results
            resultBefore.coverage = rifBucket.getCglb();
            resultBefore.tcAvailable = rifBucket.getTCAvailableToRedeem();
            int256 tpAvailableInt = rifBucket.getTPAvailableToMint(address(usdRifToken));
            resultBefore.tpAvailable = tpAvailableInt > 0 ? uint256(tpAvailableInt) : 0;
            resultBefore.acSpent = acBalanceBefore - rifToken.balanceOf(holder);
            resultBefore.tcEarn = rifProToken.balanceOf(holder) - tcBalanceBefore;
            resultBefore.tpEarn = usdRifToken.balanceOf(holder) - tpBalanceBefore;
        }

        // Revert to snapshot (restore state before the operation)
        vm.revertTo(snapshotId);

        // === Execute mintTCandTP AFTER upgrade (multi-collateral) ===
        MintTCandTPResult memory resultAfter;
        {
            _executeChanger();

            uint256 acBalanceBefore = rifToken.balanceOf(holder);
            uint256 tcBalanceBefore = rifProToken.balanceOf(holder);
            uint256 tpBalanceBefore = usdRifToken.balanceOf(holder);
            uint256 execCost = _getExecCost(rifQueue, MocQueueExecFees.OperType.mintTCandTP);

            vm.prank(holder);
            rifBucket.mintTCandTP{ value: execCost }(address(usdRifToken), 0.1 ether, 50 ether, holder, VENDOR);

            // Execute operation (multi-collateral uses MocMultiCollateralGuard)
            vm.roll(block.number + rifQueue.minOperWaitingBlk());
            mocMultiCollateralGuard.execute();

            // Capture results
            resultAfter.coverage = rifBucket.getCglb();
            resultAfter.tcAvailable = rifBucket.getTCAvailableToRedeem();
            int256 tpAvailableInt = rifBucket.getTPAvailableToMint(address(usdRifToken));
            resultAfter.tpAvailable = tpAvailableInt > 0 ? uint256(tpAvailableInt) : 0;
            resultAfter.acSpent = acBalanceBefore - rifToken.balanceOf(holder);
            resultAfter.tcEarn = rifProToken.balanceOf(holder) - tcBalanceBefore;
            resultAfter.tpEarn = usdRifToken.balanceOf(holder) - tpBalanceBefore;
        }

        // Compare results
        assertEq(resultBefore.coverage, resultAfter.coverage, "Coverage should match");
        assertEq(resultBefore.tcAvailable, resultAfter.tcAvailable, "TC available should match");
        assertEq(resultBefore.tpAvailable, resultAfter.tpAvailable, "TP available should match");
        assertEq(resultBefore.acSpent, resultAfter.acSpent, "AC spent should match");
        assertEq(resultBefore.tcEarn, resultAfter.tcEarn, "TC earned should match");
        assertEq(resultBefore.tpEarn, resultAfter.tpEarn, "TP earned should match");
    }

    // ============ Tests: DocBucket Verification ============

    /// @notice Test that DocBucket was deployed correctly
    function test_DocBucketDeployedCorrectly() public view {
        // Verify DocBucket address is set
        assertTrue(address(docBucket) != address(0), "DocBucket should be deployed");

        // Verify it's a MocCARC20
        assertTrue(address(docBucket.acToken()) != address(0), "DocBucket should have AC token set");
    }

    /// @notice Test that swappers were deployed correctly
    function test_SwappersDeployedCorrectly() public view {
        address mocSwapperV3Multihop = getDeployedAddress("Swappers_MocSwapperV3MultihopProxy");

        assertTrue(mocSwapperV3Multihop != address(0), "MocSwapperV3Multihop should be deployed");
    }

    /// @notice Test that FeeFlow contracts were deployed correctly
    function test_FeeFlowDeployedCorrectly() public {
        address feesSplitter = getDeployedAddress("FeeFlow_FeesSplitterProxy");
        address reverseAuctionDOCtoMOC = getDeployedAddress("FeeFlow_ReverseAuctionDOCtoMOC");
        address reverseAuctionMOCtoDOC = getDeployedAddress("FeeFlow_ReverseAuctionMOCtoDOC");
        address rocrRewardsBufferAddr = getDeployedAddress("FeeFlow_RocrRewardsBuffer");

        assertTrue(feesSplitter != address(0), "FeesSplitter should be deployed");
        assertTrue(reverseAuctionDOCtoMOC != address(0), "ReverseAuctionDOCtoMOC should be deployed");
        assertTrue(reverseAuctionMOCtoDOC != address(0), "ReverseAuctionMOCtoDOC should be deployed");
        assertTrue(rocrRewardsBufferAddr != address(0), "RocrRewardsBuffer should be deployed");

        _executeChanger();

        assertEq(
            MocReverseAuction(payable(reverseAuctionMOCtoDOC)).outputAccount(),
            address(docBucket),
            "ReverseAuctionMOCtoDOC output account should be DocBucket"
        );
    }
}
