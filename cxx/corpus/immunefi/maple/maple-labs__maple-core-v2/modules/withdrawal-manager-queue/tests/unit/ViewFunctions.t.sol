// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { TestBase } from "../utils/TestBase.sol";

contract ViewFunctionsTests is TestBase {

    function testFuzz_isInExitWindow(address account_) external {
        assertTrue(withdrawalManager.isInExitWindow(account_));
    }

    function test_lockedLiquidity() external {
        assertEq(withdrawalManager.lockedLiquidity(), 0);
    }

    function test_lockedShares(address account_, uint256 shares_) external {
        withdrawalManager.__setManualSharesAvailable(account_, shares_);
        assertEq(withdrawalManager.lockedShares(account_), shares_);
    }

    function test_previewWithdraw(address account_, uint256 shares_) external {
        ( uint256 redeemableAssets, uint256 redeemableShares ) = withdrawalManager.previewWithdraw(account_, shares_);
        assertEq(redeemableAssets, 0);
        assertEq(redeemableShares, 0);
    }

}
