// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../mock/ERC20Mock.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {ConcreteStandardVaultImplBaseSetup} from "../../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {IAllocateModule} from "../../../src/interface/IAllocateModule.sol";
import {SimpleStrategy} from "../../../src/periphery/strategies/SimpleStrategy.sol";
import {BaseStrategy} from "../../../src/periphery/strategies/BaseStrategy.sol";
import {IBaseStrategy} from "../../../src/periphery/interface/IBaseStrategy.sol";
import {IConcreteStandardVaultImpl} from "../../../src/interface/IConcreteStandardVaultImpl.sol";
import {StrategyType} from "../../../src/interface/IStrategyTemplate.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PeripheryRolesLib} from "../../../src/periphery/lib/PeripheryRolesLib.sol";
import {AddStrategyWithDeallocationOrder} from "../../common/AddStrategyWithDeallocationOrder.sol";

contract SimpleStrategyE2ETest is ConcreteStandardVaultImplBaseSetup, AddStrategyWithDeallocationOrder {
    address public user1;
    address public user2;
    address public admin;

    SimpleStrategy public strategy;

    uint256 public constant INITIAL_DEPOSIT = 1000e18;
    uint256 public constant STRATEGY_ALLOCATION = 500e18;

    event AllocateFunds(address indexed vault, uint256 amount);
    event DeallocateFunds(address indexed vault, uint256 amount);
    event Withdraw(address indexed vault, uint256 amount);

    function setUp() public override {
        ConcreteStandardVaultImplBaseSetup.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        admin = makeAddr("admin");

        // Deploy SimpleStrategy
        strategy = deployAndInitializeStrategy();

        vm.label(address(strategy), "SimpleStrategy");
        vm.label(user1, "user1");
        vm.label(user2, "user2");
        vm.label(admin, "admin");

        // Add strategy to vault
        addStrategyWithDeallocationOrder(address(strategy), address(concreteStandardVault), allocator, strategyOperator);

        // Give users some tokens
        asset.mint(user1, INITIAL_DEPOSIT * 2);
        asset.mint(user2, INITIAL_DEPOSIT * 2);

        // Give strategy some tokens for testing
        asset.mint(address(this), INITIAL_DEPOSIT * 10);
    }

    function deployAndInitializeStrategy() internal returns (SimpleStrategy) {
        SimpleStrategy impl = new SimpleStrategy();

        // Create proxy and initialize
        bytes memory initData =
            abi.encodeWithSelector(BaseStrategy.initialize.selector, admin, address(concreteStandardVault));

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        return SimpleStrategy(address(proxy));
    }

    function testStrategyInitialization() public view {
        assertEq(strategy.asset(), address(asset));
        assertTrue(strategy.hasRole(PeripheryRolesLib.STRATEGY_ADMIN, admin));
        assertEq(strategy.getVault(), address(concreteStandardVault));
        assertEq(uint8(strategy.strategyType()), uint8(StrategyType.ATOMIC));
        assertEq(strategy.maxAllocation(), type(uint256).max);
    }

    function testAllocateFundsThroughVault() public {
        // Setup: User deposits to vault
        _depositAsUser(user1, INITIAL_DEPOSIT);

        // Allocate funds to strategy through vault
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Verify allocation
        assertEq(strategy.totalAllocatedValue(), STRATEGY_ALLOCATION);
        assertEq(asset.balanceOf(address(strategy)), STRATEGY_ALLOCATION);
        assertEq(concreteStandardVault.totalAssets(), INITIAL_DEPOSIT);
    }

    function testDeallocateFundsThroughVault() public {
        // Setup: User deposits and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Deallocate funds through vault
        _deallocateFromStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Verify deallocation
        assertEq(strategy.totalAllocatedValue(), 0);
        assertEq(asset.balanceOf(address(strategy)), 0);
        assertEq(asset.balanceOf(address(concreteStandardVault)), INITIAL_DEPOSIT);
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

        // Withdraw through vault
        vm.prank(user1);
        concreteStandardVault.withdraw(withdrawAmount, user1, user1);

        // Verify withdrawal
        assertEq(asset.balanceOf(user1), userInitialBalance + withdrawAmount);

        // The vault should have less balance (it used its own balance first)
        assertEq(asset.balanceOf(address(concreteStandardVault)), vaultInitialBalance - withdrawAmount);

        // Strategy allocation should remain unchanged since vault used its own balance
        assertEq(strategy.totalAllocatedValue(), strategyInitialBalance);
        assertEq(asset.balanceOf(address(strategy)), strategyInitialBalance);
    }

    function testMultipleUsersWithStrategy() public {
        // Setup: Both users deposit
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);

        // Allocate all funds to strategy
        uint256 totalDeposited = INITIAL_DEPOSIT * 2;
        _allocateToStrategy(address(strategy), totalDeposited);

        // Verify total allocation
        assertEq(strategy.totalAllocatedValue(), totalDeposited);
        assertEq(asset.balanceOf(address(strategy)), totalDeposited);

        // User1 withdraws half
        uint256 user1Withdraw = INITIAL_DEPOSIT / 2;
        vm.prank(user1);
        concreteStandardVault.withdraw(user1Withdraw, user1, user1);

        // User2 withdraws half
        uint256 user2Withdraw = INITIAL_DEPOSIT / 2;
        vm.prank(user2);
        concreteStandardVault.withdraw(user2Withdraw, user2, user2);

        // Verify final state
        assertEq(strategy.totalAllocatedValue(), totalDeposited - user1Withdraw - user2Withdraw);
        assertEq(asset.balanceOf(address(strategy)), totalDeposited - user1Withdraw - user2Withdraw);
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

        vm.prank(user1);
        concreteStandardVault.withdraw(totalWithdraw, user1, user1);

        // Now max withdraw should be reduced by the amount taken from strategy
        assertEq(strategy.maxWithdraw(), STRATEGY_ALLOCATION - strategyWithdrawAmount);
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

    function testConvertFunctionsUnaffectedByStrategyOperations() public {
        // Setup: User deposits to vault
        _depositAsUser(user1, INITIAL_DEPOSIT);

        // Record initial conversion rates
        uint256 initialAssetsToShares = concreteStandardVault.convertToShares(100e18);
        uint256 initialSharesToAssets = concreteStandardVault.convertToAssets(100e18);

        // Allocate funds to strategy
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Verify conversion rates are unchanged after allocation
        assertEq(
            concreteStandardVault.convertToShares(100e18),
            initialAssetsToShares,
            "convertToShares should be unchanged after allocation"
        );
        assertEq(
            concreteStandardVault.convertToAssets(100e18),
            initialSharesToAssets,
            "convertToAssets should be unchanged after allocation"
        );

        // Deallocate funds from strategy
        _deallocateFromStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Verify conversion rates are unchanged after deallocation
        assertEq(
            concreteStandardVault.convertToShares(100e18),
            initialAssetsToShares,
            "convertToShares should be unchanged after deallocation"
        );
        assertEq(
            concreteStandardVault.convertToAssets(100e18),
            initialSharesToAssets,
            "convertToAssets should be unchanged after deallocation"
        );

        // Re-allocate funds to strategy
        _allocateToStrategy(address(strategy), STRATEGY_ALLOCATION);

        // Perform a withdrawal that uses strategy funds
        uint256 vaultBalance = asset.balanceOf(address(concreteStandardVault));
        uint256 strategyWithdrawAmount = 100e18;
        uint256 totalWithdraw = vaultBalance + strategyWithdrawAmount;

        vm.prank(user1);
        concreteStandardVault.withdraw(totalWithdraw, user1, user1);

        // Verify conversion rates are unchanged after strategy withdrawal
        assertEq(
            concreteStandardVault.convertToShares(100e18),
            initialAssetsToShares,
            "convertToShares should be unchanged after strategy withdrawal"
        );
        assertEq(
            concreteStandardVault.convertToAssets(100e18),
            initialSharesToAssets,
            "convertToAssets should be unchanged after strategy withdrawal"
        );

        // Test with different amounts to ensure consistency
        uint256 testAmount1 = 50e18;
        uint256 testAmount2 = 200e18;

        assertEq(
            concreteStandardVault.convertToShares(testAmount1),
            initialAssetsToShares * testAmount1 / 100e18,
            "convertToShares should scale proportionally"
        );
        assertEq(
            concreteStandardVault.convertToAssets(testAmount1),
            initialSharesToAssets * testAmount1 / 100e18,
            "convertToAssets should scale proportionally"
        );

        assertEq(
            concreteStandardVault.convertToShares(testAmount2),
            initialAssetsToShares * testAmount2 / 100e18,
            "convertToShares should scale proportionally"
        );
        assertEq(
            concreteStandardVault.convertToAssets(testAmount2),
            initialSharesToAssets * testAmount2 / 100e18,
            "convertToAssets should scale proportionally"
        );
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
