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

contract AaveV3ARBWETHStrategyTest is BaseStrategyTest {
    address public constant AAVE_V3_ARB_WETH_ATOKEN = 0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8;
    address public constant AAVE_V3_ARB_WETH_POOL = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address public constant REWARDS_CONTROLLER = 0x929EC64c34a17401F460460D4B9390518E5B473e;
    // Error(string) selector (0x08c379a0), observed as "PD".
    // In this suite it is observed on deallocate paths (withdraw mock), not allocate.
    bytes4 internal constant ERROR_STRING_SELECTOR = 0x08c379a0;
    // Aave custom error selector (0x2c5211c6): `InvalidAmount()`.
    // In this suite it is observed on deallocate paths (withdraw mock), not allocate.
    bytes4 internal constant ALLOWED_AAVE_REVERT_SELECTOR = 0x2c5211c6;

    function getStrategyConfig() internal pure override returns (IMYTStrategy.StrategyParams memory) {
        return IMYTStrategy.StrategyParams({
            owner: address(1),
            name: "AaveV3ARBWETH",
            protocol: "AaveV3ARBWETH",
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
        return address(
            new AaveStrategy(vault, params, WETH, AAVE_V3_ARB_WETH_ATOKEN, AAVE_V3_ARB_WETH_POOL, REWARDS_CONTROLLER, ARB)
        );
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

        if (!isFuzzOrHandler) return false;
        return selector == ALLOWED_AAVE_REVERT_SELECTOR || selector == ERROR_STRING_SELECTOR;
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

    function test_allowlisted_revert_custom_selector_is_deterministic() public {
        uint256 amountToAllocate = 1e18;
        uint256 amountToDeallocate = 5e17;
        address mockPool = address(0xBEEF);
        bytes4 getPoolSelector = bytes4(keccak256("getPool()"));
        bytes4 withdrawSelector = bytes4(keccak256("withdraw(address,uint256,address)"));

        vm.startPrank(allocator);
        _prepareVaultAssets(amountToAllocate);
        IVaultV2(vault).allocate(strategy, getVaultParams(), amountToAllocate);

        uint256 deallocPreview = IMYTStrategy(strategy).previewAdjustedWithdraw(amountToDeallocate);
        require(deallocPreview > 0, "preview is zero");

        vm.mockCall(AAVE_V3_ARB_WETH_POOL, abi.encodeWithSelector(getPoolSelector), abi.encode(mockPool));
        vm.mockCallRevert(
            mockPool, abi.encodePacked(withdrawSelector), abi.encodeWithSelector(ALLOWED_AAVE_REVERT_SELECTOR)
        );
        vm.expectRevert(ALLOWED_AAVE_REVERT_SELECTOR);
        IVaultV2(vault).deallocate(strategy, getVaultParams(), deallocPreview);
        vm.stopPrank();
    }

    function test_allowlisted_revert_error_string_is_deterministic() public {
        uint256 amountToAllocate = 1e18;
        uint256 amountToDeallocate = 5e17;
        address mockPool = address(0xBEEF);
        bytes4 getPoolSelector = bytes4(keccak256("getPool()"));
        bytes4 withdrawSelector = bytes4(keccak256("withdraw(address,uint256,address)"));

        vm.startPrank(allocator);
        _prepareVaultAssets(amountToAllocate);
        IVaultV2(vault).allocate(strategy, getVaultParams(), amountToAllocate);

        uint256 deallocPreview = IMYTStrategy(strategy).previewAdjustedWithdraw(amountToDeallocate);
        require(deallocPreview > 0, "preview is zero");

        vm.mockCall(AAVE_V3_ARB_WETH_POOL, abi.encodeWithSelector(getPoolSelector), abi.encode(mockPool));
        vm.mockCallRevert(
            mockPool, abi.encodePacked(withdrawSelector), abi.encodeWithSelector(ERROR_STRING_SELECTOR, "PD")
        );
        vm.expectRevert(bytes("PD"));
        IVaultV2(vault).deallocate(strategy, getVaultParams(), deallocPreview);
        vm.stopPrank();
    }

    function test_claimRewards_succeeds() public {
        bytes memory params = getVaultParams();
        // Allocate some assets first so there are positions to claim rewards for
        uint256 amountToAllocate = 1000e6;
        deal(testConfig.vaultAsset, strategy, amountToAllocate);
        vm.prank(vault);
        IMYTStrategy(strategy).allocate(params, amountToAllocate, "", address(vault));
        
        // Claim rewards should not revert
        vm.prank(address(1));
        IMYTStrategy(strategy).claimRewards(AAVE_V3_ARB_WETH_ATOKEN, "", 0);
        vm.stopPrank();
    }

    function test_claimRewards_emits_event_and_vault_receives_asset() public {
        // Allocate assets to create an Aave position
        bytes memory params = getVaultParams();
        uint256 amountToAllocate = 10e18;
        deal(testConfig.vaultAsset, strategy, amountToAllocate);
        vm.prank(vault);
        IMYTStrategy(strategy).allocate(params, amountToAllocate, "", address(vault));

        // Configure mock reward claim
        uint256 arbRewardAmount = 10e18;   // 10 ARB tokens claimed
        uint256 mockSwapReturn = 5e15;     // Simulated WETH swap output

        // Deploy a MockRewardsController and etch its bytecode over the real
        // rewards controller address so claimAllRewardsToSelf actually transfers ARB.
        MockRewardsController mockRC = new MockRewardsController(ARB, arbRewardAmount);
        vm.etch(REWARDS_CONTROLLER, address(mockRC).code);
        deal(ARB, REWARDS_CONTROLLER, arbRewardAmount);

        // Setup MockSwapExecutor as allowanceHolder to simulate DEX swap.
        // Swap output should be measured in vault asset terms (WETH).
        // NOTE: quote must be non-empty so the call hits fallback() not receive().
        MockSwapExecutor mockSwap = new MockSwapExecutor(WETH, mockSwapReturn);
        deal(WETH, address(mockSwap), mockSwapReturn);

        // Point the strategy's allowanceHolder to our mock
        vm.prank(address(1)); // strategy owner
        MYTStrategy(strategy).setAllowanceHolder(address(mockSwap));

        // Record vault WETH balance before claiming
        uint256 vaultBalanceBefore = IERC20(WETH).balanceOf(vault);

        // Expect the RewardsClaimed event with correct token and amount
        vm.expectEmit(true, true, false, true, strategy);
        emit IMYTStrategy.RewardsClaimed(ARB, arbRewardAmount);

        // Execute claimRewards as strategy owner
        // Pass non-empty quote bytes so allowanceHolder.call(quote) routes to
        // MockSwapExecutor.fallback() (which transfers WETH) instead of receive().
        bytes memory quote = hex"01";
        vm.prank(address(1));
        uint256 received = IMYTStrategy(strategy).claimRewards(AAVE_V3_ARB_WETH_ATOKEN, quote, 4.99e15);

        // Verify rewards were received and vault got the asset
        uint256 vaultBalanceAfter = IERC20(WETH).balanceOf(vault);
        uint256 vaultAssetReceived = vaultBalanceAfter - vaultBalanceBefore;
        assertGt(received, 0, "No rewards received from claim");
        assertEq(vaultAssetReceived, mockSwapReturn, "Vault did not receive expected WETH amount");
        assertEq(received, vaultAssetReceived, "Returned amount is not in vault asset terms");
    }

    // Test: Aave v3 ARB WETH vault yield accumulation over time
    function test_aave_v3_arbweth_yield_accumulation() public {
        vm.startPrank(allocator);
        
        // Allocate initial amount
        uint256 allocAmount = 300e18; // 300 ARB WETH
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
                uint256 smallDealloc = 30e18; // 30 ARB WETH
                uint256 deallocPreview = IMYTStrategy(strategy).previewAdjustedWithdraw(smallDealloc);
                IVaultV2(vault).deallocate(strategy, getVaultParams(), deallocPreview);
                // Update minExpected after deallocation to account for the reduction
                minExpected = IMYTStrategy(strategy).realAssets();
            }
        }
        
        // Final deallocation
        uint256 finalRealAssets = IMYTStrategy(strategy).realAssets();
        if (finalRealAssets > 1e15) {
            uint256 finalDeallocPreview = IMYTStrategy(strategy).previewAdjustedWithdraw(finalRealAssets);
            IVaultV2(vault).deallocate(strategy, getVaultParams(), finalDeallocPreview);
        }
        
        // Allow small tolerance for slippage/rounding (up to 1% of initial)
        assertApproxEqAbs(IMYTStrategy(strategy).realAssets(), 0, initialRealAssets / 100, "All real assets should be deallocated");
        
        vm.stopPrank();
    }
}
