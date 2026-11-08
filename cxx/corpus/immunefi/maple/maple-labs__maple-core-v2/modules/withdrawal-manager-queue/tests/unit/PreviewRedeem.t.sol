// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { TestBase } from "../utils/TestBase.sol";

contract PreviewRedeemTests is TestBase {

    uint256 assetsDeposited = 100e18;
    uint256 sharesToRedeem  = 250e18;

    function setUp() public override {
        super.setUp();

        asset.mint(address(pool), assetsDeposited);
        pool.mint(wm, sharesToRedeem);

        poolManager.__setTotalAssets(assetsDeposited);
    }

    function test_previewRedeem_tooManyShares() external {
        withdrawalManager.__setManualSharesAvailable(lp, sharesToRedeem);

        vm.expectRevert("WM:PR:TOO_MANY_SHARES");
        withdrawalManager.previewRedeem(lp, sharesToRedeem + 1);
    }

    function test_previewRedeem_notProcessed() external {
        withdrawalManager.__setManualSharesAvailable(lp, 0);

        ( uint256 redeemableShares_, uint256 resultingAssets_ ) = withdrawalManager.previewRedeem(lp, sharesToRedeem);

        assertEq(redeemableShares_, 0);
        assertEq(resultingAssets_,  0);
    }

    function test_previewRedeem_complete() external {
        withdrawalManager.__setManualSharesAvailable(lp, sharesToRedeem);

        ( uint256 redeemableShares_, uint256 resultingAssets_ ) = withdrawalManager.previewRedeem(lp, sharesToRedeem);

        assertEq(redeemableShares_, sharesToRedeem);
        assertEq(resultingAssets_,  assetsDeposited);
    }

    function test_previewRedeem_partial() external {
        withdrawalManager.__setManualSharesAvailable(lp, sharesToRedeem);

        // Only half of the liquidity is available.
        asset.burn(address(pool), assetsDeposited / 2);

        ( uint256 redeemableShares_, uint256 resultingAssets_ ) = withdrawalManager.previewRedeem(lp, sharesToRedeem);

        assertEq(redeemableShares_, sharesToRedeem / 2);
        assertEq(resultingAssets_,  assetsDeposited / 2);
    }

}
