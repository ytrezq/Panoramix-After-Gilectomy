// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {Ownable2StepWithGuardian, IWithGuardian} from '../src/contracts/access-control/Ownable2StepWithGuardian.sol';

contract ImplOwnable2StepWithGuardian is Ownable2StepWithGuardian {
  constructor(
    address initialOwner,
    address guardian
  ) Ownable2StepWithGuardian(initialOwner, guardian) {}

  function mock_onlyGuardian() external onlyGuardian {}

  function mock_onlyOwnerOrGuardian() external onlyOwnerOrGuardian {}
}

contract TestOfOwnable2StepWithGuardian is Test {
  ImplOwnable2StepWithGuardian public withGuardian;

  address owner = makeAddr('owner');
  address guardian = makeAddr('guardian');

  function setUp() public {
    withGuardian = new ImplOwnable2StepWithGuardian(address(this), address(this));
    assertEq(withGuardian.owner(), address(this));
    assertEq(withGuardian.guardian(), address(this));
    withGuardian.transferOwnership(owner);
    vm.prank(owner);
    withGuardian.acceptOwnership();
    withGuardian.updateGuardian(guardian);
  }

  function testConstructorLogic() external view {
    assertEq(withGuardian.owner(), owner);
    assertEq(withGuardian.guardian(), guardian);
  }

  function testTransferOwnershipIsTwoStep(address newOwner) external {
    vm.assume(newOwner != owner && newOwner != address(0));
    vm.prank(owner);
    withGuardian.transferOwnership(newOwner);
    assertEq(withGuardian.owner(), owner);
    assertEq(withGuardian.pendingOwner(), newOwner);

    vm.prank(newOwner);
    withGuardian.acceptOwnership();
    assertEq(withGuardian.owner(), newOwner);
    assertEq(withGuardian.pendingOwner(), address(0));
  }

  function testAcceptOwnershipNoAccess(address caller) external {
    address newOwner = makeAddr('newOwner');
    vm.assume(caller != newOwner);
    vm.prank(owner);
    withGuardian.transferOwnership(newOwner);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
    vm.prank(caller);
    withGuardian.acceptOwnership();
  }

  function testGuardianUpdateViaGuardian(address newGuardian) external {
    vm.startPrank(guardian);
    withGuardian.updateGuardian(newGuardian);
  }

  function testGuardianUpdateViaOwner(address newGuardian) external {
    vm.prank(owner);
    withGuardian.updateGuardian(newGuardian);
  }

  function testGuardianUpdateNoAccess() external {
    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, address(this))
    );
    withGuardian.updateGuardian(guardian);
  }

  function test_onlyGuardianGuard() external {
    vm.prank(guardian);
    withGuardian.mock_onlyGuardian();
  }

  function test_onlyGuardianGuard_shouldRevert() external {
    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianInvalidCaller.selector, address(this))
    );
    withGuardian.mock_onlyGuardian();
  }
}
