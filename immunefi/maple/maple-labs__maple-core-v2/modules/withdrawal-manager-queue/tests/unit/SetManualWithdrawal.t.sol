// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { TestBase } from "../utils/TestBase.sol";

contract SetManualWithdrawalTests is TestBase {

    event ManualWithdrawalSet(address indexed account, bool isManual);

    function test_setManualWithdrawal_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("WM:PAUSED");
        withdrawalManager.setManualWithdrawal(lp, true);
    }

    function test_setManualWithdrawal_notProtocolAdmin() external {
        vm.expectRevert("WM:NOT_PD_OR_GOV_OR_OA");
        withdrawalManager.setManualWithdrawal(lp, true);
    }

    function test_setManualWithdrawal_existingRequest() external {
        withdrawalManager.__setRequest(1, lp, 100e18);

        vm.prank(poolDelegate);
        vm.expectRevert("WM:SMW:IN_QUEUE");
        withdrawalManager.setManualWithdrawal(lp, true);
    }

    function test_setManualWithdrawal_success() external {
        assertEq(withdrawalManager.isManualWithdrawal(lp), false);

        vm.expectEmit();
        emit ManualWithdrawalSet(lp, true);

        vm.prank(poolDelegate);
        withdrawalManager.setManualWithdrawal(lp, true);

        assertEq(withdrawalManager.isManualWithdrawal(lp), true);
    }

}
