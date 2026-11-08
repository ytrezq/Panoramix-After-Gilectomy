// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Vm } from "../lib/forge-std/src/Test.sol";

import { Ethereum } from "../lib/spark-address-registry/src/Ethereum.sol";

import { TestBase } from "./Base.t.sol";

import { IERC20Like }   from "./interfaces/IERC20Like.sol";
import { IERC4626Like } from "./interfaces/IERC4626Like.sol";
import { IVaultLike }   from "./interfaces/IVaultLike.sol";

import { ISavingsVaultIntents } from "../src/interfaces/ISavingsVaultIntents.sol";
import { SavingsVaultIntents }  from "../src/SavingsVaultIntents.sol";

contract E2ETests is TestBase {

    function test_e2e_multipleRequestsOverriden() external {
        // Step 0: Setup.
        IERC20Like underlyingAsset = IERC20Like(sparkVaultUSDC.asset());

        // Deal exact user deposited amount
        deal(sparkVaultUSDC.asset(), address(sparkVaultUSDC), DEPOSIT_AMOUNT_USDC);

        // Step 1: User creates request for 1/3 shares.
        vm.prank(user);
        uint256 requestId = savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares / 3,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        assertEq(requestId, 1);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 1);

        _assertRequest({
            account           : user,
            expectedRequestId : requestId,
            vault             : sparkVaultUSDC,
            expectedShares    : userSpUSDCShares / 3,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 100
        });

        // Step 2: User creates another request for 2/3 shares and the previous request get overriden.
        uint256 withdrawShares = 2 * userSpUSDCShares / 3;

        vm.prank(user);
        sparkVaultUSDC.approve(address(savingsVaultIntents), withdrawShares);

        vm.prank(user);
        requestId = savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : withdrawShares,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        assertEq(requestId, 2);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 2);

        _assertRequest({
            account           : user,
            expectedRequestId : requestId,
            vault             : sparkVaultUSDC,
            expectedShares    : withdrawShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 100
        });

        // Step 3: Relayer fulfills the last made request for the user.
        assertEq(underlyingAsset.balanceOf(address(sparkVaultUSDC)), DEPOSIT_AMOUNT_USDC);
        assertEq(underlyingAsset.balanceOf(user),                    0);
        assertEq(sparkVaultUSDC.balanceOf(user),                     userSpUSDCShares);
        assertEq(sparkVaultUSDC.totalSupply(),                       sparkVaultUSDCInitSupply);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), withdrawShares);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestFulfilled(user, address(sparkVaultUSDC), requestId);

        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);

        assertEq(underlyingAsset.balanceOf(address(sparkVaultUSDC)), DEPOSIT_AMOUNT_USDC / 3 + 2);  // Rounding
        assertEq(underlyingAsset.balanceOf(user),                    2 * DEPOSIT_AMOUNT_USDC / 3 - 1);  // Rounding
        assertEq(sparkVaultUSDC.balanceOf(user),                     userSpUSDCShares / 3 + 1);  // Rounding
        assertEq(sparkVaultUSDC.totalSupply(),                       sparkVaultUSDCInitSupply - withdrawShares);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), 0);

        _assertEmptyRequest(user, sparkVaultUSDC);
    }

    function test_e2e_fulfillAfterTimePassesButBeforeDeadline() external {
        // Step 0: Setup.
        IERC20Like underlyingAsset = IERC20Like(sparkVaultUSDC.asset());

        // Deal exact user deposited amount
        deal(sparkVaultUSDC.asset(), address(sparkVaultUSDC), DEPOSIT_AMOUNT_USDC);

        // Step 1: User creates request
        _assertEmptyRequest(user, sparkVaultUSDC);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 0);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestCreated({
            account   : user,
            requestId : 1,
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        vm.prank(user);
        uint256 requestId = savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        assertEq(requestId, 1);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 1);

        _assertRequest({
            account           : user,
            expectedRequestId : requestId,
            vault             : sparkVaultUSDC,
            expectedShares    : userSpUSDCShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 100
        });

        // Step 2: Warp 99s
        vm.warp(block.timestamp + 99);

        deal(sparkVaultUSDC.asset(), address(sparkVaultUSDC), DEPOSIT_AMOUNT_USDC + 1_000e6);  // Deal interest earned by the vault.

        // Step 3: Relayer fulfills the request.
        assertEq(underlyingAsset.balanceOf(address(sparkVaultUSDC)), DEPOSIT_AMOUNT_USDC + 1_000e6);
        assertEq(underlyingAsset.balanceOf(user),                    0);
        assertEq(sparkVaultUSDC.balanceOf(user),                     userSpUSDCShares);
        assertEq(sparkVaultUSDC.totalSupply(),                       sparkVaultUSDCInitSupply);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), userSpUSDCShares);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestFulfilled(user, address(sparkVaultUSDC), requestId);

        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);

        assertEq(underlyingAsset.balanceOf(address(sparkVaultUSDC)), 999.876877e6);  // Remaining interest.
        assertEq(underlyingAsset.balanceOf(user),                    DEPOSIT_AMOUNT_USDC + 0.123123e6);  // Interest earned by the user.
        assertEq(sparkVaultUSDC.balanceOf(user),                     0);
        assertEq(sparkVaultUSDC.totalSupply(),                       sparkVaultUSDCInitSupply - userSpUSDCShares);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), 0);

        _assertEmptyRequest(user, sparkVaultUSDC);
    }

    function test_e2e_fulfillAfterDeadlineReverts() external {
        // Step 0: Setup.
        deal(sparkVaultUSDC.asset(), address(sparkVaultUSDC), DEPOSIT_AMOUNT_USDC);

        // Step 1: User creates request with 100s deadline
        _assertEmptyRequest(user, sparkVaultUSDC);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 0);

        uint256 deadline = block.timestamp + 100;

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestCreated({
            account   : user,
            requestId : 1,
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : deadline
        });

        vm.prank(user);
        uint256 requestId = savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : deadline
        });

        assertEq(requestId, 1);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 1);

        _assertRequest({
            account           : user,
            expectedRequestId : requestId,
            vault             : sparkVaultUSDC,
            expectedShares    : userSpUSDCShares,
            expectedRecipient : user,
            expectedDeadline  : deadline
        });

        // Step 2: Warp 101 seconds forward
        vm.warp(deadline + 1);

        // Step 3: Relayer tries to fulfill the request but it reverts because the deadline has passed.
        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.DeadlineExceeded.selector,
                user,
                address(sparkVaultUSDC),
                requestId,
                deadline
            )
        );
        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);

        // Step 4: User cancels the stale request to clean up
        vm.prank(user);
        savingsVaultIntents.cancel(address(sparkVaultUSDC));

        _assertEmptyRequest(user, sparkVaultUSDC);
    }

    function test_e2e_adminUpdatesParametersMidFlight() external {
        // Step 0: Setup.
        IERC20Like underlyingAsset = IERC20Like(sparkVaultUSDC.asset());

        deal(sparkVaultUSDC.asset(), address(sparkVaultUSDC), DEPOSIT_AMOUNT_USDC);

        // Step 1: User creates request
        _assertEmptyRequest(user, sparkVaultUSDC);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 0);

        // Approve the transfer.
        vm.prank(user);
        sparkVaultUSDC.approve(address(savingsVaultIntents), userSpUSDCShares);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestCreated({
            account   : user,
            requestId : 1,
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        vm.prank(user);
        uint256 requestId = savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        assertEq(requestId, 1);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 1);

        _assertRequest({
            account           : user,
            expectedRequestId : requestId,
            vault             : sparkVaultUSDC,
            expectedShares    : userSpUSDCShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 100
        });

        // Step 2: Admin updates maxDeadline and minIntentShares
        vm.prank(admin);
        savingsVaultIntents.setMaxDeadlineDuration(block.timestamp + 50);

        vm.prank(admin);
        savingsVaultIntents.updateVaultConfig(
            address(sparkVaultUSDC),
            false,
            MIN_INTENT_ASSETS_USDC - 1,
            MAX_INTENT_ASSETS_USDC + 1
        );

        // Step 3: Relayer still fulfills existing request (it was valid at creation)
        assertEq(underlyingAsset.balanceOf(address(sparkVaultUSDC)), DEPOSIT_AMOUNT_USDC);
        assertEq(underlyingAsset.balanceOf(user),                    0);
        assertEq(sparkVaultUSDC.balanceOf(user),                     userSpUSDCShares);
        assertEq(sparkVaultUSDC.totalSupply(),                       sparkVaultUSDCInitSupply);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), userSpUSDCShares);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestFulfilled(user, address(sparkVaultUSDC), requestId);

        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);

        assertEq(underlyingAsset.balanceOf(address(sparkVaultUSDC)), 1);
        assertEq(underlyingAsset.balanceOf(user),                    DEPOSIT_AMOUNT_USDC - 1); // Rounding
        assertEq(sparkVaultUSDC.balanceOf(user),                     0);
        assertEq(sparkVaultUSDC.totalSupply(),                       sparkVaultUSDCInitSupply - userSpUSDCShares);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), 0);

        _assertEmptyRequest(user, sparkVaultUSDC);
    }

}
