// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Units.t.sol";

contract TokenP_Mint_Units_Test is Units_Test {

    function setUp() public override {
        super.setUp();
        vm.startPrank(users.admin.addr);
        accessManager.grantRole(MINTER_ROLE_aEURp, users.dao.addr,0);
    }

    function test_mint() external {
        vm.startPrank(users.dao.addr);
        aEURp.mint(users.alice.addr, INITIAL_BALANCE);
        assertEq(aEURp.balanceOf(users.alice.addr), INITIAL_BALANCE);
    }

    function test_revertWhen_CallerIsNotMinter() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        aEURp.mint(users.alice.addr, INITIAL_BALANCE);
    }

}