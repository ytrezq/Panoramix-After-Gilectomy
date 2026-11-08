// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { IAccessControl } from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IERC20Like, IERC4626Like, TestBase } from "./Base.t.sol";

import { ISavingsVaultIntents } from "../src/interfaces/ISavingsVaultIntents.sol";
import { SavingsVaultIntents }  from "../src/SavingsVaultIntents.sol";

contract ConstructorTests is TestBase {

    // Failure tests

    function test_constructor_invalidAdmin() external {
        vm.expectRevert(ISavingsVaultIntents.InvalidAdminAddress.selector);
        new SavingsVaultIntents(address(0), relayer, 1 days);
    }

    function test_constructor_invalidRelayer() external {
        vm.expectRevert(ISavingsVaultIntents.InvalidRelayerAddress.selector);
        new SavingsVaultIntents(admin, address(0), 1 days);
    }

    function test_constructor_invalidMaxDeadlineDuration() external {
        vm.expectRevert(ISavingsVaultIntents.InvalidMaxDeadlineDuration.selector);
        new SavingsVaultIntents(admin, relayer, 0);
    }

    // Success tests

    function test_constructor() external {
        address admin_   = makeAddr("admin");
        address relayer_ = makeAddr("relayer");

        SavingsVaultIntents intentInstance = new SavingsVaultIntents({
            admin                : admin_,
            relayer              : relayer_,
            maxDeadlineDuration_ : 1 days
        });

        assertEq(intentInstance.hasRole(intentInstance.DEFAULT_ADMIN_ROLE(), admin_),   true);
        assertEq(intentInstance.hasRole(intentInstance.RELAYER(),            relayer_), true);
        
        assertEq(intentInstance.getRoleMemberCount(intentInstance.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(intentInstance.getRoleMemberCount(intentInstance.RELAYER()),            1);

        assertEq(intentInstance.maxDeadlineDuration(), 1 days);
    }

}

contract SetMaxDeadlineDurationTests is TestBase {

    // Failure tests

    function test_setMaxDeadlineDuration_noAuth() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                savingsVaultIntents.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(unauthorized);
        savingsVaultIntents.setMaxDeadlineDuration(2 days);
    }

    function test_setMaxDeadlineDuration_invalidMaxDeadline() external {
        vm.expectRevert(ISavingsVaultIntents.InvalidMaxDeadlineDuration.selector);
        vm.prank(admin);
        savingsVaultIntents.setMaxDeadlineDuration(0);
    }

    // Success tests

    function test_setMaxDeadlineDuration() external {
        assertEq(savingsVaultIntents.maxDeadlineDuration(), 1 days);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.MaxDeadlineDurationUpdated(2 days);

        vm.prank(admin);
        savingsVaultIntents.setMaxDeadlineDuration(2 days);

        assertEq(savingsVaultIntents.maxDeadlineDuration(), 2 days);
    }

}

contract UpdateVaultConfigTests is TestBase {

    // Failure tests

    function test_updateVaultConfig_noAuth() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                savingsVaultIntents.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(unauthorized);
        savingsVaultIntents.updateVaultConfig(
            makeAddr("vault"),
            true,
            MIN_INTENT_ASSETS_USDC,
            MAX_INTENT_ASSETS_USDC
        );
    }

    function test_updateVaultConfig_invalidVaultAddress() external {
        vm.expectRevert(ISavingsVaultIntents.InvalidVaultAddress.selector);
        vm.prank(admin);
        savingsVaultIntents.updateVaultConfig(
            address(0),
            true,
            MIN_INTENT_ASSETS_USDC,
            MAX_INTENT_ASSETS_USDC
        );
    }

    function test_updateVaultConfig_invalidIntentAmountBoundsBoundary() external {
        // Should fail when minintentAssets > maxIntentAssets
        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.InvalidIntentAmountBounds.selector,
                3,
                2
            )
        );

        vm.prank(admin);
        savingsVaultIntents.updateVaultConfig(
            address(sparkVaultUSDC),
            true,
            3,
            2
        );

        // Should fail when minintentAssets == maxIntentAssets
        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.InvalidIntentAmountBounds.selector,
                2,
                2
            )
        );

        vm.prank(admin);
        savingsVaultIntents.updateVaultConfig(
            address(sparkVaultUSDC),
            true,
            2,
            2
        );

        // Should pass when minintentAssets < maxIntentAssets
        vm.prank(admin);
        savingsVaultIntents.updateVaultConfig(
            address(sparkVaultUSDC),
            true,
            1,
            2
        );
    }

    // Success tests

    function test_updateVaultConfig() external {
        (
            bool    whitelisted,
            uint256 minIntentAssets,
            uint256 maxIntentAssets
        ) = savingsVaultIntents.vaultConfig(address(sparkVaultUSDC));

        assertEq(whitelisted,     true);
        assertEq(minIntentAssets, MIN_INTENT_ASSETS_USDC);
        assertEq(maxIntentAssets, MAX_INTENT_ASSETS_USDC);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.VaultConfigUpdated(
            address(sparkVaultUSDC),
            false,
            0,
            1
        );

        vm.prank(admin);
        savingsVaultIntents.updateVaultConfig(
            address(sparkVaultUSDC),
            false,
            0,
            1
        );

        (
            whitelisted,
            minIntentAssets,
            maxIntentAssets
        ) = savingsVaultIntents.vaultConfig(address(sparkVaultUSDC));

        assertEq(whitelisted,     false);
        assertEq(minIntentAssets, 0);
        assertEq(maxIntentAssets, 1);
    }

    function test_updateVaultConfig_newVault() external {
        (
            bool    whitelisted,
            uint256 minIntentAssets,
            uint256 maxIntentAssets
        ) = savingsVaultIntents.vaultConfig(makeAddr("newVault"));

        assertEq(whitelisted,     false);
        assertEq(minIntentAssets, 0);
        assertEq(maxIntentAssets, 0);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.VaultConfigUpdated(
            makeAddr("newVault"),
            true,
            100_000e18,
            100_000_000e18
        );

        vm.prank(admin);
        savingsVaultIntents.updateVaultConfig(
            makeAddr("newVault"),
            true,
            100_000e18,
            100_000_000e18
        );

        (
            whitelisted,
            minIntentAssets,
            maxIntentAssets
        ) = savingsVaultIntents.vaultConfig(makeAddr("newVault"));

        assertEq(whitelisted,     true);
        assertEq(minIntentAssets, 100_000e18);
        assertEq(maxIntentAssets, 100_000_000e18);
    }

}

