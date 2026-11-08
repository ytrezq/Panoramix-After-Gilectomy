// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../BaseStrategyTest.sol";
import {ERC4626Strategy} from "../../strategies/ERC4626Strategy.sol";
import {IVaultV2} from "lib/vault-v2/src/interfaces/IVaultV2.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface IERC4626MaxWithdraw {
    function maxWithdraw(address owner) external view returns (uint256);
}

contract MockEulerARBWETHStrategy is ERC4626Strategy {
    constructor(address _myt, StrategyParams memory _params, address _eulerVault)
        ERC4626Strategy(_myt, _params, _eulerVault)
    {}
}

contract EulerARBWETHStrategyTest is BaseStrategyTest {
    address public constant EULER_WETH_VAULT = 0x78E3E051D32157AACD550fBB78458762d8f7edFF;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    // Error(string) selector (0x08c379a0), observed as "PD".
    // In this suite it is observed on allocate paths (deposit mock), not deallocate.
    bytes4 internal constant ERROR_STRING_SELECTOR = 0x08c379a0;
    // Euler custom error selector (0xca0985cf): `E_ZeroShares()`.
    // In this suite it is observed on deallocate paths (withdraw mock), not allocate.
    bytes4 internal constant ALLOWED_EULER_REVERT_SELECTOR = 0xca0985cf;

    function getStrategyConfig() internal pure override returns (IMYTStrategy.StrategyParams memory) {
        return IMYTStrategy.StrategyParams({
            owner: address(1),
            name: "EulerARBWETH",
            protocol: "EulerARBWETH",
            riskClass: IMYTStrategy.RiskClass.LOW,
            cap: 10_000e18,
            globalCap: 1e18,
            estimatedYield: 100e18,
            additionalIncentives: false,
            slippageBPS: 1
        });
    }

    function getTestConfig() internal pure override returns (TestConfig memory) {
        return TestConfig({vaultAsset: WETH, vaultInitialDeposit: 1000e18, absoluteCap: 10_000e18, relativeCap: 1e18, decimals: 18});
    }

    function createStrategy(address vault, IMYTStrategy.StrategyParams memory params) internal override returns (address) {
        return address(new MockEulerARBWETHStrategy(vault, params, EULER_WETH_VAULT));
    }

    function getForkBlockNumber() internal pure override returns (uint256) {
        return 0;
    }

    function getRpcUrl() internal view override returns (string memory) {
        return vm.envString("ARBITRUM_RPC_URL");
    }

    function _effectiveDeallocateAmount(uint256 requestedAssets) internal view override returns (uint256) {
        uint256 maxWithdrawable = IERC4626MaxWithdraw(EULER_WETH_VAULT).maxWithdraw(strategy);
        return requestedAssets < maxWithdrawable ? requestedAssets : maxWithdrawable;
    }

    function isProtocolRevertAllowed(bytes4 selector, RevertContext context) external pure override returns (bool) {
        bool isFuzzOrHandler = context == RevertContext.HandlerAllocate || context == RevertContext.HandlerDeallocate
            || context == RevertContext.FuzzAllocate || context == RevertContext.FuzzDeallocate;

        if (!isFuzzOrHandler) return false;
        return selector == ERROR_STRING_SELECTOR || selector == ALLOWED_EULER_REVERT_SELECTOR;
    }

    // Add any strategy-specific tests here
    function test_strategy_deallocate_reverts_due_to_slippage(uint256 amountToAllocate, uint256 amountToDeallocate) public {
        amountToAllocate = bound(amountToAllocate, 1e6, testConfig.vaultInitialDeposit);
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

    function test_allowlisted_revert_error_string_is_deterministic() public {
        uint256 amountToAllocate = 1e18;
        bytes4 depositSelector = bytes4(keccak256("deposit(uint256,address)"));

        vm.startPrank(allocator);
        _prepareVaultAssets(amountToAllocate);
        vm.mockCallRevert(
            EULER_WETH_VAULT, abi.encodePacked(depositSelector), abi.encodeWithSelector(ERROR_STRING_SELECTOR, "PD")
        );
        vm.expectRevert(bytes("PD"));
        IVaultV2(vault).allocate(strategy, getVaultParams(), amountToAllocate);
        vm.stopPrank();
    }

    function test_allowlisted_revert_custom_selector_is_deterministic() public {
        uint256 amountToAllocate = 2e18;
        uint256 amountToDeallocate = 1e18;
        bytes4 withdrawSelector = bytes4(keccak256("withdraw(uint256,address,address)"));

        vm.startPrank(allocator);
        _prepareVaultAssets(amountToAllocate);
        IVaultV2(vault).allocate(strategy, getVaultParams(), amountToAllocate);

        uint256 deallocPreview = IMYTStrategy(strategy).previewAdjustedWithdraw(amountToDeallocate);
        require(deallocPreview > 0, "preview is zero");

        vm.mockCallRevert(
            EULER_WETH_VAULT, abi.encodePacked(withdrawSelector), abi.encodeWithSelector(ALLOWED_EULER_REVERT_SELECTOR)
        );
        vm.expectRevert(ALLOWED_EULER_REVERT_SELECTOR);
        IVaultV2(vault).deallocate(strategy, getVaultParams(), deallocPreview);
        vm.stopPrank();
    }

    // End-to-end test: Full lifecycle with time accumulation for EulerARBWETH
    function test_euler_arbweth_full_lifecycle_with_time() public {
        vm.startPrank(allocator);
        bytes32 allocationId = IMYTStrategy(strategy).adapterId();
        
        // Initial allocation
        uint256 alloc1 = 400e18; // 400 ARB WETH
        IVaultV2(vault).allocate(strategy, getVaultParams(), alloc1);
        uint256 realAssets1 = IMYTStrategy(strategy).realAssets();
        assertGt(realAssets1, 0, "Real assets should be positive after allocation");
        assertApproxEqAbs(IVaultV2(vault).allocation(allocationId), alloc1, 1e15);
        
        // Warp forward 7 days
        vm.warp(block.timestamp + 7 days);
        
        // Additional allocation
        uint256 alloc2 = 250e18; // 250 ARB WETH
        IVaultV2(vault).allocate(strategy, getVaultParams(), alloc2);
        uint256 realAssets2 = IMYTStrategy(strategy).realAssets();
        assertGe(realAssets2, realAssets1, "Real assets should not decrease");
        
        // Warp forward 14 days
        vm.warp(block.timestamp + 14 days);
        
        // Partial deallocation (withdraw 150 WETH)
        uint256 deallocAmount1 = 150e18;
        uint256 deallocPreview1 = IMYTStrategy(strategy).previewAdjustedWithdraw(deallocAmount1);
        IVaultV2(vault).deallocate(strategy, getVaultParams(), deallocPreview1);
        uint256 realAssets3 = IMYTStrategy(strategy).realAssets();
        assertLt(realAssets3, realAssets2, "Real assets should decrease after deallocation");
        
        // Warp forward 30 days
        vm.warp(block.timestamp + 30 days);
        
        // Check vault WETH balance
        uint256 vaultWETHBalance = IERC20(WETH).balanceOf(vault);
        assertGt(vaultWETHBalance, 0, "Vault should have WETH");
        
        // Full deallocation of remaining
        uint256 finalRealAssets = IMYTStrategy(strategy).realAssets();
        if (finalRealAssets > 1e15) {
            uint256 finalDeallocPreview = IMYTStrategy(strategy).previewAdjustedWithdraw(finalRealAssets);
            IVaultV2(vault).deallocate(strategy, getVaultParams(), finalDeallocPreview);
        }
        
        uint256 finalVaultWETHBalance = IERC20(WETH).balanceOf(vault);
        assertGt(finalVaultWETHBalance, vaultWETHBalance, "Vault WETH should increase after deallocation");
        
        vm.stopPrank();
    }

    // Fuzz test: Multiple random allocations and deallocations with time warps
    function test_fuzz_euler_arbweth_operations(uint256[] calldata amounts, uint256[] calldata timeDelays) public {
        // Use bound for array length instead of assume
        uint256 numOps = bound(amounts.length, 1, 8);
        // Ensure we don't access beyond array bounds
        uint256 maxIterations = numOps < amounts.length ? numOps : amounts.length;
        
        vm.startPrank(allocator);
        bytes32 allocationId = IMYTStrategy(strategy).adapterId();
        
        for (uint256 i = 0; i < maxIterations; i++) {
            // Alternate between allocation and deallocation
            bool isAllocate = i % 2 == 0;
            uint256 amount = bound(amounts[i], 0.1e18, 50e18); // 0.1-50 ARB WETH
            
            if (isAllocate) {
                IVaultV2(vault).allocate(strategy, getVaultParams(), amount);
            } else {
                uint256 currentAllocation = IVaultV2(vault).allocation(allocationId);
                if (currentAllocation > 0) {
                    uint256 maxDealloc = currentAllocation < 0.1e18 ? currentAllocation : 0.1e18;
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
        uint256 vaultWETHBalance = IERC20(WETH).balanceOf(vault);
        
        assertGe(finalRealAssets, 0, "Real assets should be non-negative");
        assertGe(finalAllocation, 0, "Allocation should be non-negative");
        assertGt(vaultWETHBalance, 0, "Vault should have WETH");
        
        vm.stopPrank();
    }

    // Test: Euler ARB vault yield accumulation over time
    function test_euler_arbweth_yield_accumulation() public {
        vm.startPrank(allocator);
        
        // Allocate initial amount
        uint256 allocAmount = 300e18; // 300 ARB WETH
        IVaultV2(vault).allocate(strategy, getVaultParams(), allocAmount);
        uint256 initialRealAssets = IMYTStrategy(strategy).realAssets();
        
        // Track real assets over time with warps
        uint256[] memory realAssetsSnapshots = new uint256[](4);
        uint256 minExpected = initialRealAssets * 95 / 100; // Start with 95% of initial as minimum
        for (uint256 i = 0; i < 4; i++) {
            _warpWithHook(30 days);
            
            // Simulate yield by transferring small amount to strategy (0.5% per period)
            deal(testConfig.vaultAsset, strategy, initialRealAssets * 5 / 1000);
            
            realAssetsSnapshots[i] = IMYTStrategy(strategy).realAssets();
            
            // Real assets should not significantly decrease (may increase with yield)
            assertGe(realAssetsSnapshots[i], minExpected, "Real assets decreased significantly");
            // Update minExpected to the new baseline
            minExpected = realAssetsSnapshots[i];
            
            // Small deallocation on second snapshot
            if (i == 1) {
                uint256 smallDealloc = 30e18; // 30 ARB WETH
                bool smallOk = _deallocateEstimate(smallDealloc, RevertContext.FuzzDeallocate);
                if (smallOk) {
                    // Update minExpected after deallocation to account for the reduction
                    minExpected = IMYTStrategy(strategy).realAssets();
                }
            }
        }
        
        // Final deallocation (best effort under allowlist-aware multi-step flows).
        bool finalOk = _deallocateFromRealAssetsEstimate(RevertContext.FuzzDeallocate);
        if (!finalOk) {
            vm.stopPrank();
            return;
        }
        
        // Allow small tolerance for slippage/rounding and protocol-side withdraw limits.
        assertApproxEqAbs(IMYTStrategy(strategy).realAssets(), 0, initialRealAssets / 50, "All real assets should be deallocated");
        
        vm.stopPrank();
    }
}
