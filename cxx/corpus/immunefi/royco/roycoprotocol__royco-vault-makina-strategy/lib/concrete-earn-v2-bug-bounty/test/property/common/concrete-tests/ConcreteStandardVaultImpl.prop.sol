// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../a16z-erc4626-tests/ERC4626.prop.sol";
import {IConcreteStandardVaultImpl} from "../../../../src/interface/IConcreteStandardVaultImpl.sol";
import {IAllocateModule} from "../../../../src/interface/IAllocateModule.sol";
import {ERC4626StrategyMock} from "../../../mock/ERC4626StrategyMock.sol";
import {ERC20Mock} from "../../../mock/ERC20Mock.sol";

/**
 * @title ConcreteStandardVaultImpl Property Tests
 * @dev Property tests for multi-strategy vault implementation that builds on top of A16Z ERC4626 properties
 *
 * This contract extends the base ERC4626 property tests to verify that ERC4626 compliance is maintained
 * when funds are allocated to strategies, strategies are rebalanced, and yields are accrued.
 *
 * Key differences from base ERC4626 tests:
 * - Tests ERC4626 compliance with active strategy allocation
 * - Verifies round-trip properties work with strategy rebalancing
 * - Tests preview function accuracy during strategy operations
 * - Validates total assets calculation with strategy yields/losses
 */