contract RequestTests is TestBase {

    // Failure tests

    function test_request_vaultNotWhitelisted() external {
        vm.expectRevert(ISavingsVaultIntents.VaultNotWhitelisted.selector);
        vm.prank(user);
        savingsVaultIntents.request({
            vault     : makeAddr("newVault"),
            shares    : 1e18,
            recipient : user,
            deadline  : block.timestamp + 100
        });
    }

    function test_request_invalidRecipientAddress() external {
        vm.expectRevert(ISavingsVaultIntents.InvalidRecipientAddress.selector);
        vm.prank(user);
        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : address(0),
            deadline  : block.timestamp + 100
        });
    }

    function test_request_intentAssetsBelowMinBoundary() external {
        uint256 sharesAtMin    = sparkVaultUSDC.convertToShares(MIN_INTENT_ASSETS_USDC) + 1; // Rounding
        uint256 sharesBelowMin = sharesAtMin - 1;
        uint256 assetsBelowMin = sparkVaultUSDC.convertToAssets(sharesBelowMin);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.IntentAssetsBelowMin.selector,
                MIN_INTENT_ASSETS_USDC,
                assetsBelowMin
            )
        );

        vm.prank(user);
        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : sharesBelowMin,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        vm.prank(user);
        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : sharesAtMin,
            recipient : user,
            deadline  : block.timestamp + 100
        });
    }

    function test_request_intentAssetsAboveMaxBoundary() external {
        uint256 sharesAtMax    = sparkVaultUSDC.convertToShares(MAX_INTENT_ASSETS_USDC) + 1; // Rounding
        uint256 sharesAboveMax = sharesAtMax + 1;
        uint256 assetsAboveMax = sparkVaultUSDC.convertToAssets(sharesAboveMax);

        _depositToVault(user, sparkVaultUSDC, MAX_INTENT_ASSETS_USDC + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.IntentAssetsAboveMax.selector,
                MAX_INTENT_ASSETS_USDC,
                assetsAboveMax
            )
        );

        vm.prank(user);
        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : sharesAboveMax,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        vm.startPrank(user);
        sparkVaultUSDC.approve(address(savingsVaultIntents), sharesAtMax);

        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : sharesAtMax,
            recipient : user,
            deadline  : block.timestamp + 100
        });
        vm.stopPrank();
    }

    function test_request_invalidDeadlineBoundary_deadlineTooLow() external {
        uint256 maxDeadlineDuration = savingsVaultIntents.maxDeadlineDuration();

        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.InvalidDeadline.selector,
                block.timestamp + maxDeadlineDuration,
                block.timestamp
            )
        );

        vm.prank(user);
        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : block.timestamp
        });

        vm.prank(user);
        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : block.timestamp + 1
        });
    }

    function test_request_invalidDeadlineBoundary_deadlineTooHigh() external {
        uint256 maxDeadlineDuration = savingsVaultIntents.maxDeadlineDuration();

        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.InvalidDeadline.selector,
                block.timestamp + maxDeadlineDuration,
                block.timestamp + maxDeadlineDuration + 1
            )
        );

        vm.prank(user);
        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : block.timestamp + maxDeadlineDuration + 1
        });

        vm.prank(user);
        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : block.timestamp + maxDeadlineDuration
        });
    }

    function test_request_insufficientSharesBoundary() external {
        uint256 sharesAtBoundary   = userSpUSDCShares;
        uint256 sharesOverBoundary = userSpUSDCShares + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.InsufficientShares.selector,
                sharesOverBoundary,
                userSpUSDCShares
            )
        );

        vm.prank(user);
        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : sharesOverBoundary,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        vm.prank(user);
        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : sharesAtBoundary,
            recipient : user,
            deadline  : block.timestamp + 100
        });
    }

    function test_request_insufficientAllowanceBoundary() external {
        uint256 sharesAtBoundary   = userSpUSDCShares;
        uint256 sharesOverBoundary = userSpUSDCShares + 1;

        // Request creation should revert if user is requesting more shares than allowance

        _depositToVault(user, sparkVaultUSDC, 2); // Add 2 (rounding) more assets for sharesOverBoundary 

        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.InsufficientAllowance.selector,
                sharesOverBoundary,
                userSpUSDCShares
            )
        );

        vm.prank(user);
        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : sharesOverBoundary,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        // Request creation should succeed if user is requesting shares equal to allowance

        vm.prank(user);
        savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : sharesAtBoundary,
            recipient : user,
            deadline  : block.timestamp + 100
        });
    }

    // Success tests

    function test_request() external {
        _assertEmptyRequest(user, sparkVaultUSDC);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 0);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestCreated({
            account   : user,
            vault     : address(sparkVaultUSDC),
            requestId : 1,
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
            vault             : sparkVaultUSDC,
            expectedRequestId : requestId,
            expectedShares    : userSpUSDCShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 100
        });
    }

    function test_request_multipleVaults() external {
        _assertEmptyRequest(user, sparkVaultUSDC);
        _assertEmptyRequest(user, sparkVaultETH);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 0);
        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultETH)),  0);

        // Create request for sparkVaultUSDC

        vm.prank(user);
        uint256 requestIdVaultUSDC = savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        // Create request for sparkVaultETH

        vm.prank(user);
        uint256 requestIdVaultETH = savingsVaultIntents.request({
            vault     : address(sparkVaultETH),
            shares    : userSpETHShares,
            recipient : user,
            deadline  : block.timestamp + 200
        });

        assertEq(requestIdVaultUSDC, 1);
        assertEq(requestIdVaultETH,  1);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 1);
        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultETH)),  1);

        _assertRequest({
            account           : user,
            vault             : sparkVaultUSDC,
            expectedRequestId : requestIdVaultUSDC,
            expectedShares    : userSpUSDCShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 100
        });

        _assertRequest({
            account           : user,
            vault             : sparkVaultETH,
            expectedRequestId : requestIdVaultETH,
            expectedShares    : userSpETHShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 200
        });
    }

    function test_request_overwriteRequest() external {
        _assertEmptyRequest(user, sparkVaultUSDC);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 0);

        vm.prank(user);
        uint256 requestIdA = savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        assertEq(requestIdA, 1);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 1);

        _assertRequest({
            account           : user,
            vault             : sparkVaultUSDC,
            expectedRequestId : requestIdA,
            expectedShares    : userSpUSDCShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 100
        });

        // Overwriting request A with userShares - 10

        vm.prank(user);
        uint256 requestIdB = savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares - 10,
            recipient : user,
            deadline  : block.timestamp + 200
        });

        assertEq(requestIdB, 2);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 2);

        _assertRequest({
            account           : user,
            vault             : sparkVaultUSDC,
            expectedRequestId : requestIdB,
            expectedShares    : userSpUSDCShares - 10,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 200
        });
    }

    function test_request_multipleVaults_overwriteIsolation() external {
        _assertEmptyRequest(user, sparkVaultUSDC);
        _assertEmptyRequest(user, sparkVaultETH);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 0);
        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultETH)),  0);

        // Create request for sparkVaultUSDC

        vm.prank(user);
        uint256 requestIdVaultUSDC = savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares,
            recipient : user,
            deadline  : block.timestamp + 100
        });

        // Create request for sparkVaultETH

        vm.prank(user);
        uint256 requestIdVaultETH = savingsVaultIntents.request({
            vault     : address(sparkVaultETH),
            shares    : userSpETHShares,
            recipient : user,
            deadline  : block.timestamp + 200
        });

        assertEq(requestIdVaultUSDC, 1);
        assertEq(requestIdVaultETH,  1);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 1);
        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultETH)),  1);

        _assertRequest({
            account           : user,
            vault             : sparkVaultUSDC,
            expectedRequestId : requestIdVaultUSDC,
            expectedShares    : userSpUSDCShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 100
        });

        _assertRequest({
            account           : user,
            vault             : sparkVaultETH,
            expectedRequestId : requestIdVaultETH,
            expectedShares    : userSpETHShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 200
        });

        // Overwriting requestIdVaultUSDC with userShares - 10

        vm.prank(user);
        requestIdVaultUSDC = savingsVaultIntents.request({
            vault     : address(sparkVaultUSDC),
            shares    : userSpUSDCShares - 10,
            recipient : user,
            deadline  : block.timestamp + 200
        });

        assertEq(requestIdVaultUSDC, 2);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 2);

        _assertRequest({
            account           : user,
            vault             : sparkVaultUSDC,
            expectedRequestId : requestIdVaultUSDC,
            expectedShares    : userSpUSDCShares - 10,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 200
        });

        // Request of sparkVaultETH will remain same.

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultETH)), 1);

        _assertRequest({
            account           : user,
            vault             : sparkVaultETH,
            expectedRequestId : requestIdVaultETH,
            expectedShares    : userSpETHShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 200
        });
    }

}

