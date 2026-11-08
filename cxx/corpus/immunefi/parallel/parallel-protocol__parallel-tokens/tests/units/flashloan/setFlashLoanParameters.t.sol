// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";

import { FlashParallelTokenMockV2 } from "tests/mock/FlashParallelTokenMockV2.sol";
import "tests/Units.t.sol";

contract FlashParallelToken_SetFlashLoanParameters_Units_Test is Units_Test {
    uint256 maxBorrowable = 1e18;
    bool isActive = true;
    function test_SetFlashLoanParameters() external {
        vm.startPrank(users.dao.addr);

        vm.expectEmit(true, true, true, true);
        emit FlashLoan_EventsLib.FlashLoanParametersUpdated(address(aEURp), DEFAULT_FEE_RATE, maxBorrowable, isActive);
        flashParallelToken.setFlashLoanParameters(address(aEURp), DEFAULT_FEE_RATE, maxBorrowable, isActive);

       (uint256 _maxBorrowable, uint64 _flashLoanFee,  bool _isActive) = flashParallelToken.tokenMap(address(aEURp));

        assertEq(_flashLoanFee, DEFAULT_FEE_RATE);
        assertEq(_maxBorrowable, maxBorrowable);
        assertTrue(_isActive);
    }

    function test_RevertWhen_CallerIsNotAllowed() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        flashParallelToken.setFlashLoanParameters(address(aEURp), DEFAULT_FEE_RATE, maxBorrowable, isActive);
    }

    function test_RevertWhen_FlashLoanFeeExceedsBaseParams() external {
        vm.startPrank(users.dao.addr);
        uint16 wrongFlashloanFee = uint16(PercentageMathLib.PERCENTAGE_FACTOR + 1);
        vm.expectRevert(abi.encodeWithSelector(FlashLoan_ErrorsLib.MaxFeesRateExceeded.selector));
        flashParallelToken.setFlashLoanParameters(address(aEURp), wrongFlashloanFee, maxBorrowable, isActive);
    }

}