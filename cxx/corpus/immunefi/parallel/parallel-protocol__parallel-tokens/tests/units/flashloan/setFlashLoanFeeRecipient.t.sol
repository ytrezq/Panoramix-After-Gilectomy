// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";

import { FlashParallelTokenMockV2 } from "tests/mock/FlashParallelTokenMockV2.sol";
import "tests/Units.t.sol";

contract FlashParallelToken_SetFlashLoanFeeRecipient_Units_Test is Units_Test {
    address newFlashLoanFeeRecipient = makeAddr("newFlashLoanFeeRecipient");
    function test_SetFlashLoanFeeRecipient() external {
        vm.startPrank(users.dao.addr);

        vm.expectEmit(true, true, true, true);
        emit FlashLoan_EventsLib.FlashLoanFeeRecipientUpdated(newFlashLoanFeeRecipient);
        flashParallelToken.setFlashLoanFeeRecipient(newFlashLoanFeeRecipient);

        assertEq(flashParallelToken.flashLoanFeeRecipient(), newFlashLoanFeeRecipient);
    }

    function test_RevertWhen_CallerIsNotAllowed() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        flashParallelToken.setFlashLoanFeeRecipient(newFlashLoanFeeRecipient);
    }

    function test_RevertWhen_AddressZero() external {
        vm.startPrank(users.dao.addr);
        vm.expectRevert(abi.encodeWithSelector(CommonErrorsLib.AddressZero.selector));
        flashParallelToken.setFlashLoanFeeRecipient(address(0));
    }

}