contract CancelTests is TestBase {

    // Failure tests

    function test_cancel_requestNotFound() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.RequestNotFound.selector,
                user,
                address(sparkVaultUSDC)
            )
        );

        vm.prank(user);
        savingsVaultIntents.cancel(address(sparkVaultUSDC));

        uint256 requestId = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            block.timestamp + 100
        );

        assertEq(requestId, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.RequestNotFound.selector,
                user,
                address(sparkVaultETH)
            )
        );

        vm.prank(user);
        savingsVaultIntents.cancel(address(sparkVaultETH));
    }

    // Success tests

    function test_cancel() external {
        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 0);

        uint256 requestId = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            block.timestamp + 100
        );

        assertEq(requestId, 1);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 1);

        _assertRequest({
            account           : user,
            vault             : sparkVaultUSDC,
            expectedRequestId : requestId,
            expectedShares    : userSpUSDCShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 100
        });

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestCancelled(user, address(sparkVaultUSDC), requestId);

        vm.prank(user);
        uint256 cancelledRequestId = savingsVaultIntents.cancel(address(sparkVaultUSDC));

        assertEq(requestId, cancelledRequestId);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 1);

        _assertEmptyRequest(user, sparkVaultUSDC);
    }

    function test_cancel_afterRequestOverwrite() external {
        uint256 requestId = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            block.timestamp + 100
        );

        assertEq(requestId, 1);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 1);

        _assertRequest({
            account           : user,
            vault             : sparkVaultUSDC,
            expectedRequestId : requestId,
            expectedShares    : userSpUSDCShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 100
        });

        // Overwriting request 1
        requestId = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares / 2,
            block.timestamp + 200
        );
    
        assertEq(requestId, 2);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 2);

        _assertRequest({
            account           : user,
            vault             : sparkVaultUSDC,
            expectedRequestId : requestId,
            expectedShares    : userSpUSDCShares / 2,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 200
        });
        
        // Cancel event will have overwritten requestId and requestCount doesn't change

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestCancelled(user, address(sparkVaultUSDC), requestId);

        vm.prank(user);
        uint256 cancelledRequestId = savingsVaultIntents.cancel(address(sparkVaultUSDC));

        assertEq(requestId, cancelledRequestId);

        assertEq(savingsVaultIntents.vaultRequestCount(address(sparkVaultUSDC)), 2);

        _assertEmptyRequest(user, sparkVaultUSDC);
    }

    function test_cancel_multipleVaults_onlyAffectsTargetVault() external {
        uint256 requestIdVaultUSDC = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            block.timestamp + 100
        );

        uint256 requestIdVaultETH = _createRequest(
            user,
            sparkVaultETH,
            userSpETHShares,
            block.timestamp + 200
        );

        assertEq(requestIdVaultUSDC, 1);
        assertEq(requestIdVaultETH,  1);

        _assertRequest({
            account           : user,
            vault             : sparkVaultUSDC,
            expectedRequestId : requestIdVaultUSDC,
            expectedShares    : userSpUSDCShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 100
        });

        _assertRequest({
            account           : user,
            vault             : sparkVaultETH,
            expectedRequestId : requestIdVaultETH,
            expectedShares    : userSpETHShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 200
        });

        // Cancelling sparkVaultUSDC request, Cancel event should have requestIdVaultUSDC
    
        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestCancelled(
            user,
            address(sparkVaultUSDC),
            requestIdVaultUSDC
        );

        vm.prank(user);
        uint256 cancelledRequestId = savingsVaultIntents.cancel(address(sparkVaultUSDC));

        assertEq(requestIdVaultUSDC, cancelledRequestId);

        _assertEmptyRequest(user, sparkVaultUSDC);

        // Request sparkVaultETH will not be affected

        _assertRequest({
            account           : user,
            vault             : sparkVaultETH,
            expectedRequestId : requestIdVaultETH,
            expectedShares    : userSpETHShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 200
        });
    }

}

