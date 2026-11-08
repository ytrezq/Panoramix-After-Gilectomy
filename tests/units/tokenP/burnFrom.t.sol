// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import "tests/Units.t.sol";

contract TokenP_BurnSelf_Units_Test is Units_Test {

    function setUp() public override {
        super.setUp();
        vm.startPrank(users.admin.addr);
        accessManager.grantRole(MINTER_ROLE_aEURp, users.dao.addr,0);

        vm.startPrank(users.dao.addr);
        aEURp.mint(users.alice.addr, INITIAL_BALANCE);
        aEURp.mint(users.dao.addr, INITIAL_BALANCE);
    }

    function test_burnFromItSelf() external {
        vm.startPrank(users.dao.addr);
        aEURp.burnFrom(INITIAL_BALANCE,users.dao.addr, users.dao.addr);
        assertEq(aEURp.balanceOf(users.dao.addr), 0);

    }

    function test_burnFromNotSender() external {
        vm.startPrank(users.alice.addr);
        aEURp.approve(users.dao.addr, INITIAL_BALANCE);

        vm.startPrank(users.dao.addr);
        aEURp.burnFrom(INITIAL_BALANCE,users.alice.addr, users.dao.addr);
        assertEq(aEURp.balanceOf(users.alice.addr), 0);
    }

    function test_burnFromNotSender_RevertWhen_NotEnoughAllowance() external {
        vm.startPrank(users.alice.addr);
        aEURp.approve(users.dao.addr, INITIAL_BALANCE - 1);

        vm.startPrank(users.dao.addr);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, users.dao.addr, INITIAL_BALANCE - 1, INITIAL_BALANCE));
        aEURp.burnFrom(INITIAL_BALANCE,users.alice.addr, users.dao.addr);
    }

    function test_revertWhen_CallerIsNotMinter() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        aEURp.burnFrom(INITIAL_BALANCE, users.alice.addr, users.hacker.addr);
    }

}