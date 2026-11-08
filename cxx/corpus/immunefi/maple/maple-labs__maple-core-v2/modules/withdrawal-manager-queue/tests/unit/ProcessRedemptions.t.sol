// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { TestBase } from "../utils/TestBase.sol";

// TODO: Add ManualSharesIncreased event to tests
// TODO: Add test case for reentrancy check
contract ProcessRedemptionsTests is TestBase {

    event RequestDecreased(uint128 indexed requestId, uint256 shares);
    event RequestProcessed(uint128 indexed requestId, address indexed owner, uint256 shares, uint256 assets);
    event RequestRemoved(uint128 indexed requestId);

    uint256 assetsDeposited = 100e18;
    uint256 sharesLocked    = 250e18;

    function setUp() public override {
        super.setUp();

        asset.mint(address(pool), assetsDeposited);
        pool.mint(wm, sharesLocked);

        poolManager.__setTotalAssets(assetsDeposited);
        withdrawalManager.__setTotalShares(sharesLocked);
    }

    function test_processRedemptions_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("WM:PAUSED");
        withdrawalManager.processRedemptions(sharesLocked);
    }

    function test_processRedemptions_notRedeemer() external {
        globals.__setIsInstanceOf(false);

        vm.expectRevert("WM:NOT_REDEEMER");
        withdrawalManager.processRedemptions(sharesLocked);
    }

    function test_processRedemptions_zeroShares() external {
        vm.prank(poolDelegate);
        vm.expectRevert("WM:PR:ZERO_SHARES");
        withdrawalManager.processRedemptions(0);
    }

    function test_processRedemptions_lowLiquidity() external {
        asset.burn(address(pool), 1);

        vm.prank(poolDelegate);
        vm.expectRevert("WM:PR:LOW_LIQUIDITY");
        withdrawalManager.processRedemptions(sharesLocked);
    }

    function test_processRedemptions_poolDelegate() external {
        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(sharesLocked);

        assertQueue({ nextRequestId: 1, lastRequestId: 0 });
    }

    function test_processRedemptions_governor() external {
        vm.prank(governor);
        withdrawalManager.processRedemptions(sharesLocked);

        assertQueue({ nextRequestId: 1, lastRequestId: 0 });
    }

    function test_processRedemptions_operationalAdmin() external {
        vm.prank(operationalAdmin);
        withdrawalManager.processRedemptions(sharesLocked);

        assertQueue({ nextRequestId: 1, lastRequestId: 0 });
    }

    function test_processRedemptions_bot() external {
        globals.__setIsInstanceOf(true);

        vm.prank(redeemer);
        withdrawalManager.processRedemptions(sharesLocked);

        assertQueue({ nextRequestId: 1, lastRequestId: 0 });
    }

    function test_processRedemptions_manual_complete() external {
        withdrawalManager.__setManualWithdrawal(lp, true);
        withdrawalManager.__setRequest(1, lp, sharesLocked);
        withdrawalManager.__setQueue(1, 1);

        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(sharesLocked);

        assertEq(withdrawalManager.totalShares(),             sharesLocked);
        assertEq(withdrawalManager.requestIds(lp),            0);
        assertEq(withdrawalManager.manualSharesAvailable(lp), sharesLocked);

        assertRequest({ requestId: 1, owner: address(0), shares: 0 });

        assertQueue({ nextRequestId: 2, lastRequestId: 1 });
    }

    function test_processRedemptions_manual_partial() external {
        withdrawalManager.__setManualWithdrawal(lp, true);
        withdrawalManager.__setRequest(1, lp, sharesLocked);
        withdrawalManager.__setQueue(1, 1);

        // Only half of the liquidity is available.
        asset.burn(address(pool), assetsDeposited / 2);

        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(sharesLocked / 2);

        assertEq(withdrawalManager.totalShares(),             sharesLocked);
        assertEq(withdrawalManager.requestIds(lp),            1);
        assertEq(withdrawalManager.manualSharesAvailable(lp), sharesLocked / 2);

        assertRequest({ requestId: 1, owner: lp, shares: sharesLocked / 2 });

        assertQueue({ nextRequestId: 1, lastRequestId: 1 });
    }

    function test_processRedemptions_manual_overkill() external {
        withdrawalManager.__setManualWithdrawal(lp, true);
        withdrawalManager.__setRequest(1, lp, sharesLocked);
        withdrawalManager.__setQueue(1, 1);

        // Add extra liquidity.
        asset.mint(address(pool), assetsDeposited);

        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(2 * sharesLocked);

        assertEq(withdrawalManager.totalShares(),             sharesLocked);
        assertEq(withdrawalManager.requestIds(lp),            0);
        assertEq(withdrawalManager.manualSharesAvailable(lp), sharesLocked);

        assertRequest({ requestId: 1, owner: address(0), shares: 0 });

        assertQueue({ nextRequestId: 2, lastRequestId: 1 });
    }

    function test_processRedemptions_automatic_complete() external {
        withdrawalManager.__setRequest(1, lp, sharesLocked);
        withdrawalManager.__setQueue(1, 1);

        vm.expectEmit();
        emit RequestProcessed(1, lp, sharesLocked, assetsDeposited);

        vm.expectEmit();
        emit RequestRemoved(1);

        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(sharesLocked);

        assertEq(withdrawalManager.totalShares(), 0);

        assertEq(withdrawalManager.requestIds(lp), 0);

        assertRequest({ requestId: 1, owner: address(0), shares: 0 });

        assertQueue({ nextRequestId: 2, lastRequestId: 1 });
    }

    function test_processRedemptions_automatic_partial() external {
        withdrawalManager.__setRequest(1, lp, sharesLocked);
        withdrawalManager.__setQueue(1, 1);

        // Only half of the liquidity is available.
        asset.burn(address(pool), assetsDeposited / 2);

        vm.expectEmit();
        emit RequestProcessed(1, lp, sharesLocked / 2, assetsDeposited / 2);

        vm.expectEmit();
        emit RequestDecreased(1, sharesLocked / 2);

        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(sharesLocked / 2);

        assertEq(withdrawalManager.totalShares(), sharesLocked / 2);

        assertEq(withdrawalManager.requestIds(lp), 1);

        assertRequest({ requestId: 1, owner: lp, shares: sharesLocked / 2 });

        assertQueue({ nextRequestId: 1, lastRequestId: 1 });
    }

    function test_processRedemptions_automatic_overkill() external {
        withdrawalManager.__setRequest(1, lp, sharesLocked);
        withdrawalManager.__setQueue(1, 1);

        // Add extra liquidity.
        asset.mint(address(pool), assetsDeposited);

        vm.expectEmit();
        emit RequestProcessed(1, lp, sharesLocked, assetsDeposited);

        vm.expectEmit();
        emit RequestRemoved(1);

        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(2 * sharesLocked);

        assertEq(withdrawalManager.totalShares(), 0);

        assertEq(withdrawalManager.requestIds(lp), 0);

        assertRequest({ requestId: 1, owner: address(0), shares: 0 });

        assertQueue({ nextRequestId: 2, lastRequestId: 1 });
    }

    function test_processRedemptions_multiple() external {
        address lp1 = makeAddr("lp1");
        address lp2 = makeAddr("lp2");

        withdrawalManager.__setRequest(1, lp1, 100e18);
        withdrawalManager.__setRequest(2, lp2, 150e18);
        withdrawalManager.__setQueue(1, 2);

        vm.expectEmit();
        emit RequestProcessed(1, lp1, 100e18, 40e18);

        vm.expectEmit();
        emit RequestRemoved(1);

        vm.expectEmit();
        emit RequestProcessed(2, lp2, 150e18, 60e18);

        vm.expectEmit();
        emit RequestRemoved(2);

        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(sharesLocked);

        assertEq(withdrawalManager.totalShares(), 0);

        assertEq(withdrawalManager.requestIds(lp1), 0);
        assertEq(withdrawalManager.requestIds(lp2), 0);

        assertRequest({ requestId: 1, owner: address(0), shares: 0 });
        assertRequest({ requestId: 2, owner: address(0), shares: 0 });

        assertQueue({ nextRequestId: 3, lastRequestId: 2 });
    }

}

