// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../mock/ERC20Mock.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {ConcreteStandardVaultImplBaseSetup} from "../../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {IAllocateModule} from "../../../src/interface/IAllocateModule.sol";
import {MultisigStrategy} from "../../../src/periphery/strategies/MultisigStrategy.sol";
import {BaseStrategy} from "../../../src/periphery/strategies/BaseStrategy.sol";
import {IBaseStrategy} from "../../../src/periphery/interface/IBaseStrategy.sol";
import {IConcreteStandardVaultImpl} from "../../../src/interface/IConcreteStandardVaultImpl.sol";
import {StrategyType} from "../../../src/interface/IStrategyTemplate.sol";
import {PeripheryRolesLib} from "../../../src/periphery/lib/PeripheryRolesLib.sol";
import {PositionAccountingLib} from "../../../src/periphery/lib/PositionAccountingLib.sol";
import {AddStrategyWithDeallocationOrder} from "../../common/AddStrategyWithDeallocationOrder.sol";

// EnforcedPause error from PausableUpgradeable
error EnforcedPause();

import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MultisigStrategyE2ETest is ConcreteStandardVaultImplBaseSetup, AddStrategyWithDeallocationOrder {
    address public user1;
    address public user2;
    address public admin;
    address public multisig;
    address public operator;

    MultisigStrategy public strategy;

    uint256 public constant INITIAL_DEPOSIT = 1000e18;
    uint256 public constant STRATEGY_ALLOCATION = 500e18;

    event AllocateFunds(address indexed vault, uint256 amount);
    event DeallocateFunds(address indexed vault, uint256 amount);
    event Withdraw(address indexed vault, uint256 amount);
    event AssetsForwarded(address indexed asset, uint256 amount, address multiSig);
    event AssetsRetrieved(address indexed asset, uint256 amount, address multiSig);

    function setUp() public override {
        ConcreteStandardVaultImplBaseSetup.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        admin = makeAddr("admin");
        multisig = makeAddr("multisig");
        operator = makeAddr("operator");

        // Deploy MultisigStrategy
        strategy = deployAndInitializeStrategy();

        vm.label(address(strategy), "MultisigStrategy");
        vm.label(user1, "user1");
        vm.label(user2, "user2");
        vm.label(admin, "admin");
        vm.label(multisig, "multisig");
        vm.label(operator, "operator");

        // Add strategy to vault
        addStrategyWithDeallocationOrder(address(strategy), address(concreteStandardVault), allocator, strategyOperator);

        // Give users some tokens
        asset.mint(user1, INITIAL_DEPOSIT * 2);
        asset.mint(user2, INITIAL_DEPOSIT * 2);

        // Give multisig some tokens for testing withdrawals
        asset.mint(multisig, INITIAL_DEPOSIT * 10);

        // Grant operator role to operator for accounting tests
        vm.prank(admin);
        strategy.grantRole(PeripheryRolesLib.OPERATOR_ROLE, operator);
    }

    function deployAndInitializeStrategy() internal returns (MultisigStrategy) {
        MultisigStrategy impl = new MultisigStrategy();

        // Create proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            MultisigStrategy.initialize.selector,
            admin,
            address(concreteStandardVault),
            multisig,
            uint64(1000), // maxAccountingChangeThreshold (10%)
            uint64(86400), // accountingValidityPeriod (1 day)
            uint64(3600) // cooldownPeriod (1 hour)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        return MultisigStrategy(address(proxy));
    }

    function testStrategyInitialization() public view {
        assertEq(strategy.asset(), address(asset));
        assertTrue(strategy.hasRole(PeripheryRolesLib.STRATEGY_ADMIN, admin));
        assertEq(strategy.getVault(), address(concreteStandardVault));
        assertEq(uint8(strategy.strategyType()), uint8(StrategyType.ASYNC));
        assertEq(strategy.maxAllocation(), type(uint256).max);
        assertEq(strategy.getMultiSig(), multisig);
    }

    function testAllocateFundsThroughVault() public {
        // Setup: User deposits to vault
        _depositAsUser(user1, INITIAL_DEPOSIT);

        // Record initial balances
        uint256 initialMultisigBalance = asset.balanceOf(multisig);
        uint256 initialVaultBalance = asset.balanceOf(address(concreteStandardVault));

        // Allocate funds to strategy through vault
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Verify allocation
        assertEq(strategy.totalAllocatedValue(), STRATEGY_ALLOCATION);
        assertEq(asset.balanceOf(address(strategy)), 0); // Strategy should have no balance
        assertEq(concreteStandardVault.totalAssets(), INITIAL_DEPOSIT);

        // Verify funds ended up in multisig
        assertEq(asset.balanceOf(multisig), initialMultisigBalance + STRATEGY_ALLOCATION);
        assertEq(asset.balanceOf(address(concreteStandardVault)), initialVaultBalance - STRATEGY_ALLOCATION);
    }

    function testDeallocateFundsThroughVault() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Record initial balances
        uint256 initialMultisigBalance = asset.balanceOf(multisig);
        uint256 initialVaultBalance = asset.balanceOf(address(concreteStandardVault));

        // Approve strategy to pull funds from multisig
        vm.prank(multisig);
        asset.approve(address(strategy), STRATEGY_ALLOCATION);

        // Deallocate funds through vault
        _deallocateFromStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Verify deallocation
        assertEq(strategy.totalAllocatedValue(), 0);
        assertEq(asset.balanceOf(address(strategy)), 0); // Strategy should have no balance
        assertEq(asset.balanceOf(address(concreteStandardVault)), INITIAL_DEPOSIT);

        // Verify funds came back from multisig to vault
        assertEq(asset.balanceOf(multisig), initialMultisigBalance - STRATEGY_ALLOCATION);
        assertEq(asset.balanceOf(address(concreteStandardVault)), initialVaultBalance + STRATEGY_ALLOCATION);
    }

    function testWithdrawThroughVault() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        uint256 withdrawAmount = 200e18;

        // Record initial balances
        uint256 userInitialBalance = asset.balanceOf(user1);
        uint256 strategyInitialBalance = strategy.totalAllocatedValue();
        uint256 vaultInitialBalance = asset.balanceOf(address(concreteStandardVault));
        uint256 multisigInitialBalance = asset.balanceOf(multisig);

        // Approve strategy to pull funds from multisig
        vm.prank(multisig);
        asset.approve(address(strategy), withdrawAmount);

        // Withdraw through vault
        vm.prank(user1);
        concreteStandardVault.withdraw(withdrawAmount, user1, user1);

        // Verify withdrawal
        assertEq(asset.balanceOf(user1), userInitialBalance + withdrawAmount);

        // The vault should have less balance (it used its own balance first)
        assertEq(asset.balanceOf(address(concreteStandardVault)), vaultInitialBalance - withdrawAmount);

        // Strategy allocation should remain unchanged since vault used its own balance
        assertEq(strategy.totalAllocatedValue(), strategyInitialBalance);
        assertEq(asset.balanceOf(address(strategy)), 0); // Strategy should have no balance
        assertEq(asset.balanceOf(multisig), multisigInitialBalance); // Multisig balance unchanged
    }

    function testWithdrawFromStrategyWhenVaultBalanceInsufficient() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Record initial balances
        uint256 userInitialBalance = asset.balanceOf(user1);
        uint256 multisigInitialBalance = asset.balanceOf(multisig);

        // Withdraw more than vault's balance to force strategy withdrawal
        uint256 vaultBalance = asset.balanceOf(address(concreteStandardVault));
        uint256 strategyWithdrawAmount = 100e18;
        uint256 totalWithdraw = vaultBalance + strategyWithdrawAmount;

        // Approve strategy to pull funds from multisig
        vm.prank(multisig);
        asset.approve(address(strategy), strategyWithdrawAmount);

        // Withdraw through vault
        vm.prank(user1);
        concreteStandardVault.withdraw(totalWithdraw, user1, user1);

        // Verify withdrawal
        assertEq(asset.balanceOf(user1), userInitialBalance + totalWithdraw);

        // Vault balance should be 0 (all used)
        assertEq(asset.balanceOf(address(concreteStandardVault)), 0);

        // Strategy allocation should be reduced by the amount taken from strategy
        assertEq(strategy.totalAllocatedValue(), STRATEGY_ALLOCATION - strategyWithdrawAmount);
        assertEq(asset.balanceOf(address(strategy)), 0); // Strategy should have no balance

        // Multisig balance should be reduced by the amount taken from strategy
        assertEq(asset.balanceOf(multisig), multisigInitialBalance - strategyWithdrawAmount);
    }

    function testMultipleUsersWithStrategy() public {
        // Setup: Both users deposit
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);

        // Allocate all funds to strategy
        uint256 totalDeposited = INITIAL_DEPOSIT * 2;
        _allocateToStrategy(address(strategy), totalDeposited);

        // Verify total allocation and multisig balance
        assertEq(strategy.totalAllocatedValue(), totalDeposited);
        assertEq(asset.balanceOf(address(strategy)), 0); // Strategy should have no balance
        assertEq(asset.balanceOf(multisig), INITIAL_DEPOSIT * 10 + totalDeposited); // Initial balance + allocated funds

        // User1 withdraws half
        uint256 user1Withdraw = INITIAL_DEPOSIT / 2;

        // Approve strategy to pull funds from multisig
        vm.prank(multisig);
        asset.approve(address(strategy), user1Withdraw);

        vm.prank(user1);
        concreteStandardVault.withdraw(user1Withdraw, user1, user1);

        // User2 withdraws half
        uint256 user2Withdraw = INITIAL_DEPOSIT / 2;

        // Approve strategy to pull funds from multisig
        vm.prank(multisig);
        asset.approve(address(strategy), user2Withdraw);

        vm.prank(user2);
        concreteStandardVault.withdraw(user2Withdraw, user2, user2);

        // Verify final state
        assertEq(strategy.totalAllocatedValue(), totalDeposited - user1Withdraw - user2Withdraw);
        assertEq(asset.balanceOf(address(strategy)), 0); // Strategy should have no balance
        assertEq(asset.balanceOf(multisig), INITIAL_DEPOSIT * 10 + totalDeposited - user1Withdraw - user2Withdraw);
    }

    function testMaxWithdraw() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Test maxWithdraw - should return current allocated amount
        assertEq(strategy.maxWithdraw(), STRATEGY_ALLOCATION);

        // Withdraw some funds first (vault will use its own balance)
        uint256 partialWithdraw = STRATEGY_ALLOCATION / 2;
        vm.prank(user1);
        concreteStandardVault.withdraw(partialWithdraw, user1, user1);

        // Max withdraw should still be the full allocation since vault used its own balance
        assertEq(strategy.maxWithdraw(), STRATEGY_ALLOCATION);

        // Withdraw more than the vault's remaining balance to force strategy withdrawal
        uint256 remainingVaultBalance = asset.balanceOf(address(concreteStandardVault));
        uint256 strategyWithdrawAmount = 100e18; // Amount that will come from strategy
        uint256 totalWithdraw = remainingVaultBalance + strategyWithdrawAmount;

        // Approve strategy to pull funds from multisig
        vm.prank(multisig);
        asset.approve(address(strategy), strategyWithdrawAmount);

        vm.prank(user1);
        concreteStandardVault.withdraw(totalWithdraw, user1, user1);

        // Now max withdraw should be reduced by the amount taken from strategy
        assertEq(strategy.maxWithdraw(), STRATEGY_ALLOCATION - strategyWithdrawAmount);
    }

    function testWithdrawDisabled() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Disable withdrawals
        vm.prank(admin);
        strategy.setMaxWithdraw(0); // Disable withdrawals by setting maxWithdraw to 0

        // Approve strategy to pull funds from multisig
        vm.prank(multisig);
        asset.approve(address(strategy), STRATEGY_ALLOCATION);

        // Try to deallocate funds - should work (deallocate is not restricted by maxWithdraw)
        _deallocateFromStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Try to withdraw through vault - should fail when strategy is called
        uint256 vaultBalance = asset.balanceOf(address(concreteStandardVault));
        uint256 strategyWithdrawAmount = 100e18;
        uint256 totalWithdraw = vaultBalance + strategyWithdrawAmount;

        vm.prank(user1);
        vm.expectRevert(); // Should revert due to maxWithdraw being 0
        concreteStandardVault.withdraw(totalWithdraw, user1, user1);
    }

    function testOperatorRole() public {
        // Grant operator role to operator
        vm.prank(admin);
        strategy.grantRole(PeripheryRolesLib.OPERATOR_ROLE, operator);

        // Verify operator has the role
        assertTrue(strategy.isOperator(operator));

        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Verify initial allocation
        assertEq(strategy.totalAllocatedValue(), STRATEGY_ALLOCATION);

        // Test that operator can call adjustTotalAssets (even if it fails due to validation)
        // The important thing is that the role check passes
        vm.prank(operator);
        strategy.adjustTotalAssets(50e18, 1); // This will pause the strategy due to validation failure

        // Verify strategy is paused due to validation failure
        assertTrue(strategy.paused());

        // Note: We can't call totalAllocatedValue when paused as _previewPosition() will revert
        // The allocation remains unchanged since the adjustment failed
    }

    function testUnauthorizedAccess() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Try to call strategy functions directly (should fail)
        vm.prank(user1);
        vm.expectRevert(IBaseStrategy.UnauthorizedVault.selector);
        strategy.allocateFunds(abi.encode(100e18));

        vm.prank(user1);
        vm.expectRevert(IBaseStrategy.UnauthorizedVault.selector);
        strategy.deallocateFunds(abi.encode(100e18));

        vm.prank(user1);
        vm.expectRevert(IBaseStrategy.UnauthorizedVault.selector);
        strategy.onWithdraw(100e18);
    }

    function testInsufficientAllocatedAmount() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Try to withdraw more than the user has deposited (not just allocated)
        // The vault should prevent withdrawal of more than user's balance
        vm.prank(user1);
        vm.expectRevert();
        concreteStandardVault.withdraw(INITIAL_DEPOSIT + 1, user1, user1);
    }

    function testEmergencyRecover() public {
        // Create a different token for emergency recovery
        ERC20Mock otherToken = new ERC20Mock();
        otherToken.mint(address(strategy), 100e18);

        uint256 initialBalance = otherToken.balanceOf(admin);

        // Admin can recover tokens
        vm.prank(admin);
        strategy.rescueToken(address(otherToken), 50e18);

        assertEq(otherToken.balanceOf(admin), initialBalance + 50e18);
    }

    function testEmergencyRecoverUnauthorized() public {
        // Create a different token for unauthorized test
        ERC20Mock otherToken = new ERC20Mock();

        // Non-admin cannot recover tokens
        vm.prank(user1);
        vm.expectRevert();
        strategy.rescueToken(address(otherToken), 50e18);
    }

    function testEmergencyRecoverAssetToken() public {
        // Mint some tokens to the strategy
        asset.mint(address(strategy), 100e18);

        // Try to recover the strategy's asset token (should fail)
        vm.prank(admin);
        vm.expectRevert(IBaseStrategy.InvalidAsset.selector);
        strategy.rescueToken(address(asset), 50e18);
    }

    function testTotalAllocatedValue() public {
        // Initially should return 0
        assertEq(strategy.totalAllocatedValue(), 0);

        // Allocate some funds
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Should return allocated amount
        assertEq(strategy.totalAllocatedValue(), STRATEGY_ALLOCATION);
    }

    function testMultisigBalanceTracking() public {
        // Test that multisig balance is properly tracked through multiple operations

        // Initial state
        uint256 initialMultisigBalance = asset.balanceOf(multisig);
        assertEq(initialMultisigBalance, INITIAL_DEPOSIT * 10); // From setUp

        // User deposits and allocate
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Verify multisig received funds
        assertEq(asset.balanceOf(multisig), initialMultisigBalance + STRATEGY_ALLOCATION);

        // Deallocate some funds
        uint256 deallocateAmount = 200e18;
        vm.prank(multisig);
        asset.approve(address(strategy), deallocateAmount);
        _deallocateFromStrategy(address(strategy), deallocateAmount);

        // Verify multisig balance decreased
        assertEq(asset.balanceOf(multisig), initialMultisigBalance + STRATEGY_ALLOCATION - deallocateAmount);

        // Allocate more funds
        uint256 additionalAllocation = 300e18;
        _allocateToStrategy(address(strategy), additionalAllocation);

        // Verify multisig balance increased
        assertEq(
            asset.balanceOf(multisig),
            initialMultisigBalance + STRATEGY_ALLOCATION - deallocateAmount + additionalAllocation
        );
    }

    // ========== ACCOUNTING LIBRARY TESTS ==========

    function testValidAccountingAdjustmentWithYield() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Record initial allocation
        uint256 strategyInitialAllocation = strategy.totalAllocatedValue();

        // Wait for cooldown period to pass (1 hour = 3600 seconds)
        vm.warp(block.timestamp + 3601);

        // Simulate yield by adjusting total assets (valid adjustment within threshold)
        uint256 yieldAmount = 50e18; // 10% yield (within 10% threshold)
        uint256 nextNonce = strategy.getNextAccountingNonce();

        vm.prank(operator);
        strategy.adjustTotalAssets(int256(yieldAmount), nextNonce);

        // Verify the adjustment was applied
        assertEq(strategy.totalAllocatedValue(), strategyInitialAllocation + yieldAmount);

        // Verify strategy is not paused (valid adjustment)
        assertFalse(strategy.paused());

        // Test that deposits and withdrawals still work after valid adjustment
        // Give user more tokens and approve vault
        asset.mint(user1, 100e18);
        vm.prank(user1);
        asset.approve(address(concreteStandardVault), 100e18);

        vm.prank(user1);
        concreteStandardVault.deposit(100e18, user1);
    }

    function testCooldownPeriodViolation() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Wait for cooldown period to pass for first adjustment
        vm.warp(block.timestamp + 3601);

        // First valid adjustment
        uint256 yieldAmount = 50e18;
        uint256 nextNonce = strategy.getNextAccountingNonce();

        vm.prank(operator);
        strategy.adjustTotalAssets(int256(yieldAmount), nextNonce);

        // Verify strategy is not paused
        assertFalse(strategy.paused());

        // Try to adjust again before cooldown period (1 hour = 3600 seconds)
        nextNonce = strategy.getNextAccountingNonce();

        vm.prank(operator);
        strategy.adjustTotalAssets(int256(10e18), nextNonce);

        // Strategy should be paused due to cooldown violation
        assertTrue(strategy.paused());

        // Verify that strategy functions that require whenNotPaused are blocked
        // Try to call adjustTotalAssets again - should fail due to pause
        nextNonce = strategy.getNextAccountingNonce();
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        strategy.adjustTotalAssets(int256(5e18), nextNonce);

        // Verify that vault operations also fail when strategy is paused
        // Try to deposit - should fail due to pause
        asset.mint(user1, 100e18);
        vm.prank(user1);
        asset.approve(address(concreteStandardVault), 100e18);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        concreteStandardVault.deposit(100e18, user1);

        // Try to withdraw - should fail due to pause
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        concreteStandardVault.withdraw(50e18, user1, user1);

        // Admin unpauses and fixes the accounting
        vm.prank(admin);
        strategy.unpauseAndAdjustTotalAssets(int256(10e18)); // Apply the adjustment that was blocked

        // Verify strategy is unpaused
        assertFalse(strategy.paused());

        // Verify the adjustment was applied
        assertEq(strategy.totalAllocatedValue(), STRATEGY_ALLOCATION + yieldAmount + 10e18);

        // Now deposits and withdrawals should work again
        // Give user more tokens and approve vault
        asset.mint(user1, 100e18);
        vm.prank(user1);
        asset.approve(address(concreteStandardVault), 100e18);

        vm.prank(user1);
        concreteStandardVault.deposit(100e18, user1);
    }

    function testLargeAccountingChangeViolation() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Wait for cooldown period to pass
        vm.warp(block.timestamp + 3601);

        // Try to adjust with too large change (20% > 10% threshold)
        uint256 largeYieldAmount = 200e18; // 40% yield (exceeds 10% threshold)
        uint256 nextNonce = strategy.getNextAccountingNonce();

        vm.prank(operator);
        strategy.adjustTotalAssets(int256(largeYieldAmount), nextNonce);

        // Strategy should be paused due to large change violation
        assertTrue(strategy.paused());

        // Verify that strategy functions that require whenNotPaused are blocked
        // Try to call adjustTotalAssets again - should fail due to pause
        nextNonce = strategy.getNextAccountingNonce();
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        strategy.adjustTotalAssets(int256(5e18), nextNonce);

        // Verify that vault operations also fail when strategy is paused
        // Try to deposit - should fail due to pause
        asset.mint(user1, 100e18);
        vm.prank(user1);
        asset.approve(address(concreteStandardVault), 100e18);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        concreteStandardVault.deposit(100e18, user1);

        // Try to withdraw - should fail due to pause
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        concreteStandardVault.withdraw(50e18, user1, user1);

        // Admin unpauses and fixes the accounting with a smaller adjustment
        uint256 smallerYieldAmount = 50e18; // 10% yield (within threshold)
        vm.prank(admin);
        strategy.unpauseAndAdjustTotalAssets(int256(smallerYieldAmount));

        // Verify strategy is unpaused
        assertFalse(strategy.paused());

        // Verify the smaller adjustment was applied
        assertEq(strategy.totalAllocatedValue(), STRATEGY_ALLOCATION + smallerYieldAmount);

        // Now deposits and withdrawals should work again
        // Give user more tokens and approve vault
        asset.mint(user1, 100e18);
        vm.prank(user1);
        asset.approve(address(concreteStandardVault), 100e18);

        vm.prank(user1);
        concreteStandardVault.deposit(100e18, user1);
    }

    function testAccountingValidityPeriodExpired() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Wait for cooldown period to pass
        uint256 time1 = 1 + 3601;
        vm.warp(time1);

        // Make a valid adjustment first
        uint256 yieldAmount = 50e18;
        uint256 nextNonce = strategy.getNextAccountingNonce();

        vm.prank(operator);
        strategy.adjustTotalAssets(int256(yieldAmount), nextNonce);

        // Warp time to make accounting stale (accounting validity period is 1 day = 86400 seconds)
        uint256 time2 = time1 + 86401;
        vm.warp(time2); // 1 second past validity period

        // Try to deposit - should fail due to stale accounting
        asset.mint(user1, 100e18);
        vm.prank(user1);
        asset.approve(address(concreteStandardVault), 100e18);

        vm.prank(user1);
        vm.expectRevert(PositionAccountingLib.AccountingValidityPeriodExpired.selector);
        concreteStandardVault.deposit(100e18, user1);

        // Try to withdraw - should also fail due to stale accounting
        vm.prank(user1);
        vm.expectRevert(PositionAccountingLib.AccountingValidityPeriodExpired.selector);
        concreteStandardVault.withdraw(50e18, user1, user1);

        // Admin can fix by making a new accounting adjustment (this updates the timestamp)
        // Wait for cooldown period to pass first
        uint256 time3 = time2 + 3601;
        vm.warp(time3);
        nextNonce = strategy.getNextAccountingNonce();
        vm.prank(admin);
        strategy.adjustTotalAssets(int256(10e18), nextNonce);

        // Now deposits and withdrawals should work again
        vm.prank(user1);
        concreteStandardVault.deposit(100e18, user1);

        // Verify withdrawals also work again
        vm.prank(user1);
        concreteStandardVault.withdraw(50e18, user1, user1);
    }

    function testAccountingValidityPeriodExpiredWithAllocationModule() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Wait for cooldown period to pass
        vm.warp(block.timestamp + 3601);

        // Make a valid adjustment first
        uint256 yieldAmount = 50e18;
        uint256 nextNonce = strategy.getNextAccountingNonce();

        vm.prank(operator);
        strategy.adjustTotalAssets(int256(yieldAmount), nextNonce);

        // Warp time to make accounting stale (accounting validity period is 1 day = 86400 seconds)
        vm.warp(block.timestamp + 86401); // 1 second past validity period

        // Try to allocate more funds through allocation module - should fail due to stale accounting
        IAllocateModule.AllocateParams[] memory allocateParams = new IAllocateModule.AllocateParams[](1);
        allocateParams[0] = IAllocateModule.AllocateParams({
            strategy: address(strategy), isDeposit: true, extraData: abi.encode(100e18)
        });
        bytes memory allocateData = abi.encode(allocateParams);

        vm.startPrank(allocator);
        vm.expectRevert(PositionAccountingLib.AccountingValidityPeriodExpired.selector);
        concreteStandardVault.allocate(allocateData);
        vm.stopPrank();

        // Try to deallocate funds through allocation module - should also fail due to stale accounting
        IAllocateModule.AllocateParams[] memory deallocateParams = new IAllocateModule.AllocateParams[](1);
        deallocateParams[0] = IAllocateModule.AllocateParams({
            strategy: address(strategy), isDeposit: false, extraData: abi.encode(100e18)
        });
        bytes memory deallocateData = abi.encode(deallocateParams);

        vm.startPrank(allocator);
        vm.expectRevert(PositionAccountingLib.AccountingValidityPeriodExpired.selector);
        concreteStandardVault.allocate(deallocateData);
        vm.stopPrank();

        // Admin can fix by making a new accounting adjustment (this updates the timestamp)
        nextNonce = strategy.getNextAccountingNonce();
        vm.prank(admin);
        strategy.adjustTotalAssets(int256(10e18), nextNonce);

        // Now allocation module operations should work again
        _allocateToStrategy(address(strategy), 100e18);

        // Verify deallocation also works again
        vm.prank(multisig);
        asset.approve(address(strategy), 100e18);
        _deallocateFromStrategy(address(strategy), 100e18);
    }

    // Helper functions

    function _depositAsUser(address user, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(address(concreteStandardVault), amount);
        concreteStandardVault.deposit(amount, user);
        vm.stopPrank();
    }

    function _allocateToStrategy(address strategyAddress, uint256 amount) internal {
        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] =
            IAllocateModule.AllocateParams({strategy: strategyAddress, isDeposit: true, extraData: abi.encode(amount)});

        bytes memory allocateData = abi.encode(params);

        vm.prank(allocator);
        concreteStandardVault.allocate(allocateData);
    }

    function _deallocateFromStrategy(address strategyAddress, uint256 amount) internal {
        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] = IAllocateModule.AllocateParams({
            strategy: strategyAddress, isDeposit: false, extraData: abi.encode(amount)
        });

        bytes memory allocateData = abi.encode(params);

        vm.prank(allocator);
        concreteStandardVault.allocate(allocateData);
    }
}