abstract contract ConcreteStandardVaultImplProp is ERC4626Prop {
    //
    // Enhanced Multi-Strategy Property Tests
    //

    /**
     * @dev Property: Round-trip deposit-redeem should work even with strategy rebalancing
     * Tests that users can deposit and redeem the same amount even after strategy rebalancing occurs
     */
    function prop_RT_deposit_redeem_withRebalancing(address caller, uint256 assets) public {
        vm.prank(caller);
        uint256 shares = IERC4626(_vault_).deposit(assets, caller);

        // First allocate deposited funds to strategies, then rebalance
        _performStrategyAllocation();
        _simulateStrategyRebalancing();

        vm.prank(caller);
        uint256 assetsRedeemed = IERC4626(_vault_).redeem(shares, caller, caller);

        // Should get back approximately same assets (within strategy operation tolerance)
        assertApproxGeAbs(assetsRedeemed, assets, _delta_);
    }

    /**
     * @dev Property: Round-trip deposit-withdraw should work even with strategy rebalancing
     * Tests that deposit followed by withdraw maintains consistency during strategy operations
     */
    function prop_RT_deposit_withdraw_withRebalancing(address caller, uint256 assets) public {
        vm.prank(caller);
        uint256 shares = IERC4626(_vault_).deposit(assets, caller);

        // First allocate deposited funds to strategies, then rebalance
        _performStrategyAllocation();
        _simulateStrategyRebalancing();

        vm.prank(caller);
        uint256 sharesRedeemed = IERC4626(_vault_).withdraw(assets, caller, caller);

        // Should redeem approximately same shares (within tolerance)
        assertApproxGeAbs(sharesRedeemed, shares, _delta_);
    }

    /**
     * @dev Property: Preview functions should remain accurate after strategy allocation
     * Tests that previewDeposit remains consistent before and after strategy allocation
     */
    function prop_previewDeposit_withStrategyAllocation(address caller, uint256 assets) public {
        // Get preview before any strategy operations
        vm.prank(caller);
        uint256 expectedShares = IERC4626(_vault_).previewDeposit(assets);

        // Perform strategy allocation (if vault has funds)
        _performStrategyAllocation();

        // Preview should still be accurate
        vm.prank(caller);
        uint256 actualShares = IERC4626(_vault_).deposit(assets, caller);

        assertApproxEqAbs(actualShares, expectedShares, _delta_);
    }

    /**
     * @dev Property: Preview functions should remain accurate after strategy yield
     * Tests that previewRedeem accounts for yield increases appropriately
     */
    function prop_previewRedeem_afterStrategyYield(address caller, uint256 shares) public {
        // Get preview before yield
        vm.prank(caller);
        uint256 expectedAssets = IERC4626(_vault_).previewRedeem(shares);

        // Simulate strategy yield and accrue yield
        _simulateAndAccrueYield();

        vm.prank(caller);
        uint256 actualAssets = IERC4626(_vault_).redeem(shares, caller, caller);

        // Assets should be at least as much as previewed (yield should increase value)
        assertGe(actualAssets, expectedAssets);
    }

    /**
     * @dev Property: maxWithdraw should account for strategy liquidity constraints
     * Tests that maxWithdraw respects both user balance and strategy liquidity limits
     */
    function prop_maxWithdraw_withStrategyConstraints(address caller, address owner) public {
        vm.prank(caller);
        uint256 maxWithdrawable = IERC4626(_vault_).maxWithdraw(owner);

        if (maxWithdrawable > 0) {
            // Should be able to withdraw the max amount
            vm.prank(caller);
            IERC4626(_vault_).withdraw(maxWithdrawable, caller, owner);
        }
    }

    /**
     * @dev Property: totalAssets should reflect strategy allocations accurately
     * Tests that totalAssets remains consistent after strategy allocation and yield accrual
     */
    function prop_totalAssets_reflectsStrategyAllocations(address caller) public {
        vm.prank(caller);
        uint256 totalAssetsBefore = IERC4626(_vault_).totalAssets();

        // Perform allocation and yield accrual
        _performStrategyAllocation();
        IConcreteStandardVaultImpl(_vault_).accrueYield();

        vm.prank(caller);
        uint256 totalAssetsAfter = IERC4626(_vault_).totalAssets();

        // Should remain consistent (within strategy operation costs)
        assertApproxEqAbs(totalAssetsAfter, totalAssetsBefore, _delta_);
    }

    //
    // Strategy Operation Helpers
    //

    /**
     * @dev Simulate strategy rebalancing by moving funds between strategies
     */
    function _simulateStrategyRebalancing() internal {
        address[] memory strategies = IConcreteStandardVaultImpl(_vault_).getStrategies();
        if (strategies.length < 2) return; // Need at least 2 strategies to rebalance

        uint256 totalVaultAssets = IERC4626(_vault_).totalAssets();
        if (totalVaultAssets == 0) return;

        // Get current allocations
        uint256[] memory allocations = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            IConcreteStandardVaultImpl.StrategyData memory data =
                IConcreteStandardVaultImpl(_vault_).getStrategyData(strategies[i]);
            allocations[i] = data.allocated;
        }

        uint256 totalAllocated = IConcreteStandardVaultImpl(_vault_).getTotalAllocated();
        if (totalAllocated == 0) return; // No funds allocated to rebalance

        // Simple rebalancing: move 10% from first strategy to second strategy
        uint256 rebalanceAmount = allocations[0] / 10;
        if (rebalanceAmount > 0 && rebalanceAmount <= type(uint120).max) {
            // Create combined params array for atomic rebalancing
            IAllocateModule.AllocateParams[] memory rebalanceParams = new IAllocateModule.AllocateParams[](2);
            rebalanceParams[0] = IAllocateModule.AllocateParams({
                strategy: strategies[0], isDeposit: false, extraData: abi.encode(rebalanceAmount)
            });
            rebalanceParams[1] = IAllocateModule.AllocateParams({
                strategy: strategies[1], isDeposit: true, extraData: abi.encode(rebalanceAmount)
            });

            vm.prank(_getAllocator());
            IConcreteStandardVaultImpl(_vault_).allocate(abi.encode(rebalanceParams));
        }
    }

    /**
     * @dev Perform strategy allocation if vault has unallocated funds
     */
    function _performStrategyAllocation() internal {
        address[] memory strategies = IConcreteStandardVaultImpl(_vault_).getStrategies();
        if (strategies.length == 0) return;

        uint256 idleFunds = IERC20(_underlying_).balanceOf(_vault_);
        if (idleFunds == 0 || idleFunds > type(uint120).max) return;

        // Allocate 50% of idle funds to first strategy
        uint256 allocateAmount = idleFunds / 2;
        if (allocateAmount > 0) {
            _allocateToStrategy(strategies[0], allocateAmount);
        }
    }

    /**
     * @dev Simulate yield generation and accrue yield
     */
    function _simulateAndAccrueYield() internal {
        address[] memory strategies = IConcreteStandardVaultImpl(_vault_).getStrategies();

        // Apply yield to strategies with allocations
        for (uint256 i = 0; i < strategies.length; i++) {
            IConcreteStandardVaultImpl.StrategyData memory data =
                IConcreteStandardVaultImpl(_vault_).getStrategyData(strategies[i]);

            if (data.allocated > 0 && data.allocated <= type(uint120).max) {
                // Generate 5% yield
                uint256 yieldAmount = data.allocated * 5 / 100;
                if (yieldAmount > 0 && yieldAmount <= type(uint120).max) {
                    ERC20Mock(_underlying_).mint(address(this), yieldAmount);
                    IERC20(_underlying_).approve(strategies[i], yieldAmount);
                    ERC4626StrategyMock(strategies[i]).simulateYield(yieldAmount);
                }
            }
        }

        // Accrue the yield
        IConcreteStandardVaultImpl(_vault_).accrueYield();
    }

    /**
     * @dev Ensure vault has funds allocated to strategies for yield/loss tests
     * Assumes vault already has funds from previous deposits
     */
    function _ensureAllocatedStrategiesForYieldTest() internal {
        uint256 vaultBalance = IERC20(_underlying_).balanceOf(_vault_);
        address[] memory strategies = IConcreteStandardVaultImpl(_vault_).getStrategies();

        // If vault has idle funds and strategies exist, allocate some funds
        if (vaultBalance > 0 && strategies.length > 0) {
            // Check if any strategy has allocations
            bool hasAllocations = false;
            for (uint256 i = 0; i < strategies.length; i++) {
                IConcreteStandardVaultImpl.StrategyData memory data =
                    IConcreteStandardVaultImpl(_vault_).getStrategyData(strategies[i]);
                if (data.allocated > 0) {
                    hasAllocations = true;
                    break;
                }
            }

            // If no allocations, allocate 50% of idle funds (respecting uint120 limit)
            if (!hasAllocations) {
                uint256 allocateAmount = vaultBalance / 2;
                if (allocateAmount > type(uint120).max) allocateAmount = type(uint120).max;
                if (allocateAmount > 0) {
                    _allocateToStrategy(strategies[0], allocateAmount);
                }
            }
        }
    }

    /**
     * @dev Helper function to allocate funds to a strategy
     * @param strategy The strategy address to allocate to
     * @param amount The amount to allocate
     */
    function _allocateToStrategy(address strategy, uint256 amount) internal {
        if (amount == 0 || amount > type(uint120).max) return; // StrategyData.allocated is uint120

        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] = IAllocateModule.AllocateParams({strategy: strategy, isDeposit: true, extraData: abi.encode(amount)});

        bytes memory allocateData = abi.encode(params);

        vm.prank(_getAllocator());
        IConcreteStandardVaultImpl(_vault_).allocate(allocateData);
    }

    /**
     * @dev Get the allocator address for the vault
     * Must be implemented by concrete test contracts
     */
    function _getAllocator() internal view virtual returns (address);
}
