// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { TestBase } from "../utils/TestBase.sol";

contract AddSharesFuzzTests is TestBase {

    function setUp() public override {
        super.setUp();
    }

    function testFuzz_addShares(uint256[50] memory amount_, address[50] calldata account_) external {
        address owner_;

        uint128 lastRequestId;
        uint256 shares_;
        uint256 totalShares_;

        for (uint256 i; i < account_.length; ++i) {
            amount_[i] = bound(amount_[i], 1, 1e29);

            if (withdrawalManager.requestIds(account_[i]) > 0) {
                vm.prank(pm);
                vm.expectRevert("WM:AS:IN_QUEUE");
                withdrawalManager.addShares(amount_[i], account_[i]);
                break;
            }

            pool.mint(pm, amount_[i]);

            vm.startPrank(pm);
            pool.approve(address(withdrawalManager), amount_[i]);

            withdrawalManager.addShares(amount_[i], account_[i]);
            vm.stopPrank();

            totalShares_ += amount_[i];

            ( , lastRequestId ) = withdrawalManager.queue();

            assertEq(lastRequestId, i + 1);

            ( owner_, shares_ ) = withdrawalManager.requests(lastRequestId);

            assertEq(shares_,                              amount_[i]);
            assertEq(withdrawalManager.totalShares(),      totalShares_);
            assertEq(withdrawalManager.requestIds(owner_), lastRequestId);
        }
    }

}
