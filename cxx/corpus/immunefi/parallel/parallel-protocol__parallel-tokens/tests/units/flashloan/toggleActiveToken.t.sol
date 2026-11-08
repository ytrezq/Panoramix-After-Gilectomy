// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";

import { FlashParallelTokenMockV2 } from "tests/mock/FlashParallelTokenMockV2.sol";
import "tests/Units.t.sol";

contract FlashParallelToken_SetFlashLoanParameters_Units_Test is Units_Test {
    uint256 maxBorrowable = 1e18;
    bool isActive = true;

    function setUp() public override {
        super.setUp();
        vm.startPrank(users.dao.addr);
        flashParallelToken.setFlashLoanParameters(address(aEURp), DEFAULT_FEE_RATE, maxBorrowable, isActive);
        vm.stopPrank();
    }

    function test_ToggleActiveToken() external {
        vm.startPrank(users.dao.addr);

        vm.expectEmit(true, true, true, true);
        emit FlashLoan_EventsLib.ActiveTokenToggled(address(aEURp), !isActive);
        flashParallelToken.toggleActiveToken(address(aEURp));
        
       (uint256 _maxBorrowable, uint64 _flashLoanFee,  bool _isActive) = flashParallelToken.tokenMap(address(aEURp));

        assertEq(_flashLoanFee, DEFAULT_FEE_RATE);
        assertEq(_maxBorrowable, maxBorrowable);
        assertFalse(_isActive);
    }

    function test_RevertWhen_CallerIsNotAllowed() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        flashParallelToken.toggleActiveToken(address(aEURp));
    }


}