// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../BaseStrategyTest.sol";
import {AaveStrategy} from "../../strategies/AaveStrategy.sol";
import {MYTStrategy} from "../../MYTStrategy.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IVaultV2} from "lib/vault-v2/src/interfaces/IVaultV2.sol";

interface IRewardsController {
    function claimAllRewardsToSelf(address[] calldata assets) external returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}

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

/// @notice When used as allowanceHolder, transfers a fixed amount of vault asset to msg.sender on any call (simulates swap output).
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

contract AaveV3OPUSDCStrategyTest is BaseStrategyTest {
    address public constant AAVE_V3_USDC_ATOKEN = 0x38d693cE1dF5AaDF7bC62595A37D667aD57922e5;
    address public constant AAVE_V3_USDC_POOL = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb; // pool provider to query
    address public constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address public constant OP = 0x4200000000000000000000000000000000000042;
    address public constant REWARDS_CONTROLLER = 0x929EC64c34a17401F460460D4B9390518E5B473e;
    // Aave custom error selector (0x2c5211c6): `InvalidAmount()`.
    // In this suite it is observed on deallocate paths (withdraw mock), not allocate.
    bytes4 internal constant ALLOWED_AAVE_REVERT_SELECTOR = 0x2c5211c6;

    function getStrategyConfig() internal pure override returns (IMYTStrategy.StrategyParams memory) {
        return IMYTStrategy.StrategyParams({
            owner: address(1),
            name: "AaveV3OPUSDC",
            protocol: "AaveV3OPUSDC",
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
        return address(new AaveStrategy(vault, params, USDC, AAVE_V3_USDC_ATOKEN, AAVE_V3_USDC_POOL, REWARDS_CONTROLLER, OP));
    }

    function getForkBlockNumber() internal pure override returns (uint256) {
        return 141_751_698;
    }

    function getRpcUrl() internal view override returns (string memory) {
        return vm.envString("OPTIMISM_RPC_URL");
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

        return isFuzzOrHandler && selector == ALLOWED_AAVE_REVERT_SELECTOR;
    }

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

    function test_claimRewards_succeeds() public {
        bytes memory params = getVaultParams();
        // Allocate some assets first so there are positions to claim rewards for
        uint256 amountToAllocate = 1000e6;
        deal(testConfig.vaultAsset, strategy, amountToAllocate);
        vm.prank(vault);
        IMYTStrategy(strategy).allocate(params, amountToAllocate, "", address(vault));
        
        // Claim rewards should not revert
        vm.prank(address(1));
        IMYTStrategy(strategy).claimRewards(AAVE_V3_USDC_ATOKEN, "", 0);
        vm.stopPrank();
    }

    function test_allowlisted_revert_custom_selector_is_deterministic() public {
        uint256 amountToAllocate = 100e6;
        uint256 amountToDeallocate = 50e6;
        address mockPool = address(0xBEEF);
        bytes4 getPoolSelector = bytes4(keccak256("getPool()"));
        bytes4 withdrawSelector = bytes4(keccak256("withdraw(address,uint256,address)"));

        vm.startPrank(allocator);
        _prepareVaultAssets(amountToAllocate);
        IVaultV2(vault).allocate(strategy, getVaultParams(), amountToAllocate);

        uint256 deallocPreview = IMYTStrategy(strategy).previewAdjustedWithdraw(amountToDeallocate);
        require(deallocPreview > 0, "preview is zero");

        vm.mockCall(AAVE_V3_USDC_POOL, abi.encodeWithSelector(getPoolSelector), abi.encode(mockPool));
        vm.mockCallRevert(
            mockPool, abi.encodePacked(withdrawSelector), abi.encodeWithSelector(ALLOWED_AAVE_REVERT_SELECTOR)
        );
        vm.expectRevert(ALLOWED_AAVE_REVERT_SELECTOR);
        IVaultV2(vault).deallocate(strategy, getVaultParams(), deallocPreview);
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
        uint256 opRewardAmount = 10e18; // 10 OP tokens claimed
        uint256 mockSwapReturn = 15e6;  // Simulated swap output

        // Deploy a MockRewardsController and etch its bytecode over the real
        // rewards controller address so claimAllRewardsToSelf actually transfers OP.
        MockRewardsController mockRC = new MockRewardsController(OP, opRewardAmount);
        vm.etch(REWARDS_CONTROLLER, address(mockRC).code);
        deal(OP, REWARDS_CONTROLLER, opRewardAmount);

        // Setup MockSwapExecutor as allowanceHolder to simulate DEX swap.
        // Swap output should be measured in vault asset terms (USDC).
        MockSwapExecutor mockSwap = new MockSwapExecutor(USDC, mockSwapReturn);
        deal(USDC, address(mockSwap), mockSwapReturn);

        // Point the strategy's allowanceHolder to our mock
        vm.prank(address(1)); // strategy owner
        MYTStrategy(strategy).setAllowanceHolder(address(mockSwap));

        // Record vault USDC balance before claiming
        uint256 vaultBalanceBefore = IERC20(USDC).balanceOf(vault);

        // Expect the RewardsClaimed event with correct token and amount
        vm.expectEmit(true, true, false, true, strategy);
        emit IMYTStrategy.RewardsClaimed(OP, opRewardAmount);

        // Execute claimRewards as strategy owner
        // MockSwapExecutor.fallback() transfers USDC to simulate swap output.
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
}
