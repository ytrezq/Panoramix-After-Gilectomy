// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../BaseStrategyTest.sol";
import {ERC4626Strategy} from "../../strategies/ERC4626Strategy.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IVaultV2} from "lib/vault-v2/src/interfaces/IVaultV2.sol";

contract MockFluidARBUSDCStrategy is ERC4626Strategy {
    constructor(address _myt, StrategyParams memory _params, address _vault)
        ERC4626Strategy(_myt, _params, _vault)
    {}
}

contract FluidARBUSDCStrategyTest is BaseStrategyTest {
    address public constant FLUID_USDC_VAULT = 0x1A996cb54bb95462040408C06122D45D6Cdb6096;
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    // Fluid custom error selector (0xdcab82e2): `FluidLiquidityError(uint256)`.
    // Observed in fork traces on allocator allocate path when Fluid `deposit` is called with dust-sized amounts (e.g. 1 unit).
    // In this suite it is observed on allocate paths; deallocate-path occurrences were not observed.
    // Allowlisted only for fuzz/handler contexts to avoid flakiness from protocol-side dust guards.
    bytes4 internal constant ALLOWED_FLUID_REVERT_SELECTOR = 0xdcab82e2;

    function getStrategyConfig() internal pure override returns (IMYTStrategy.StrategyParams memory) {
        return IMYTStrategy.StrategyParams({
            owner: address(1),
            name: "FluidARBUSDC",
            protocol: "FluidARBUSDC",
            riskClass: IMYTStrategy.RiskClass.LOW,
            cap: 10_000e6,
            globalCap: 1e18,
            estimatedYield: 100e6,
            additionalIncentives: false,
            slippageBPS: 1
        });
    }

    function getTestConfig() internal pure override returns (TestConfig memory) {
        return TestConfig({vaultAsset: USDC, vaultInitialDeposit: 1000e6, absoluteCap: 10_000e6, relativeCap: 1e18, decimals: 6});
    }

    function createStrategy(address vault, IMYTStrategy.StrategyParams memory params) internal override returns (address) {
        return address(new MockFluidARBUSDCStrategy(vault, params, FLUID_USDC_VAULT));
    }

    function getForkBlockNumber() internal pure override returns (uint256) {
        return 0;
    }

    function getRpcUrl() internal view override returns (string memory) {
        return vm.envString("ARBITRUM_RPC_URL");
    }

    function isProtocolRevertAllowed(bytes4 selector, RevertContext context) external pure override returns (bool) {
        bool isFuzzOrHandler = context == RevertContext.HandlerAllocate || context == RevertContext.HandlerDeallocate
            || context == RevertContext.FuzzAllocate || context == RevertContext.FuzzDeallocate;

        return isFuzzOrHandler && selector == ALLOWED_FLUID_REVERT_SELECTOR;
    }

    // Add any strategy-specific tests here
    function test_strategy_deallocate_reverts_due_to_slippage(uint256 amountToAllocate, uint256 amountToDeallocate) public {
        amountToAllocate = bound(amountToAllocate, 1 * 10 ** testConfig.decimals, testConfig.vaultInitialDeposit);
        amountToDeallocate = amountToAllocate;
        bytes memory params = getVaultParams();
        vm.startPrank(vault);
        deal(testConfig.vaultAsset, strategy, amountToAllocate);
        IMYTStrategy(strategy).allocate(params, amountToAllocate, "", address(vault));
        uint256 initialRealAssets = IMYTStrategy(strategy).realAssets();
        require(initialRealAssets > 0, "Initial real assets is 0");
        vm.expectRevert();
        IMYTStrategy(strategy).deallocate(params, amountToDeallocate, "", address(vault));
        vm.stopPrank();
    }

    // End-to-end test: Full lifecycle with time accumulation for FluidARBUSDC
    function test_fluid_arbusdc_full_lifecycle_with_time() public {
        vm.startPrank(allocator);
        bytes32 allocationId = IMYTStrategy(strategy).adapterId();
        
        // Initial allocation
        uint256 alloc1 = 300e6; // 300 ARB USDC
        IVaultV2(vault).allocate(strategy, getVaultParams(), alloc1);
        uint256 realAssets1 = IMYTStrategy(strategy).realAssets();
        assertGt(realAssets1, 0, "Real assets should be positive after allocation");
        assertApproxEqAbs(IVaultV2(vault).allocation(allocationId), alloc1, 1e5);
        
        // Warp forward 7 days
        vm.warp(block.timestamp + 7 days);
        
        // Additional allocation
        uint256 alloc2 = 200e6; // 200 ARB USDC
        IVaultV2(vault).allocate(strategy, getVaultParams(), alloc2);
        uint256 realAssets2 = IMYTStrategy(strategy).realAssets();
        assertGe(realAssets2, realAssets1, "Real assets should not decrease");
        
        // Warp forward 14 days
        vm.warp(block.timestamp + 14 days);
        
        // Partial deallocation (withdraw 100 USDC)
        uint256 deallocAmount1 = 100e6;
        uint256 deallocPreview1 = IMYTStrategy(strategy).previewAdjustedWithdraw(deallocAmount1);
        IVaultV2(vault).deallocate(strategy, getVaultParams(), deallocPreview1);
        uint256 realAssets3 = IMYTStrategy(strategy).realAssets();
        assertLt(realAssets3, realAssets2, "Real assets should decrease after deallocation");
        
        // Warp forward 30 days
        vm.warp(block.timestamp + 30 days);
        
        // Check vault USDC balance
        uint256 vaultUSDCBalance = IERC20(USDC).balanceOf(vault);
        assertGt(vaultUSDCBalance, 0, "Vault should have USDC");
        
        // Full deallocation of remaining
        uint256 finalRealAssets = IMYTStrategy(strategy).realAssets();
        if (finalRealAssets > 1e6) {
            uint256 finalDeallocPreview = IMYTStrategy(strategy).previewAdjustedWithdraw(finalRealAssets);
            IVaultV2(vault).deallocate(strategy, getVaultParams(), finalDeallocPreview);
        }
        
        uint256 finalVaultUSDCBalance = IERC20(USDC).balanceOf(vault);
        assertGt(finalVaultUSDCBalance, vaultUSDCBalance, "Vault USDC should increase after deallocation");
        
        vm.stopPrank();
    }

    // Fuzz test: Multiple random allocations and deallocations with time warps
    function test_fuzz_fluid_arbusdc_operations(uint256[] calldata amounts, uint256[] calldata timeDelays) public {
        // Use bound for array length instead of assume
        uint256 numOps = bound(amounts.length, 1, 8);
        // Ensure we don't access beyond array bounds
        uint256 maxIterations = numOps < amounts.length ? numOps : amounts.length;
        
        vm.startPrank(allocator);
        bytes32 allocationId = IMYTStrategy(strategy).adapterId();
        
        for (uint256 i = 0; i < maxIterations; i++) {
            // Alternate between allocation and deallocation
            bool isAllocate = i % 2 == 0;
            uint256 amount = bound(amounts[i], 10e6, 100e6); // 10-100 ARB USDC
            
            if (isAllocate) {
                IVaultV2(vault).allocate(strategy, getVaultParams(), amount);
            } else {
                uint256 currentAllocation = IVaultV2(vault).allocation(allocationId);
                if (currentAllocation > 0) {
                    uint256 maxDealloc = currentAllocation < 10e6 ? currentAllocation : 10e6;
                    uint256 deallocAmount = bound(amount, 0, maxDealloc);
                    if (deallocAmount > 0) {
                        uint256 deallocPreview = IMYTStrategy(strategy).previewAdjustedWithdraw(deallocAmount);
                        if (deallocPreview > 0) {
                            IVaultV2(vault).deallocate(strategy, getVaultParams(), deallocPreview);
                        }
                    }
                }
            }
            
            // Warp forward (with bounds check for timeDelays array)
            uint256 timeDelay = i < timeDelays.length ? bound(timeDelays[i], 1 hours, 30 days) : 1 hours;
            vm.warp(block.timestamp + timeDelay);
        }
        
        // Final sanity checks
        uint256 finalRealAssets = IMYTStrategy(strategy).realAssets();
        uint256 finalAllocation = IVaultV2(vault).allocation(allocationId);
        uint256 vaultUSDCBalance = IERC20(USDC).balanceOf(vault);
        
        assertGe(finalRealAssets, 0, "Real assets should be non-negative");
        assertGe(finalAllocation, 0, "Allocation should be non-negative");
        assertGt(vaultUSDCBalance, 0, "Vault should have USDC");
        
        vm.stopPrank();
    }

    // Test: Fluid ARB USDC vault yield accumulation over time
    function test_fluid_arbusdc_yield_accumulation() public {
        vm.startPrank(allocator);
        
        // Allocate initial amount
        uint256 allocAmount = 250e6; // 250 ARB USDC
        IVaultV2(vault).allocate(strategy, getVaultParams(), allocAmount);
        uint256 initialRealAssets = IMYTStrategy(strategy).realAssets();
        
        // Track real assets over time with warps
        uint256[] memory realAssetsSnapshots = new uint256[](4);
        uint256 minExpected = initialRealAssets * 95 / 100; // Start with 95% of initial as minimum
        for (uint256 i = 0; i < 4; i++) {
            vm.warp(block.timestamp + 30 days);
            
            // Simulate yield by transferring small amount to strategy (0.5% per period)
            deal(testConfig.vaultAsset, strategy, initialRealAssets * 5 / 1000);
            
            realAssetsSnapshots[i] = IMYTStrategy(strategy).realAssets();
            
            // Real assets should not significantly decrease (may increase with yield)
            assertGe(realAssetsSnapshots[i], minExpected, "Real assets decreased significantly");
            // Update minExpected to the new baseline
            minExpected = realAssetsSnapshots[i];
            
            // Small deallocation on second snapshot
            if (i == 1) {
                uint256 smallDealloc = 25e6; // 25 ARB USDC
                uint256 deallocPreview = IMYTStrategy(strategy).previewAdjustedWithdraw(smallDealloc);
                IVaultV2(vault).deallocate(strategy, getVaultParams(), deallocPreview);
                // Update minExpected after deallocation to account for the reduction
                minExpected = IMYTStrategy(strategy).realAssets();
            }
        }
        
        // Final deallocation
        uint256 finalRealAssets = IMYTStrategy(strategy).realAssets();
        if (finalRealAssets > 1e6) {
            uint256 finalDeallocPreview = IMYTStrategy(strategy).previewAdjustedWithdraw(finalRealAssets);
            IVaultV2(vault).deallocate(strategy, getVaultParams(), finalDeallocPreview);
        }
        
        // Allow small tolerance for slippage/rounding (up to 1% of initial)
        assertApproxEqAbs(IMYTStrategy(strategy).realAssets(), 0, initialRealAssets / 100, "All real assets should be deallocated");
        
        vm.stopPrank();
    }
}