contract FulfillTests is TestBase {

    // Failure tests

    function test_fulfill_noAuth() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                savingsVaultIntents.RELAYER()
            )
        );

        vm.prank(unauthorized);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), 1);
    }

    function test_fulfill_requestNotFound_zeroRequestId() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.RequestNotFound.selector,
                user,
                address(sparkVaultUSDC)
            )
        );
        
        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), 0);
    }

    function test_fulfill_requestNotFound_noRequest() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.RequestNotFound.selector,
                user,
                address(sparkVaultUSDC)
            )
        );
        
        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.RequestNotFound.selector,
                user,
                address(sparkVaultETH)
            )
        );
        
        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultETH), 1);
    }

    function test_fulfill_requestNotFound_wrongVault() external {
        // User created request for sparkVaultUSDC
        uint256 requestId = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            block.timestamp + 100
        );

        // Fulfill of sparkVaultETH request should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.RequestNotFound.selector,
                user,
                address(sparkVaultETH)
            )
        );
        
        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultETH), requestId);
    }

    function test_fulfill_requestNotFoundRaceCondition() external {
        // User creates request A
        uint256 requestA = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            block.timestamp + 100
        );

        assertEq(requestA, 1);

        // User cancels request A
        vm.prank(user);
        savingsVaultIntents.cancel(address(sparkVaultUSDC));

        // User creates request B with half of his shares.
        uint256 requestB = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares / 2,
            block.timestamp + 100
        );

        assertEq(requestB, 2);

        // Relayer captured the request A and trying to fulfill
        vm.expectRevert(
            abi.encodeWithSelector(
                ISavingsVaultIntents.RequestNotFound.selector,
                user,
                address(sparkVaultUSDC)
            )
        );
        
        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestA);

        // Relayer fulfilling request B should succeed

        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestB);
    }

    function test_fulfill_deadlineExceededBoundary() external {
        uint256 deadline = block.timestamp + 10;

        uint256 requestId = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            deadline
        );

        assertEq(requestId, 1);

        vm.warp(deadline + 1);

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

        vm.warp(deadline);

        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);
    }

    function test_fulfill_sharesAllowanceBoundary() external {
        // User creates an intent request
        uint256 requestId = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            block.timestamp + 100
        );

        assertEq(requestId, 1);

        // User reducing the allowance by 1 before fulfill should cause fulfill to revert

        vm.prank(user);
        sparkVaultUSDC.approve(address(savingsVaultIntents), userSpUSDCShares - 1);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), userSpUSDCShares - 1);

        vm.expectRevert("SparkVault/insufficient-allowance");
        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);

        // Fulfill succeeds when the allowance to savingsVaultIntents is exactly the required amount

        vm.prank(user);
        sparkVaultUSDC.approve(address(savingsVaultIntents), userSpUSDCShares);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), userSpUSDCShares);

        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), 0);

        _assertEmptyRequest(user, sparkVaultUSDC);
    }


    function test_fulfill_insufficientUserFundsBoundary() external {
        assertEq(sparkVaultUSDC.balanceOf(user), userSpUSDCShares);
        
        uint256 requestId = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            block.timestamp + 100
        );

        assertEq(requestId, 1);

        // Fulfill fails as user redeems 1 share from the requested userSpUSDCShares

        vm.prank(user);
        uint256 redeemedAssets = sparkVaultUSDC.redeem(1, user, user);

        assertEq(sparkVaultUSDC.balanceOf(user), userSpUSDCShares - 1);

        vm.expectRevert("SparkVault/insufficient-balance");
        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);

        // Fulfill succeeds when user deposits 1 share (redeemedAssets + 1) back to vault

        _depositToVault(user, sparkVaultUSDC, redeemedAssets + 1); // Rounding

        assertEq(sparkVaultUSDC.balanceOf(user), userSpUSDCShares);

        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);

        _assertEmptyRequest(user, sparkVaultUSDC);
    }

    function test_fulfill_insufficientVaultFundsBoundary() external {
        // Drain all the sparkVaultUSDC liquidity

        deal(sparkVaultUSDC.asset(), address(sparkVaultUSDC), 0);

        uint256 assetsAtBoundary    = sparkVaultUSDC.convertToAssets(userSpUSDCShares); // 999_999_999999
        uint256 assetsUnderBoundary = sparkVaultUSDC.convertToAssets(userSpUSDCShares) - 1; // 999_999_999998

        uint256 requestId = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            block.timestamp + 100
        );
        
        // Vault have zero assets to redeem userShares, request fulfill fails
        vm.expectRevert("SparkVault/insufficient-liquidity");
        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);

        deal(sparkVaultUSDC.asset(), address(sparkVaultUSDC), assetsUnderBoundary);
        
        // Vault have one less than the assets required to redeem userShares, request fulfill fails
        vm.expectRevert("SparkVault/insufficient-liquidity");
        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);

        // Vault have exact amount of assets required to redeem, request fulfilled
        deal(sparkVaultUSDC.asset(), address(sparkVaultUSDC), assetsAtBoundary);

        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);

        _assertEmptyRequest(user, sparkVaultUSDC);
    }

    // Success tests

    function test_fulfill() external {
        IERC20Like underlyingAsset = IERC20Like(sparkVaultUSDC.asset());

        // Deal exact user deposited amount
        deal(sparkVaultUSDC.asset(), address(sparkVaultUSDC), DEPOSIT_AMOUNT_USDC);

        uint256 requestId = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            block.timestamp + 100
        );

        assertEq(requestId, 1);

        // Fulfill the request.

        assertEq(underlyingAsset.balanceOf(address(sparkVaultUSDC)), DEPOSIT_AMOUNT_USDC);
        assertEq(underlyingAsset.balanceOf(user),                    0);

        assertEq(sparkVaultUSDC.balanceOf(user), userSpUSDCShares);
        assertEq(sparkVaultUSDC.totalSupply(),   sparkVaultUSDCInitSupply);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), userSpUSDCShares);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestFulfilled(user, address(sparkVaultUSDC), requestId);

        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestId);

        assertEq(underlyingAsset.balanceOf(address(sparkVaultUSDC)), 1);
        assertEq(underlyingAsset.balanceOf(user),                    DEPOSIT_AMOUNT_USDC - 1); // Rounding

        assertEq(sparkVaultUSDC.balanceOf(user), 0);
        assertEq(sparkVaultUSDC.totalSupply(),   sparkVaultUSDCInitSupply - userSpUSDCShares);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), 0);

        _assertEmptyRequest(user, sparkVaultUSDC);
    }

    function test_fulfill_multipleVaults() external {
        IERC20Like underlyingAssetUSDC = IERC20Like(sparkVaultUSDC.asset());
        IERC20Like underlyingAssetETH  = IERC20Like(sparkVaultETH.asset());

        // Deal exact user deposited amount to both vaults

        deal(sparkVaultUSDC.asset(), address(sparkVaultUSDC), DEPOSIT_AMOUNT_USDC);
        deal(sparkVaultETH.asset(),  address(sparkVaultETH),  DEPOSIT_AMOUNT_ETH);

        // User creates sparkVaultUSDC and sparkVaultETH requests

        uint256 requestIdVaultUSDC = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            block.timestamp + 100
        );

        uint256 requestIdVaultETH = _createRequest(
            user,
            sparkVaultETH,
            userSpETHShares,
            block.timestamp + 200
        );

        assertEq(requestIdVaultUSDC, 1);
        assertEq(requestIdVaultETH,  1);

        // Fulfill both sparkVaultUSDC and sparkVaultETH requests.

        assertEq(underlyingAssetUSDC.balanceOf(address(sparkVaultUSDC)), DEPOSIT_AMOUNT_USDC);
        assertEq(underlyingAssetETH.balanceOf(address(sparkVaultETH)),   DEPOSIT_AMOUNT_ETH);
        assertEq(underlyingAssetUSDC.balanceOf(user),                    0);
        assertEq(underlyingAssetETH.balanceOf(user),                     0);

        assertEq(sparkVaultUSDC.balanceOf(user), userSpUSDCShares);
        assertEq(sparkVaultETH.balanceOf(user),  userSpETHShares);
        assertEq(sparkVaultUSDC.totalSupply(),   sparkVaultUSDCInitSupply);
        assertEq(sparkVaultETH.totalSupply(),    sparkVaultETHInitSupply);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), userSpUSDCShares);
        assertEq(sparkVaultETH.allowance(user,  address(savingsVaultIntents)), userSpETHShares);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestFulfilled(
            user,
            address(sparkVaultUSDC),
            requestIdVaultUSDC
        );

        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestIdVaultUSDC);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestFulfilled(
            user,
            address(sparkVaultETH),
            requestIdVaultETH
        );

        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultETH), requestIdVaultETH);

        assertEq(underlyingAssetUSDC.balanceOf(address(sparkVaultUSDC)), 1);
        assertEq(underlyingAssetETH.balanceOf(address(sparkVaultETH)),   1);
        assertEq(underlyingAssetUSDC.balanceOf(user),                    DEPOSIT_AMOUNT_USDC - 1); // Rounding
        assertEq(underlyingAssetETH.balanceOf(user),                     DEPOSIT_AMOUNT_ETH - 1);  // Rounding

        assertEq(sparkVaultUSDC.balanceOf(user), 0);
        assertEq(sparkVaultETH.balanceOf(user),  0);
        assertEq(sparkVaultUSDC.totalSupply(),   sparkVaultUSDCInitSupply - userSpUSDCShares);
        assertEq(sparkVaultETH.totalSupply(),    sparkVaultETHInitSupply - userSpETHShares);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), 0);
        assertEq(sparkVaultETH.allowance(user,  address(savingsVaultIntents)), 0);

        _assertEmptyRequest(user, sparkVaultUSDC);
        _assertEmptyRequest(user, sparkVaultETH);
    }

    function test_fulfill_multipleVaults_onlyAffectsTargetVault() external {
        IERC20Like underlyingAssetUSDC = IERC20Like(sparkVaultUSDC.asset());
        IERC20Like underlyingAssetETH  = IERC20Like(sparkVaultETH.asset());

        // Deal exact user deposited amount to both vaults

        deal(sparkVaultUSDC.asset(), address(sparkVaultUSDC), DEPOSIT_AMOUNT_USDC);
        deal(sparkVaultETH.asset(),  address(sparkVaultETH),  DEPOSIT_AMOUNT_ETH);

        // User creates sparkVaultUSDC and sparkVaultETH requests

        uint256 requestIdVaultUSDC = _createRequest(
            user,
            sparkVaultUSDC,
            userSpUSDCShares,
            block.timestamp + 100
        );

        uint256 requestIdVaultETH = _createRequest(
            user,
            sparkVaultETH,
            userSpETHShares,
            block.timestamp + 200
        );

        assertEq(requestIdVaultUSDC, 1);
        assertEq(requestIdVaultETH,  1);

        // Fulfill only the sparkVaultUSDC request.

        assertEq(underlyingAssetUSDC.balanceOf(address(sparkVaultUSDC)), DEPOSIT_AMOUNT_USDC);
        assertEq(underlyingAssetETH.balanceOf(address(sparkVaultETH)),   DEPOSIT_AMOUNT_ETH);
        assertEq(underlyingAssetUSDC.balanceOf(user),                    0);
        assertEq(underlyingAssetETH.balanceOf(user),                     0);

        assertEq(sparkVaultUSDC.balanceOf(user), userSpUSDCShares);
        assertEq(sparkVaultETH.balanceOf(user),  userSpETHShares);
        assertEq(sparkVaultUSDC.totalSupply(),   sparkVaultUSDCInitSupply);
        assertEq(sparkVaultETH.totalSupply(),    sparkVaultETHInitSupply);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), userSpUSDCShares);
        assertEq(sparkVaultETH.allowance(user,  address(savingsVaultIntents)), userSpETHShares);

        vm.expectEmit(address(savingsVaultIntents));
        emit ISavingsVaultIntents.RequestFulfilled(
            user,
            address(sparkVaultUSDC),
            requestIdVaultUSDC
        );

        vm.prank(relayer);
        savingsVaultIntents.fulfill(user, address(sparkVaultUSDC), requestIdVaultUSDC);

        assertEq(underlyingAssetUSDC.balanceOf(address(sparkVaultUSDC)), 1);
        assertEq(underlyingAssetUSDC.balanceOf(user),                    DEPOSIT_AMOUNT_USDC - 1); // Rounding

        assertEq(sparkVaultUSDC.balanceOf(user), 0);
        assertEq(sparkVaultUSDC.totalSupply(),   sparkVaultUSDCInitSupply - userSpUSDCShares);

        assertEq(sparkVaultUSDC.allowance(user, address(savingsVaultIntents)), 0);

        _assertEmptyRequest(user, sparkVaultUSDC);

        // Request sparkVaultETH is not fulfilled

        assertEq(underlyingAssetETH.balanceOf(address(sparkVaultETH)), DEPOSIT_AMOUNT_ETH);
        assertEq(underlyingAssetETH.balanceOf(user),                   0);

        assertEq(sparkVaultETH.balanceOf(user), userSpETHShares);
        assertEq(sparkVaultETH.totalSupply(),   sparkVaultETHInitSupply);

        assertEq(sparkVaultETH.allowance(user, address(savingsVaultIntents)), userSpETHShares);

        _assertRequest({
            account           : user,
            vault             : sparkVaultETH,
            expectedRequestId : requestIdVaultETH,
            expectedShares    : userSpETHShares,
            expectedRecipient : user,
            expectedDeadline  : block.timestamp + 200
        });
    }

}