contract ComplexRedemptionTests is TestBase {

    event RequestDecreased(uint128 indexed requestId, uint256 shares);
    event RequestProcessed(uint128 indexed requestId, address indexed owner, uint256 shares, uint256 assets);
    event RequestRemoved(uint128 indexed requestId);

    function test_processRedemptions_complex() external {
        uint256 totalAssets     = 100e18;
        uint256 totalShares     = 250e18;
        uint256 sharesToProcess = 200e18;

        asset.mint(address(pool), totalShares);
        pool.mint(wm, totalShares);

        poolManager.__setTotalAssets(totalAssets);

        withdrawalManager.__setRequest(1, address(0), 0);       // Already processed
        withdrawalManager.__setRequest(2, address(2), 100e18);  // Fully processed
        withdrawalManager.__setRequest(3, address(3), 50e18);   // Manual
        withdrawalManager.__setRequest(4, address(0), 0);       // Cancelled
        withdrawalManager.__setRequest(5, address(5), 75e18);   // Partially processed
        withdrawalManager.__setRequest(6, address(6), 25e18);   // Out of shares

        withdrawalManager.__setManualWithdrawal(address(3), true);
        withdrawalManager.__setTotalShares(totalShares);
        withdrawalManager.__setQueue(2, 6);

        vm.expectEmit();
        emit RequestProcessed(2, address(2), 100e18, 40e18);

        vm.expectEmit();
        emit RequestRemoved(2);

        vm.expectEmit();
        emit RequestProcessed(5, address(5), 50e18, 20e18);

        vm.expectEmit();
        emit RequestDecreased(5, 50e18);

        vm.prank(poolDelegate);
        withdrawalManager.processRedemptions(sharesToProcess);

        assertEq(withdrawalManager.requestIds(address(2)), 0);
        assertEq(withdrawalManager.requestIds(address(3)), 0);
        assertEq(withdrawalManager.requestIds(address(4)), 0);
        assertEq(withdrawalManager.requestIds(address(5)), 5);
        assertEq(withdrawalManager.requestIds(address(6)), 6);

        assertRequest({ requestId: 1, owner: address(0), shares: 0 });
        assertRequest({ requestId: 2, owner: address(0), shares: 0 });
        assertRequest({ requestId: 3, owner: address(0), shares: 0 });
        assertRequest({ requestId: 4, owner: address(0), shares: 0 });
        assertRequest({ requestId: 5, owner: address(5), shares: 25e18 });
        assertRequest({ requestId: 6, owner: address(6), shares: 25e18 });

        assertEq(withdrawalManager.manualSharesAvailable(address(3)), 50e18);

        // Shares from the manual request are not redeemed.
        assertEq(withdrawalManager.totalShares(), totalShares - sharesToProcess + 50e18);

        // Request `5` is partially processed and becomes the next request.
        assertQueue({ nextRequestId: 5, lastRequestId: 6 });
    }

}
