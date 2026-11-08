// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcreteStandardVaultImplBaseSetup} from "../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {IAllocateModule} from "../../src/interface/IAllocateModule.sol";
import {ERC4626StrategyMock} from "../mock/ERC4626StrategyMock.sol";
import {IConcreteStandardVaultImpl} from "../../src/interface/IConcreteStandardVaultImpl.sol";
import {AddStrategyWithDeallocationOrder} from "../common/AddStrategyWithDeallocationOrder.sol";

contract HaltedStrategyE2ETest is ConcreteStandardVaultImplBaseSetup, AddStrategyWithDeallocationOrder {
    address public user1;
    address public user2;

    ERC4626StrategyMock public activeStrategy;
    ERC4626StrategyMock public haltedStrategy;
    ERC4626StrategyMock public strategy3;

    uint256 public constant INITIAL_DEPOSIT = 1000e18;
    uint256 public constant STRATEGY_ALLOCATION = 300e18;

    event StrategyStatusToggled(address indexed strategy);

    function setUp() public override {
        ConcreteStandardVaultImplBaseSetup.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy strategies
        activeStrategy = new ERC4626StrategyMock(address(asset));
        haltedStrategy = new ERC4626StrategyMock(address(asset));
        strategy3 = new ERC4626StrategyMock(address(asset));

        vm.label(address(activeStrategy), "activeStrategy");
        vm.label(address(haltedStrategy), "haltedStrategy");
        vm.label(address(strategy3), "strategy3");
        vm.label(user1, "user1");
        vm.label(user2, "user2");

        // Add strategies to vault (all start as Active)
        addStrategyWithDeallocationOrder(
            address(activeStrategy), address(concreteStandardVault), allocator, strategyOperator
        );
        addStrategyWithDeallocationOrder(
            address(haltedStrategy), address(concreteStandardVault), allocator, strategyOperator
        );
        addStrategyWithDeallocationOrder(
            address(strategy3), address(concreteStandardVault), allocator, strategyOperator
        );

        // Give users some tokens
        asset.mint(user1, INITIAL_DEPOSIT * 2);
        asset.mint(user2, INITIAL_DEPOSIT * 2);

        // Give strategies some tokens for yield simulation
        asset.mint(address(this), INITIAL_DEPOSIT * 10);
    }

    function testToggleStrategyFromActiveToHalted() public {
        // Verify strategy starts as Active
        IConcreteStandardVaultImpl.StrategyData memory strategyData =
            concreteStandardVault.getStrategyData(address(haltedStrategy));
        assertEq(uint256(strategyData.status), uint256(IConcreteStandardVaultImpl.StrategyStatus.Active));

        // Toggle strategy to Halted
        vm.expectEmit();
        emit StrategyStatusToggled(address(haltedStrategy));

        vm.prank(strategyOperator);
        concreteStandardVault.toggleStrategyStatus(address(haltedStrategy));

        // Verify strategy is now Halted
        strategyData = concreteStandardVault.getStrategyData(address(haltedStrategy));
        assertEq(uint256(strategyData.status), uint256(IConcreteStandardVaultImpl.StrategyStatus.Halted));
    }

    function testToggleStrategyFromHaltedToActive() public {
        // First halt the strategy
        vm.prank(strategyOperator);
        concreteStandardVault.toggleStrategyStatus(address(haltedStrategy));

        // Verify strategy is Halted
        IConcreteStandardVaultImpl.StrategyData memory strategyData =
            concreteStandardVault.getStrategyData(address(haltedStrategy));
        assertEq(uint256(strategyData.status), uint256(IConcreteStandardVaultImpl.StrategyStatus.Halted));

        // Toggle back to Active
        vm.expectEmit();
        emit StrategyStatusToggled(address(haltedStrategy));

        vm.prank(strategyOperator);
        concreteStandardVault.toggleStrategyStatus(address(haltedStrategy));

        // Verify strategy is now Active again
        strategyData = concreteStandardVault.getStrategyData(address(haltedStrategy));
        assertEq(uint256(strategyData.status), uint256(IConcreteStandardVaultImpl.StrategyStatus.Active));
    }

    function testToggleStrategyRevertsForNonExistentStrategy() public {
        address nonExistentStrategy = makeAddr("nonExistentStrategy");

        vm.prank(strategyOperator);
        vm.expectRevert(IConcreteStandardVaultImpl.StrategyDoesNotExist.selector);
        concreteStandardVault.toggleStrategyStatus(nonExistentStrategy);
    }

    function testToggleStrategyRevertsForUnauthorizedUser() public {
        address unauthorizedUser = makeAddr("unauthorizedUser");

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        concreteStandardVault.toggleStrategyStatus(address(haltedStrategy));
    }

    function testAllocationIgnoresHaltedStrategies() public {
        // Setup: Users deposit funds
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);

        // Halt one strategy
        vm.prank(strategyOperator);
        concreteStandardVault.toggleStrategyStatus(address(haltedStrategy));

        // Allocate to both strategies (halted one should be ignored)
        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](2);
        params[0] = IAllocateModule.AllocateParams({
            strategy: address(activeStrategy), isDeposit: true, extraData: abi.encode(400e18)
        });
        params[1] = IAllocateModule.AllocateParams({
            strategy: address(haltedStrategy), isDeposit: true, extraData: abi.encode(400e18)
        });

        bytes memory allocateData = abi.encode(params);

        vm.prank(allocator);
        concreteStandardVault.allocate(allocateData);

        // Verify only active strategy received allocation
        assertEq(activeStrategy.totalAllocatedValue(), 400e18);
        assertEq(haltedStrategy.totalAllocatedValue(), 0);

        // Verify strategy data reflects allocations
        IConcreteStandardVaultImpl.StrategyData memory activeData =
            concreteStandardVault.getStrategyData(address(activeStrategy));
        IConcreteStandardVaultImpl.StrategyData memory haltedData =
            concreteStandardVault.getStrategyData(address(haltedStrategy));

        assertEq(activeData.allocated, 400e18);
        assertEq(haltedData.allocated, 0);
    }

    function testWithdrawalIgnoresHaltedStrategies() public {
        // Setup: Deposit and allocate to both strategies
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);

        // Allocate to both strategies while they're Active
        _allocateToStrategy(address(activeStrategy), 400e18);
        _allocateToStrategy(address(haltedStrategy), 400e18);

        // Halt one strategy after allocation
        vm.prank(strategyOperator);
        concreteStandardVault.toggleStrategyStatus(address(haltedStrategy));

        // Allocate remaining funds to leave minimal idle balance
        _allocateToStrategy(address(strategy3), 1200e18);

        // Capture user1's balance before withdrawal
        uint256 user1BalanceBefore = asset.balanceOf(user1);

        // Attempt large withdrawal that would normally require both strategies
        uint256 withdrawalAmount = 600e18;

        // Should still work, but only use Active strategies for deallocation
        vm.prank(user1);
        concreteStandardVault.withdraw(withdrawalAmount, user1, user1);

        // Verify user received the withdrawal amount (not total balance)
        uint256 user1BalanceAfter = asset.balanceOf(user1);
        uint256 actualWithdrawn = user1BalanceAfter - user1BalanceBefore;
        assertEq(actualWithdrawn, withdrawalAmount);

        // Verify halted strategy allocation remained unchanged
        assertEq(haltedStrategy.totalAllocatedValue(), 400e18);

        // Verify active strategies were used for deallocation
        uint256 activeStrategyRemaining = activeStrategy.totalAllocatedValue();
        uint256 strategy3Remaining = strategy3.totalAllocatedValue();

        // At least one of the active strategies should have been deallocated from
        assertTrue(activeStrategyRemaining < 400e18 || strategy3Remaining < 1200e18);
    }

    function testAccrueYieldIgnoresHaltedStrategies() public {
        // Setup: Deposit and allocate to both strategies
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);

        _allocateToStrategy(address(activeStrategy), 400e18);
        _allocateToStrategy(address(haltedStrategy), 400e18);

        // Halt one strategy after allocation
        vm.prank(strategyOperator);
        concreteStandardVault.toggleStrategyStatus(address(haltedStrategy));

        // Simulate yield in both strategies
        uint256 yieldAmount = 40e18; // 10% yield

        asset.approve(address(activeStrategy), yieldAmount);
        activeStrategy.simulateYield(yieldAmount);

        asset.approve(address(haltedStrategy), yieldAmount);
        haltedStrategy.simulateYield(yieldAmount);

        // Get strategy allocated amounts before yield accrual
        IConcreteStandardVaultImpl.StrategyData memory activeDataBefore =
            concreteStandardVault.getStrategyData(address(activeStrategy));
        IConcreteStandardVaultImpl.StrategyData memory haltedDataBefore =
            concreteStandardVault.getStrategyData(address(haltedStrategy));

        // Get expected yield before accrual
        uint256 expectedActiveYield = _getActualYield(address(activeStrategy));
        uint256 expectedHaltedYield = _getActualYield(address(haltedStrategy));

        // Get total assets deposited before accrual
        uint256 lastTotalAssetsBefore = concreteStandardVault.cachedTotalAssets();

        // Yield accrual should only process Active strategies
        concreteStandardVault.accrueYield();

        uint256 lastTotalAssetsAfter = concreteStandardVault.cachedTotalAssets();

        // Only yield from active strategy should be accrued (halted strategy yield ignored)
        // Note: lastTotalAssets is updated by yield accrual and reflects actual accrued amounts
        assertGt(lastTotalAssetsAfter, lastTotalAssetsBefore); // Should increase due to active strategy yield

        // More precise check: total increase should be close to active strategy yield (allowing for fees)
        uint256 actualIncrease = lastTotalAssetsAfter - lastTotalAssetsBefore;
        assertGe(actualIncrease, expectedActiveYield - 2); // Allow small rounding for fees
        assertLt(actualIncrease, expectedActiveYield + expectedHaltedYield); // Should not include halted yield

        // Verify halted strategy's allocated amount wasn't updated
        IConcreteStandardVaultImpl.StrategyData memory haltedDataAfter =
            concreteStandardVault.getStrategyData(address(haltedStrategy));
        assertEq(haltedDataAfter.allocated, haltedDataBefore.allocated); // Should remain unchanged

        // Verify active strategy's allocated amount was updated with the actual net yield
        IConcreteStandardVaultImpl.StrategyData memory activeDataAfter =
            concreteStandardVault.getStrategyData(address(activeStrategy));
        uint256 actualActiveYieldAccrued = activeDataAfter.allocated - activeDataBefore.allocated;
        assertEq(actualActiveYieldAccrued, expectedActiveYield); // Should match the expected yield
    }

    function testRemoveHaltedStrategyWithAllocatedFunds() public {
        // Setup: Deposit and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(haltedStrategy), 400e18);

        // Verify strategy has allocated funds
        IConcreteStandardVaultImpl.StrategyData memory strategyData =
            concreteStandardVault.getStrategyData(address(haltedStrategy));
        assertEq(strategyData.allocated, 400e18);

        // Halt the strategy
        vm.prank(strategyOperator);
        concreteStandardVault.toggleStrategyStatus(address(haltedStrategy));

        // Should be able to remove halted strategy even with allocated funds
        vm.prank(strategyOperator);
        concreteStandardVault.removeStrategy(address(haltedStrategy));

        // Verify strategy was removed from the strategies list
        address[] memory strategies = concreteStandardVault.getStrategies();
        for (uint256 i = 0; i < strategies.length; i++) {
            assertTrue(strategies[i] != address(haltedStrategy));
        }

        // Verify strategy data was deleted
        strategyData = concreteStandardVault.getStrategyData(address(haltedStrategy));
        assertEq(uint256(strategyData.status), uint256(IConcreteStandardVaultImpl.StrategyStatus.Inactive));
        assertEq(strategyData.allocated, 0);
    }

    function testMigrateHaltedStrategyWithAllocatedFunds() public {
        // Setup: Deposit and allocate to the strategy that will become "broken"
        _depositAsUser(user1, INITIAL_DEPOSIT);
        uint256 allocationAmount = 400e18;
        _allocateToStrategy(address(haltedStrategy), allocationAmount);

        // Verify strategy has allocated funds
        assertEq(concreteStandardVault.getStrategyData(address(haltedStrategy)).allocated, allocationAmount);

        // Record totalAssets before halting (this includes the allocated funds)
        uint256 totalAssetsBefore = concreteStandardVault.totalAssets();
        uint256 cachedTotalAssetsBefore = concreteStandardVault.cachedTotalAssets();

        // Step 1: Halt the broken strategy
        vm.prank(strategyOperator);
        concreteStandardVault.toggleStrategyStatus(address(haltedStrategy));

        // Verify strategy is halted
        assertEq(
            uint256(concreteStandardVault.getStrategyData(address(haltedStrategy)).status),
            uint256(IConcreteStandardVaultImpl.StrategyStatus.Halted)
        );

        // Step 2: Remove the halted broken strategy (totalAssets should remain unchanged)
        vm.prank(strategyOperator);
        concreteStandardVault.removeStrategy(address(haltedStrategy));

        // Verify totalAssets unchanged after removal
        assertEq(concreteStandardVault.totalAssets(), totalAssetsBefore, "totalAssets unchanged after removal");
        assertEq(
            concreteStandardVault.cachedTotalAssets(),
            cachedTotalAssetsBefore,
            "cachedTotalAssets unchanged after removal"
        );

        // Verify strategy was removed from the strategies list
        address[] memory strategies = concreteStandardVault.getStrategies();
        for (uint256 i = 0; i < strategies.length; i++) {
            assertTrue(strategies[i] != address(haltedStrategy));
        }

        // Step 3: Rescue and transfer the raw assets back to the vault
        assertEq(haltedStrategy.totalAllocatedValue(), allocationAmount, "Rescued amount equals original allocation");

        // Emergency rescue: withdraw assets from strategy to this contract
        haltedStrategy.emergencyRescue(address(this));

        // Verify totalAssets unchanged after rescue
        assertEq(concreteStandardVault.totalAssets(), totalAssetsBefore, "totalAssets unchanged after rescue");
        assertEq(
            concreteStandardVault.cachedTotalAssets(),
            cachedTotalAssetsBefore,
            "cachedTotalAssets unchanged after rescue"
        );

        // Verify old strategy has zero allocation after rescue
        assertEq(haltedStrategy.totalAllocatedValue(), 0, "Old strategy has zero allocated value after rescue");

        // Transfer (donate) the rescued assets to the vault
        asset.transfer(address(concreteStandardVault), allocationAmount);

        // Verify totalAssets unchanged after donation to vault
        assertEq(concreteStandardVault.totalAssets(), totalAssetsBefore, "totalAssets unchanged after donation");
        assertEq(
            concreteStandardVault.cachedTotalAssets(),
            cachedTotalAssetsBefore,
            "cachedTotalAssets unchanged after donation"
        );

        // Step 4: Add new fixed strategy to the vault
        ERC4626StrategyMock newFixedStrategy = new ERC4626StrategyMock(address(asset));
        vm.label(address(newFixedStrategy), "newFixedStrategy");

        vm.prank(strategyOperator);
        concreteStandardVault.addStrategy(address(newFixedStrategy));

        // Verify new strategy is added and active with zero allocation
        IConcreteStandardVaultImpl.StrategyData memory strategyData =
            concreteStandardVault.getStrategyData(address(newFixedStrategy));
        assertEq(uint256(strategyData.status), uint256(IConcreteStandardVaultImpl.StrategyStatus.Active));
        assertEq(strategyData.allocated, 0, "New strategy starts with zero allocation");

        // Step 5: Allocate to the new strategy (amount equal to the old removed one)
        _allocateToStrategy(address(newFixedStrategy), allocationAmount);

        // Verify totalAssets unchanged after allocation to new strategy
        assertEq(concreteStandardVault.totalAssets(), totalAssetsBefore, "totalAssets unchanged after new allocation");
        assertEq(
            concreteStandardVault.cachedTotalAssets(),
            cachedTotalAssetsBefore,
            "cachedTotalAssets unchanged after new allocation"
        );

        // Verify new strategy has the same allocation as the old one
        assertEq(
            concreteStandardVault.getStrategyData(address(newFixedStrategy)).allocated,
            allocationAmount,
            "New strategy allocation equals old strategy allocation"
        );
        assertEq(
            newFixedStrategy.totalAllocatedValue(), allocationAmount, "New strategy actual value equals old allocation"
        );

        // Final verification: old strategy still has zero allocation
        assertEq(haltedStrategy.totalAllocatedValue(), 0, "Old strategy still has zero allocated value");
    }

    function testCannotRemoveActiveStrategyWithAllocatedFunds() public {
        // Setup: Deposit and allocate to strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _allocateToStrategy(address(activeStrategy), 400e18);

        // Should NOT be able to remove active strategy with allocated funds
        vm.prank(strategyOperator);
        vm.expectRevert();
        concreteStandardVault.removeStrategy(address(activeStrategy));
    }

    function testRemoveActiveStrategyWithZeroAllocation() public {
        // Strategy with no allocation should be removable regardless of status
        // First, remove strategy3 from deallocation order
        address[] memory currentOrder = concreteStandardVault.getDeallocationOrder();
        address[] memory newOrder = new address[](currentOrder.length - 1);
        uint256 newIndex = 0;

        for (uint256 i = 0; i < currentOrder.length; i++) {
            if (currentOrder[i] != address(strategy3)) {
                newOrder[newIndex] = currentOrder[i];
                newIndex++;
            }
        }

        vm.prank(allocator);
        concreteStandardVault.setDeallocationOrder(newOrder);

        // Now remove the strategy
        vm.prank(strategyOperator);
        concreteStandardVault.removeStrategy(address(strategy3));

        // Verify strategy was removed
        address[] memory strategies = concreteStandardVault.getStrategies();
        for (uint256 i = 0; i < strategies.length; i++) {
            assertTrue(strategies[i] != address(strategy3));
        }
    }

    function testHaltedStrategySkipsAllocationAndWithdrawal() public {
        // Setup: Deposit funds and allocate to active strategy
        _depositAsUser(user1, INITIAL_DEPOSIT);
        _depositAsUser(user2, INITIAL_DEPOSIT);

        _allocateToStrategy(address(activeStrategy), 800e18);
        _allocateToStrategy(address(haltedStrategy), 800e18);

        // Halt one strategy
        vm.prank(strategyOperator);
        concreteStandardVault.toggleStrategyStatus(address(haltedStrategy));

        // Allocate remaining idle funds to test strategy selection
        _allocateToStrategy(address(strategy3), 400e18);

        // Calculate max withdrawable (should only consider active strategies)
        uint256 maxWithdrawable = concreteStandardVault.maxWithdraw(user1);

        // Withdraw the maximum available (should skip halted strategy)
        vm.prank(user1);
        concreteStandardVault.withdraw(maxWithdrawable, user1, user1);

        // Verify halted strategy was not touched
        assertEq(haltedStrategy.totalAllocatedValue(), 800e18);

        // Verify active strategies were used
        assertTrue(activeStrategy.totalAllocatedValue() < 800e18 || strategy3.totalAllocatedValue() < 400e18);
    }

    function testMultipleStrategyStatusToggles() public {
        // Test multiple toggles work correctly
        address[] memory strategiesToToggle = new address[](2);
        strategiesToToggle[0] = address(activeStrategy);
        strategiesToToggle[1] = address(haltedStrategy);

        vm.startPrank(strategyOperator);

        // Toggle both strategies to Halted
        for (uint256 i = 0; i < strategiesToToggle.length; i++) {
            concreteStandardVault.toggleStrategyStatus(strategiesToToggle[i]);

            IConcreteStandardVaultImpl.StrategyData memory data =
                concreteStandardVault.getStrategyData(strategiesToToggle[i]);
            assertEq(uint256(data.status), uint256(IConcreteStandardVaultImpl.StrategyStatus.Halted));
        }

        // Toggle both strategies back to Active
        for (uint256 i = 0; i < strategiesToToggle.length; i++) {
            concreteStandardVault.toggleStrategyStatus(strategiesToToggle[i]);

            IConcreteStandardVaultImpl.StrategyData memory data =
                concreteStandardVault.getStrategyData(strategiesToToggle[i]);
            assertEq(uint256(data.status), uint256(IConcreteStandardVaultImpl.StrategyStatus.Active));
        }

        vm.stopPrank();
    }

    // Helper functions

    function _getActualYield(address strategy) internal view returns (uint256) {
        uint256 currentValue = ERC4626StrategyMock(strategy).totalAllocatedValue();
        uint256 allocatedAmount = concreteStandardVault.getStrategyData(strategy).allocated;
        return currentValue > allocatedAmount ? currentValue - allocatedAmount : 0;
    }

    function _depositAsUser(address user, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(address(concreteStandardVault), amount);
        concreteStandardVault.deposit(amount, user);
        vm.stopPrank();
    }

    function _allocateToStrategy(address strategy, uint256 amount) internal {
        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] = IAllocateModule.AllocateParams({strategy: strategy, isDeposit: true, extraData: abi.encode(amount)});

        bytes memory allocateData = abi.encode(params);

        vm.prank(allocator);
        concreteStandardVault.allocate(allocateData);
    }
}
