// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Setup } from "test/utils/Setup.sol";
import { Operator } from "src/Operator.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract OperatorTest is Setup {
    address public gaugeVoter = address(0x2);
    address public daoVoter = address(0x3);
    address public lockerUser = address(0x4);
    address public user = address(0x5);

    event GaugeVoterUpdated(address indexed voter, bool isVoter);
    event DaoVoterUpdated(address indexed voter, bool isVoter);
    event LockerUpdated(address indexed locker, bool isLocker);
    event Swept(address indexed token, address indexed to, uint256 amount);

    function setUp() public override {
        super.setUp();
        // Setup permissioned roles
        vm.startPrank(operator.owner());
        operator.authorizeDaoVoter(daoVoter, true);
        operator.authorizeGaugeVoter(gaugeVoter, true);
        operator.authorizeLocker(lockerUser, true);
        vm.stopPrank();
        assertGt(getPastVotingPower(block.timestamp), 0, "Voting power is 0");
        increaseLock(address(locker), 1_000_000e18);
    }

    // ============================================
    // Constructor Tests
    // ============================================

    function test_ConstructorRevertsWithZeroLocker() public {
        vm.expectRevert("!valid");
        new Operator(payable(address(0)), address(gaugeController), address(daoVoting), address(yToken));
    }

    // ============================================
    // Role Management Tests
    // ============================================

    function test_SetGaugeVoter() public {
        operator.authorizeGaugeVoter(gaugeVoter, true);
        assertTrue(operator.gaugeVoters(gaugeVoter));
    }

    function test_SetGaugeVoterRevertsWhenNotOwner() public {
        vm.expectRevert("!owner");
        vm.prank(user);
        operator.authorizeGaugeVoter(gaugeVoter, true);
    }

    function test_SetDaoVoter() public {
        operator.authorizeDaoVoter(daoVoter, true);
        assertTrue(operator.daoVoters(daoVoter));
    }

    function test_SetDaoVoterRevertsWhenNotOwner() public {
        vm.expectRevert("!owner");
        vm.prank(user);
        operator.authorizeDaoVoter(daoVoter, true);
    }

    function test_SetLocker() public {
        operator.authorizeLocker(lockerUser, true);
        assertTrue(operator.lockers(lockerUser));
    }

    function test_SetLockerRevertsWhenNotOwner() public {
        vm.expectRevert("!owner");
        vm.prank(user);
        operator.authorizeLocker(lockerUser, true);
    }

    // ============================================
    // Gauge Voting Tests
    // ============================================

    function test_VoteForGaugeWeights() public {
        (address[] memory gauges, uint256[] memory weights) = getGaugeVoteData();

        vm.prank(gaugeVoter);
        operator.voteForGaugeWeights(gauges, weights);
    }

    function test_VoteForGaugeWeightsAllowsOwner() public {
        (address[] memory gauges, uint256[] memory weights) = getGaugeVoteData();
        operator.voteForGaugeWeights(gauges, weights);
    }

    function test_VoteForGaugeWeightsRevertsWhenNotAuthorized() public {
        (address[] memory gauges, uint256[] memory weights) = getGaugeVoteData();
        vm.expectRevert("!gauge voter");
        vm.prank(user);
        operator.voteForGaugeWeights(gauges, weights);
    }

    // ============================================
    // Lock Management Tests
    // ============================================

    function test_Lock() public {
        uint256 startBalance = operator.getVotes();
        deal(address(token), address(locker), 1000e18);
        vm.prank(lockerUser);
        operator.lock(1000e18);
        assertGt(operator.getVotes(), startBalance, "Votes are not greater than previous");
    }

    function test_LockAllowsOwner() public {
        uint256 amount = 1000e18;
        deal(address(token), address(locker), amount);
        vm.prank(operator.owner());
        operator.lock(amount);
        assertGe(operator.getVotes(), amount, "Votes are not equal to amount");
    }

    function test_LockRevertsWhenNotAuthorized() public {
        vm.expectRevert("!locker");
        vm.prank(user);
        operator.lock(1000e18);
    }

    function test_IncreaseLockRevertsWhenNotAuthorized() public {
        vm.expectRevert("!locker");
        vm.prank(user);
        operator.lock(500e18);
    }

    // ============================================
    // View Function Tests
    // ============================================

    function test_GetLockTimeRemaining() public {
        toggleInfiniteLock(address(locker), false);
        uint256 remaining = operator.getLockTimeRemaining();
        assertGt(remaining, 0, "Remaining is 0");
        skip(100 days);
        assertLt(operator.getLockTimeRemaining(), remaining, "Remaining is not less than previous");

        vm.prank(address(locker));
        escrow.increase_unlock_time(block.timestamp + MAX_LOCK_TIME);
        assertApproxEqAbs(operator.getLockTimeRemaining(), MAX_LOCK_TIME, 7 days, "Remaining is not MAX_LOCK_TIME");

        vm.prank(address(locker));
        escrow.infinite_lock_toggle();
        assertEq(operator.getLockTimeRemaining(), type(uint256).max, "Remaining is not infinite");

        skip(100 days);
        assertEq(operator.getLockTimeRemaining(), type(uint256).max, "Remaining is not infinite");

        vm.prank(address(locker));
        escrow.infinite_lock_toggle();
        skip(100 days);
        assertLt(operator.getLockTimeRemaining(), MAX_LOCK_TIME, "Remaining is not less than MAX_LOCK_TIME");
    }

    function test_GetLockTimeRemainingReturnsZeroWhenExpired() public {
        toggleInfiniteLock(address(locker), false);
        // Skip past the unlock time
        uint256 remaining = operator.getLockTimeRemaining();
        if (remaining == type(uint256).max) {
            vm.prank(address(locker));
            escrow.infinite_lock_toggle();
            remaining = operator.getLockTimeRemaining();
        }
        skip(remaining);
        assertEq(operator.getLockTimeRemaining(), 0);
    }

    function test_GetVotes() public view {
        uint256 balance = operator.getVotes();
        assertGt(balance, 0);
    }

    // ============================================
    // Sweep Tests
    // ============================================

    function test_Sweep() public {
        MockERC20 someToken = new MockERC20("Some", "SOME");
        someToken.mint(address(operator), 1000e18);

        address recipient = address(0x999);
        operator.sweep(address(someToken), recipient, 1000e18);

        assertEq(someToken.balanceOf(recipient), 1000e18);
        assertEq(someToken.balanceOf(address(operator)), 0);
    }

    function test_SweepRevertsWhenNotOwner() public {
        vm.expectRevert("!owner");
        vm.prank(user);
        operator.sweep(address(token), user, 100e18);
    }

    function getGaugeVoteData() public view returns (address[] memory gauges, uint256[] memory weights) {
        uint256 n_gauges = 2;//gaugeController.n_gauges();
        gauges = new address[](n_gauges);
        weights = new uint256[](n_gauges);
        uint256 k;
        for (uint256 i = 0; i < n_gauges || k < 2; i++) {
            address g = gaugeController.gauges(i);
            if (gaugeController.is_killed(g)) continue;
            gauges[k] = g;
            weights[k] = 5000;
            k++;
        }
        return (gauges, weights);
    }

    // ============================================
    // Migrate Operator Tests
    // ============================================

    function test_MigrateToNewOperator() public {
        // given: Original operator has state and authorizations
        assertTrue(operator.gaugeVoters(gaugeVoter));
        assertTrue(operator.daoVoters(daoVoter));
        assertTrue(operator.lockers(lockerUser));

        // when: Deploy new operator and migrate
        Operator newOperator = new Operator(
            payable(address(locker)),
            address(gaugeController),
            address(daoVoting),
            address(yToken)
        );

        vm.startPrank(locker.owner());
        // Re-authorize roles on new operator
        newOperator.authorizeDaoVoter(daoVoter, true);
        newOperator.authorizeGaugeVoter(gaugeVoter, true);
        newOperator.authorizeLocker(lockerUser, true);

        // Switch locker to new operator
        locker.setOperator(address(newOperator));
        vm.stopPrank();

        // then: New operator has correct state
        assertEq(locker.operator(), address(newOperator));
        assertTrue(newOperator.gaugeVoters(gaugeVoter));
        assertTrue(newOperator.daoVoters(daoVoter));
        assertTrue(newOperator.lockers(lockerUser));

        // Verify old operator cannot execute via locker
        vm.prank(address(operator));
        vm.expectRevert("!authorized");
        locker.safeExecute(
            payable(address(escrow)),
            0,
            abi.encodeWithSelector(escrow.increase_amount.selector, 1000e18)
        );
    }
}
