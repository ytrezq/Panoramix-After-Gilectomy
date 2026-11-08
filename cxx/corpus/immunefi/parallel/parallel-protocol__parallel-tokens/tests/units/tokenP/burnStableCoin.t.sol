// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Units.t.sol";

contract TokenP_BurnStableCoin_Units_Test is Units_Test {

    function setUp() public override {
        super.setUp();
        vm.startPrank(users.admin.addr);
        accessManager.grantRole(MINTER_ROLE_aEURp, users.admin.addr,0);
        aEURp.mint(users.alice.addr, INITIAL_BALANCE);
    }

    function test_burnStableCoin() external {
        vm.startPrank(users.alice.addr);
        aEURp.burnStablecoin(INITIAL_BALANCE);
        assertEq(aEURp.balanceOf(users.alice.addr), 0);
    }

}