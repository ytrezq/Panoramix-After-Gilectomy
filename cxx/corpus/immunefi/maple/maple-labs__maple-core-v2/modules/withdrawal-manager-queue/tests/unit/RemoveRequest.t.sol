// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { TestBase } from "../utils/TestBase.sol";

contract RemoveRequestTests is TestBase {

    event RequestRemoved(uint128 indexed requestId);

    function setUp() public override {
        super.setUp();

        pool.mint(pm, 2);

        vm.prank(pm);
        pool.approve(address(withdrawalManager), 2);
    }

    function test_removeRequest_protocolPaused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("WM:PAUSED");
        withdrawalManager.removeRequest(lp);
    }

    function test_removeRequest_notProtocolAdmin() external {
        vm.expectRevert("WM:NOT_PD_OR_GOV_OR_OA");
        withdrawalManager.removeRequest(lp);
    }

    function test_removeRequest_notInQueue() external {
        vm.prank(poolDelegate);
        vm.expectRevert("WM:RR:NOT_IN_QUEUE");
        withdrawalManager.removeRequest(lp);
    }

    function test_removeRequest_failedTransfer() external {
        vm.prank(pm);
        withdrawalManager.addShares(1, lp);

        pool.burn(address(withdrawalManager), 1);

        vm.prank(poolDelegate);
        vm.expectRevert("WM:RR:TRANSFER_FAIL");
        withdrawalManager.removeRequest(lp);
    }

    function test_removeRequest_success() external {
        vm.prank(pm);
        withdrawalManager.addShares(2, lp);

        ( , uint128 lastRequestId ) = withdrawalManager.queue();

        ( address owner_, uint256 shares_ ) = withdrawalManager.requests(lastRequestId);

        assertEq(shares_,                              2);
        assertEq(withdrawalManager.totalShares(),      2);
        assertEq(lastRequestId,                        1);
        assertEq(withdrawalManager.requestIds(owner_), lastRequestId);

        vm.expectEmit();
        emit RequestRemoved(1);

        vm.prank(poolDelegate);
        withdrawalManager.removeRequest(lp);

        ( , lastRequestId ) = withdrawalManager.queue();

        ( owner_, shares_ ) = withdrawalManager.requests(lastRequestId);

        assertEq(lastRequestId,                        1);
        assertEq(shares_,                              0);
        assertEq(owner_,                               address(0));
        assertEq(withdrawalManager.requestIds(owner_), 0);
        assertEq(withdrawalManager.requestIds(lp),     0);
        assertEq(withdrawalManager.totalShares(),      0);
    }

}
