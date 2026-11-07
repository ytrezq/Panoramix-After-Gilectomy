// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Setup } from "test/utils/Setup.sol";
import { Locker } from "src/Locker.sol";
import { Operator } from "src/Operator.sol";
import { MockTarget } from "test/mocks/MockTarget.sol";
import { IYBVotingEscrow } from "src/interfaces/yb/IYBVotingEscrow.sol";

contract LockerTest is Setup {
    MockTarget public target;

    address public user = address(0x3);

    event OperatorUpdated(address operator);
    event Executed(address indexed caller, address indexed to);

    function setUp() public override {
        super.setUp();
        target = new MockTarget();
    }

    // ============================================
    // Constructor Tests
    // ============================================

    function test_ConstructorRevertsWithZeroAddresses() public {
        vm.expectRevert("!valid");
        new Locker(address(this), address(0), address(escrow));

        vm.expectRevert("!valid");
        new Locker(address(this), address(token), address(0));
    }

    // ============================================
    // setOperator Tests
    // ============================================

    function test_SetOperator() public {
        locker.setOperator(address(operator));
        assertEq(locker.operator(), address(operator));
    }

    function test_SetOperatorRevertsWhenNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        vm.prank(user);
        locker.setOperator(address(operator));
    }

    function test_SetOperatorRevertsWithZeroAddress() public {
        vm.expectRevert("!valid");
        locker.setOperator(address(0));
    }

    // ============================================
    // execute Tests
    // ============================================

    function test_ExecuteByOwnerAndOperator() public {
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);
        // Owner can execute (owner is this test contract)
        (bool success, ) = locker.execute(payable(address(target)), 0, data);
        assertTrue(success);
        assertEq(target.value(), 42);

        // Operator can execute
        locker.setOperator(address(operator));
        vm.prank(address(operator));
        (success, ) = locker.execute(payable(address(target)), 0, data);
        assertTrue(success);
    }

    function test_ExecuteRevertsWhenNotAuthorized() public {
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);
        vm.expectRevert("!authorized");
        vm.prank(user);
        locker.execute(payable(address(target)), 0, data);
    }

    function test_ExecuteReturnsFailureForRevertingCall() public {
        target.setShouldRevert(true);
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42); // fake call
        (bool success, ) = locker.execute(payable(address(target)), 0, data);
        assertFalse(success);
    }

    // ============================================
    // safeExecute Tests
    // ============================================

    function test_SafeExecuteRevertsWhenNotAuthorized() public {
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);
        vm.expectRevert("!authorized");
        vm.prank(user);
        locker.safeExecute(payable(address(target)), 0, data);
    }

    function test_SafeExecuteRevertsOnFailedCall() public {
        target.setShouldRevert(true);
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);

        vm.expectRevert("call failed");
        locker.safeExecute(payable(address(target)), 0, data);
    }

    // ============================================
    // Edge Cases
    // ============================================

    function test_OperatorChangeRevokesAccess() public {
        locker.setOperator(address(operator));

        // Change to different operator
        address newOperator = address(0x4);
        locker.setOperator(newOperator);

        // Old operator can no longer execute
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 100);
        vm.expectRevert("!authorized");
        vm.prank(address(operator));
        locker.execute(payable(address(target)), 0, data);
    }

    // ============================================
    // increase_amount Blocking Tests
    // ============================================

    function test_OwnerCannotCallIncreaseAmount() public {
        // given: Locker has tokens
        deal(address(token), address(locker), 1000e18);
        bytes memory data = abi.encodeWithSelector(IYBVotingEscrow.increase_amount.selector, 1000e18);
        vm.expectRevert("Blocked selector");
        locker.execute(payable(address(escrow)), 0, data);
    }

    function test_OperatorCanCallIncreaseAmount() public {
        locker.setOperator(address(operator));
        deal(address(token), address(locker), 1000e18);
        bytes memory data = abi.encodeWithSelector(IYBVotingEscrow.increase_amount.selector, 1000e18);
        vm.prank(address(operator));
        (bool success, ) = locker.execute(payable(address(escrow)), 0, data);
        assertTrue(success);
    }

    function test_OperatorLockFunctionWorks() public {
        // given: Operator is set and locker has tokens
        locker.setOperator(address(operator));
        deal(address(token), address(locker), 1000e18);
        uint256 lockedBefore = operator.getLockedAmount();

        // when: Call lock via operator (happy path)
        vm.prank(address(yToken));
        operator.lock(1000e18);

        // then: Lock succeeded and cache updated
        assertGt(operator.getLockedAmount(), lockedBefore);
        assertEq(operator.cachedLockedAmount(), operator.getLockedAmount());
    }

    function test_OwnerCanCallOtherEscrowFunctions() public {
        // given: Operator is set
        locker.setOperator(address(operator));

        // when: Owner calls non-blocked escrow function
        bytes memory data = abi.encodeWithSelector(IYBVotingEscrow.infinite_lock_toggle.selector);
        (bool success, ) = locker.execute(payable(address(escrow)), 0, data);

        // then: Call succeeds
        assertTrue(success);
    }

    // Test ability to transfer lock to a new contract
    function test_MigrateToNewLocker() public {
        address predictedLockerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        deal(address(token), predictedLockerAddress, 1e18);
        Locker newLocker = new Locker(address(this), address(token), address(escrow));

        uint256 tokenId = escrow.tokenOfOwnerByIndex(address(locker), 0);
        vm.prank(address(locker));
        escrow.safeTransferFrom(address(locker), address(newLocker), tokenId);

        assertEq(escrow.getVotes(address(locker)), 0);
        assertGt(escrow.getVotes(address(newLocker)), 0);
        assertEq(operator.getLockedAmount(), 0);
        assertEq(operator.getVotes(), 0);


        Operator newOperator = new Operator(payable(address(newLocker)), address(gaugeController), address(daoVoting), address(yToken));
        vm.prank(locker.owner());
        newLocker.setOperator(address(newOperator));
        assertGt(newOperator.getLockedAmount(), 0);
        assertGt(newOperator.getVotes(), 0);
        assertGt(newOperator.cachedLockedAmount(), 0);
        assertEq(newOperator.cachedLockedAmount(), newOperator.getLockedAmount());
    }
}
