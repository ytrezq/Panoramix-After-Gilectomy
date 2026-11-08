
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Integrations.t.sol";


contract FlashParallelToken_AccrueInterestToFeeRecipient_Integrations_Test is Integrations_Test {

    function setUp() public override {
        super.setUp();
        vm.startPrank(users.admin.addr);
        aEURp.mint(address(flashParallelToken), INITIAL_BALANCE);
    }

    function test_AccrueInterestToFeeRecipientToTreasury() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(aEURp);
        flashParallelToken.accrueInterestToFeeRecipient(tokens);
        assertEq(aEURp.balanceOf(address(flashParallelToken)), 0);
        assertEq(aEURp.balanceOf(address(users.feesRecipient.addr)), INITIAL_BALANCE);
    }

    function test_AccrueInterestToFeeRecipientToTreasury_ZeroBalance() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(bEURp);
        flashParallelToken.accrueInterestToFeeRecipient(tokens);
        assertEq(bEURp.balanceOf(address(flashParallelToken)), 0);
        assertEq(bEURp.balanceOf(address(users.feesRecipient.addr)), 0);
    }

}