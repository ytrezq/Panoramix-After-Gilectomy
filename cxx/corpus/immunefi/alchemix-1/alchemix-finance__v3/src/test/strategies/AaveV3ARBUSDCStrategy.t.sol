// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../BaseStrategyTest.sol";
import {AaveStrategy} from "../../strategies/AaveStrategy.sol";
import {MYTStrategy} from "../../MYTStrategy.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IVaultV2} from "lib/vault-v2/src/interfaces/IVaultV2.sol";

/// @notice Replaces the real Aave RewardsController via vm.etch so that
///         claimAllRewardsToSelf actually transfers reward tokens to the caller.
contract MockRewardsController {
    IERC20 public immutable rewardToken;
    uint256 public immutable rewardAmount;

    constructor(address _rewardToken, uint256 _rewardAmount) {
        rewardToken = IERC20(_rewardToken);
        rewardAmount = _rewardAmount;
    }

    function claimAllRewardsToSelf(address[] calldata)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts)
    {
        rewardToken.transfer(msg.sender, rewardAmount);
        rewardsList = new address[](1);
        rewardsList[0] = address(rewardToken);
        claimedAmounts = new uint256[](1);
        claimedAmounts[0] = rewardAmount;
    }
}

/// @notice When used as allowanceHolder, transfers a fixed amount of token to msg.sender on any call (simulates swap output).
contract MockSwapExecutor {
    IERC20 public immutable token;
    uint256 public amountToTransfer;

    constructor(address _token, uint256 _amountToTransfer) {
        token = IERC20(_token);
        amountToTransfer = _amountToTransfer;
    }

    receive() external payable {}

    fallback() external {
        token.transfer(msg.sender, amountToTransfer);
    }
}

contract AaveV3ARBUSDCStrategyTest is BaseStrategyTest {
    address public constant AAVE_V3_USDC_ATOKEN = 0x724dc807b04555b71ed48a6896b6F41593b8C637;
    address public constant AAVE_V3_USDC_POOL = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address public constant REWARDS_CONTROLLER = 0x929EC64c34a17401F460460D4B9390518E5B473e;

    function getStrategyConfig() internal pure override returns (IMYTStrategy.StrategyParams memory) {
        return IMYTStrategy.StrategyParams({
            owner: address(1),
            name: "AaveV3ARBUSDC",
            protocol: "AaveV3ARBUSDC",
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
        return address(new AaveStrategy(vault, params, USDC, AAVE_V3_USDC_ATOKEN, AAVE_V3_USDC_POOL, REWARDS_CONTROLLER, ARB));
    }

    function getForkBlockNumber() internal pure override returns (uint256) {
        return 387_030_683;
    }

    function getRpcUrl() internal view override returns (string memory) {
        return vm.envString("ARBITRUM_RPC_URL");
    }

    function _effectiveDeallocateAmount(uint256 requestedAssets) internal view override returns (uint256) {
        uint256 maxWithdrawable = IMYTStrategy(strategy).realAssets();
        uint256 minMeaningfulDeallocate = 1 * 10 ** testConfig.decimals;
        if (maxWithdrawable < minMeaningfulDeallocate || requestedAssets < minMeaningfulDeallocate) {
            return 0;
        }

        return requestedAssets < maxWithdrawable ? requestedAssets : maxWithdrawable;
    }

    function isProtocolRevertAllowed(bytes4 selector, RevertContext context) external pure override returns (bool) {
        bool isFuzzOrHandler = context == RevertContext.HandlerAllocate || context == RevertContext.HandlerDeallocate
            || context == RevertContext.FuzzAllocate || context == RevertContext.FuzzDeallocate;

        return false;
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


    function test_claimRewards_emits_event_and_vault_receives_asset() public {
        // Allocate assets to create an Aave position
        bytes memory params = getVaultParams();
        uint256 amountToAllocate = 1000e6;
        deal(testConfig.vaultAsset, strategy, amountToAllocate);
        vm.prank(vault);
        IMYTStrategy(strategy).allocate(params, amountToAllocate, "", address(vault));

        // Configure mock reward claim
        uint256 arbRewardAmount = 10e18; // 10 ARB tokens claimed
        uint256 mockSwapReturn = 15e6;   // Simulated swap output

        // Deploy a MockRewardsController and etch its bytecode over the real
        // rewards controller address so claimAllRewardsToSelf actually transfers ARB.
        MockRewardsController mockRC = new MockRewardsController(ARB, arbRewardAmount);
        vm.etch(REWARDS_CONTROLLER, address(mockRC).code);
        deal(ARB, REWARDS_CONTROLLER, arbRewardAmount);

        // Setup MockSwapExecutor as allowanceHolder to simulate DEX swap.
        // Swap output should be measured in vault asset terms (USDC).
        // NOTE: quote must be non-empty so the call hits fallback() not receive().
        MockSwapExecutor mockSwap = new MockSwapExecutor(USDC, mockSwapReturn);
        deal(USDC, address(mockSwap), mockSwapReturn);

        // Point the strategy's allowanceHolder to our mock
        vm.prank(address(1)); // strategy owner
        MYTStrategy(strategy).setAllowanceHolder(address(mockSwap));

        // Record vault USDC balance before claiming
        uint256 vaultBalanceBefore = IERC20(USDC).balanceOf(vault);

        // Expect the RewardsClaimed event with correct token and amount
        vm.expectEmit(true, true, false, true, strategy);
        emit IMYTStrategy.RewardsClaimed(ARB, arbRewardAmount);

        // Execute claimRewards as strategy owner
        // Pass non-empty quote bytes so allowanceHolder.call(quote) routes to
        // MockSwapExecutor.fallback() (which transfers USDC) instead of receive().
        bytes memory quote = hex"01";
        vm.prank(address(1));
        uint256 received = IMYTStrategy(strategy).claimRewards(AAVE_V3_USDC_ATOKEN, quote, 4.99e6);

        // Verify rewards were received and vault got the asset
        uint256 vaultBalanceAfter = IERC20(USDC).balanceOf(vault);
        uint256 vaultAssetReceived = vaultBalanceAfter - vaultBalanceBefore;
        assertGt(received, 0, "No rewards received from claim");
        assertEq(vaultAssetReceived, mockSwapReturn, "Vault did not receive expected USDC amount");
        assertEq(received, vaultAssetReceived, "Returned amount is not in vault asset terms");
    }

    // Test: Aave v3 ARB USDC vault yield accumulation over time
    function test_aave_v3_arbusdc_yield_accumulation() public {
        vm.startPrank(allocator);
        
        // Allocate initial amount
        uint256 allocAmount = 500e6; // 500 ARB USDC
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
                uint256 smallDealloc = 50e6; // 50 ARB USDC
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
