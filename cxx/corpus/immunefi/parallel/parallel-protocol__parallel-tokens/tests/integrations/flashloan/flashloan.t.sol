
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ReentrancyGuardTransientUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import "tests/Integrations.t.sol";

import "tests/mock/FlashLoanReceiverMock.sol";

contract FlashParallelToken_FlashLoan_Integrations_Test is Integrations_Test {
    FlashLoanReceiverMock flashLoanReceiverMock;
    uint256 maxBorrowable = 10000e18;
    function setUp() public override {
        Integrations_Test.setUp();

        flashLoanReceiverMock = new FlashLoanReceiverMock();

        vm.startPrank(users.dao.addr);
        flashParallelToken.setFlashLoanParameters(address(aEURp), DEFAULT_FEE_RATE, maxBorrowable, true);
    }
    
    function test_FlashLoan() public {
        uint256 borrowAmount = 100e18;
        uint256 fee = flashParallelToken.flashFee(address(aEURp), borrowAmount);
        vm.startPrank(users.admin.addr);
        aEURp.mint(address(flashLoanReceiverMock), fee);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit FlashLoan_EventsLib.FlashLoan(address(aEURp), borrowAmount, IERC3156FlashBorrower(address(flashLoanReceiverMock)));

        flashParallelToken.flashLoan(flashLoanReceiverMock, address(aEURp), borrowAmount, "");

        assertEq(aEURp.balanceOf(address(flashLoanReceiverMock)), 0);
        assertEq(aEURp.balanceOf(address(flashParallelToken)), fee);
    }

    function test_FlashLoan_RevertWhen_TokenNotWhitelisted() public {
        vm.expectRevert(abi.encodeWithSelector(FlashLoan_ErrorsLib.UnsupportedToken.selector));
        flashParallelToken.flashLoan(flashLoanReceiverMock, address(bEURp), maxBorrowable, "");
    }
    
    function test_FlashLoan_RevertWhen_TokenNotActive() public {
        flashParallelToken.toggleActiveToken(address(aEURp));
        vm.expectRevert(abi.encodeWithSelector(FlashLoan_ErrorsLib.UnsupportedToken.selector));
        flashParallelToken.flashLoan(flashLoanReceiverMock, address(aEURp), maxBorrowable, "");
    }

    function test_FlashLoan_RevertWhen_BorrowAmountTooBig() public {
        uint256 bigBorrowAmount =  flashParallelToken.maxFlashLoan(address(aEURp)) + 1;
        vm.expectRevert(abi.encodeWithSelector(FlashLoan_ErrorsLib.TooBigAmount.selector));
        flashParallelToken.flashLoan(flashLoanReceiverMock, address(aEURp),bigBorrowAmount, "");
    }

    function test_FlashLoan_RevertWhen_InvalidReturnMessage() public {
        vm.expectRevert(abi.encodeWithSelector(FlashLoan_ErrorsLib.InvalidReturnMessage.selector));
        flashParallelToken.flashLoan(flashLoanReceiverMock, address(aEURp), 10 ** 21, "");
    }

    function test_FlashLoan_RevertWhen_ReentrantFlashLoan() public {
        uint256 borrowAmount = 2e18;
        uint256 fee = flashParallelToken.flashFee(address(aEURp), borrowAmount);

        vm.startPrank(users.admin.addr);
        aEURp.mint(address(flashLoanReceiverMock), fee);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector));
        flashParallelToken.flashLoan(flashLoanReceiverMock, address(aEURp),borrowAmount, "");
    }
    
}