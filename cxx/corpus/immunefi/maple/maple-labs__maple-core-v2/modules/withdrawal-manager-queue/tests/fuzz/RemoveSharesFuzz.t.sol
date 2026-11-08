// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { TestBase } from "../utils/TestBase.sol";

contract RemoveSharesFuzzTests is TestBase {

    function setUp() public override {
        super.setUp();
    }

    function testFuzz_removeShares(address[50] calldata account_, uint256[50] memory amount0_, uint256[50] memory amount1_) external {
        address owner_;

        uint128 lastRequestId;
        uint256 shares_;
        uint256 totalShares_;

        for (uint256 i; i < account_.length; ++i) {
            amount0_[i] = bound(amount0_[i], 1, 1e29);
            amount1_[i] = bound(amount1_[i], 1, 1e29);

            if (withdrawalManager.requestIds(account_[i]) > 0) break;

            pool.mint(pm, amount0_[i]);

            vm.startPrank(pm);
            pool.approve(address(withdrawalManager), amount0_[i]);

            withdrawalManager.addShares(amount0_[i], account_[i]);
            vm.stopPrank();

            totalShares_ += amount0_[i];

            ( , lastRequestId ) = withdrawalManager.queue();

            ( owner_, shares_ ) = withdrawalManager.requests(lastRequestId);

            assertEq(shares_,                              amount0_[i]);
            assertEq(withdrawalManager.totalShares(),      totalShares_);
            assertEq(lastRequestId,                        i + 1);
            assertEq(withdrawalManager.requestIds(owner_), lastRequestId);

            if (amount1_[i] > amount0_[i]) {
                vm.prank(pm);
                vm.expectRevert("WM:RS:INSUFFICIENT_SHARES");
                withdrawalManager.removeShares(amount1_[i], account_[i]);
                break;
            }

            vm.prank(pm);
            withdrawalManager.removeShares(amount1_[i], account_[i]);

            totalShares_ -= amount1_[i];

            ( , lastRequestId ) = withdrawalManager.queue();

            ( owner_, shares_ ) = withdrawalManager.requests(lastRequestId);

            assertEq(shares_,                         amount0_[i] - amount1_[i]);
            assertEq(withdrawalManager.totalShares(), totalShares_);
            assertEq(lastRequestId,                   i + 1);

            if (amount0_[i] == amount1_[i]) {
                assertEq(withdrawalManager.requestIds(owner_), 0);
            } else {
                assertEq(withdrawalManager.requestIds(owner_), lastRequestId);
            }
        }
    }

}
