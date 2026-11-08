// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcreteBridgedAsyncVaultImplBaseSetup} from "../../common/ConcreteBridgedAsyncVaultImplBaseSetup.t.sol";
import {IConcreteBridgedAsyncVaultImpl} from "../../../src/interface/IConcreteBridgedAsyncVaultImpl.sol";
import {IAccessControl} from "@openzeppelin-contracts/access/IAccessControl.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../../src/lib/Roles.sol";

contract UnbackedMintUnitTest is ConcreteBridgedAsyncVaultImplBaseSetup {
    address public user1;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        vm.label(user1, "user1");
    }

    /// @notice Test successful unbacked mint
    function test_UnbackedMint_Success() public {
        uint256 sharesToMint = 1000000e18;

        // Verify initial state
        assertEq(concreteBridgedAsyncVault.totalSupply(), 0, "Initial total supply should be 0");
        assertEq(concreteBridgedAsyncVault.balanceOf(vaultManager), 0, "Initial vault manager balance should be 0");

        // Expect UnbackedMint event
        vm.expectEmit(true, true, true, true);
        emit IConcreteBridgedAsyncVaultImpl.UnbackedMint(sharesToMint);

        // Mint shares as vault manager
        vm.prank(vaultManager);
        concreteBridgedAsyncVault.unbackedMint(sharesToMint);

        // Verify final state
        assertEq(concreteBridgedAsyncVault.totalSupply(), sharesToMint, "Total supply should equal minted shares");
        assertEq(
            concreteBridgedAsyncVault.balanceOf(vaultManager),
            sharesToMint,
            "Vault manager balance should equal minted shares"
        );
    }

    /// @notice Test unbacked mint reverts when shares is zero
    function test_UnbackedMint_RevertsWhenZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IConcreteBridgedAsyncVaultImpl.ZeroAmount.selector));

        vm.prank(vaultManager);
        concreteBridgedAsyncVault.unbackedMint(0);
    }

    /// @notice Test unbacked mint reverts when total supply is not zero
    function test_UnbackedMint_RevertsWhenNotInitialMint() public {
        uint256 sharesToMint = 1000000e18;

        // First mint should succeed
        vm.prank(vaultManager);
        concreteBridgedAsyncVault.unbackedMint(sharesToMint);

        assertEq(concreteBridgedAsyncVault.totalSupply(), sharesToMint, "Total supply should be non-zero");

        // Second mint should fail
        vm.expectRevert(abi.encodeWithSelector(IConcreteBridgedAsyncVaultImpl.NotInitialMint.selector));

        vm.prank(vaultManager);
        concreteBridgedAsyncVault.unbackedMint(sharesToMint);
    }

    /// @notice Test unbacked mint reverts when caller is not vault manager
    function test_UnbackedMint_RevertsWhenNotVaultManager() public {
        uint256 sharesToMint = 1000000e18;

        // Expect AccessControl revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, RolesLib.VAULT_MANAGER
            )
        );

        vm.prank(user1);
        concreteBridgedAsyncVault.unbackedMint(sharesToMint);
    }

    /// @notice Test unbacked mint with various share amounts
    function testFuzz_UnbackedMint_VariousAmounts(uint256 sharesToMint) public {
        // Bound the shares to a reasonable range (greater than 0, less than max uint128 for safety)
        sharesToMint = bound(sharesToMint, 1, type(uint128).max);

        // Expect UnbackedMint event
        vm.expectEmit(true, true, true, true);
        emit IConcreteBridgedAsyncVaultImpl.UnbackedMint(sharesToMint);

        // Mint shares as vault manager
        vm.prank(vaultManager);
        concreteBridgedAsyncVault.unbackedMint(sharesToMint);

        // Verify final state
        assertEq(concreteBridgedAsyncVault.totalSupply(), sharesToMint, "Total supply should equal minted shares");
        assertEq(
            concreteBridgedAsyncVault.balanceOf(vaultManager),
            sharesToMint,
            "Vault manager balance should equal minted shares"
        );
    }

    /// @notice Test unbacked mint by different vault managers
    function test_UnbackedMint_DifferentVaultManagers() public {
        address vaultManager2 = makeAddr("vaultManager2");
        uint256 sharesToMint = 1000000e18;

        // Grant vault manager role to vaultManager2
        vm.prank(vaultManager);
        concreteBridgedAsyncVault.grantRole(RolesLib.VAULT_MANAGER, vaultManager2);

        // First vault manager mints
        vm.expectEmit(true, true, true, true);
        emit IConcreteBridgedAsyncVaultImpl.UnbackedMint(sharesToMint);

        vm.prank(vaultManager);
        concreteBridgedAsyncVault.unbackedMint(sharesToMint);

        assertEq(concreteBridgedAsyncVault.balanceOf(vaultManager), sharesToMint);

        // Second vault manager cannot mint (not initial mint anymore)
        vm.expectRevert(abi.encodeWithSelector(IConcreteBridgedAsyncVaultImpl.NotInitialMint.selector));

        vm.prank(vaultManager2);
        concreteBridgedAsyncVault.unbackedMint(sharesToMint);
    }

    /// @notice Test unbacked mint fails after deposit
    function test_UnbackedMint_RevertsAfterDeposit() public {
        uint256 depositAmount = 100000e18;
        uint256 sharesToMint = 1000000e18;

        // Setup user with assets and approval
        asset.mint(user1, depositAmount);
        vm.startPrank(user1);
        asset.approve(address(concreteBridgedAsyncVault), depositAmount);

        // User deposits first
        uint256 sharesMinted = concreteBridgedAsyncVault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Verify deposit worked
        assertEq(concreteBridgedAsyncVault.balanceOf(user1), sharesMinted, "User should have received shares");
        assertEq(concreteBridgedAsyncVault.totalSupply(), sharesMinted, "Total supply should equal deposited shares");
        assertGt(sharesMinted, 0, "Shares should have been minted");

        // Vault manager tries to unbacked mint - should fail because totalSupply > 0
        vm.expectRevert(abi.encodeWithSelector(IConcreteBridgedAsyncVaultImpl.NotInitialMint.selector));

        vm.prank(vaultManager);
        concreteBridgedAsyncVault.unbackedMint(sharesToMint);
    }

    /// @notice Test deposit works after unbacked mint with correct share calculation
    function test_Deposit_WorksAfterUnbackedMint() public {
        uint256 sharesToMint = 1000000e18;
        uint256 depositAmount = 100000e18;

        // Vault manager does unbacked mint first
        vm.prank(vaultManager);
        concreteBridgedAsyncVault.unbackedMint(sharesToMint);

        // Verify unbacked mint worked
        assertEq(concreteBridgedAsyncVault.totalSupply(), sharesToMint, "Total supply should equal minted shares");
        assertEq(
            concreteBridgedAsyncVault.balanceOf(vaultManager), sharesToMint, "Vault manager should have minted shares"
        );

        // Setup user with assets and approval
        asset.mint(user1, depositAmount);
        vm.startPrank(user1);
        asset.approve(address(concreteBridgedAsyncVault), depositAmount);

        // User deposits after unbacked mint
        uint256 totalSupplyBefore = concreteBridgedAsyncVault.totalSupply();

        uint256 sharesReceived = concreteBridgedAsyncVault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Verify deposit worked
        assertGt(sharesReceived, 0, "User should have received shares");
        assertEq(
            concreteBridgedAsyncVault.balanceOf(user1), sharesReceived, "User balance should match shares received"
        );
        assertEq(
            concreteBridgedAsyncVault.totalSupply(),
            totalSupplyBefore + sharesReceived,
            "Total supply should increase by shares received"
        );

        // When totalAssets is 0 but totalSupply > 0, the conversion formula is:
        // shares = assets * (totalSupply + 1) / (totalAssets + 1)
        // shares = 100000e18 * (1000000e18 + 1) / (0 + 1)
        // shares = 100000e18 * 1000000e18 (approximately)
        // This results in a HUGE amount of shares because the share price is effectively infinite
        uint256 expectedShares = depositAmount * (totalSupplyBefore + 1) / 1; // (0 + 1) = 1
        assertEq(sharesReceived, expectedShares, "Shares calculated using conversion formula");

        // Verify the shares are significantly more than the deposit amount
        assertGt(sharesReceived, depositAmount, "User receives many more shares than deposited assets");

        // Verify assets were transferred
        assertEq(concreteBridgedAsyncVault.totalAssets(), depositAmount, "Total assets should equal deposit amount");
    }
}

