// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../BaseStrategyTest.sol";
import {ERC4626Strategy} from "../../strategies/ERC4626Strategy.sol";
import {IVaultV2} from "lib/vault-v2/src/interfaces/IVaultV2.sol";

interface IERC4626MaxWithdraw {
    function maxWithdraw(address owner) external view returns (uint256);
}

contract MockEulerARBUSDCStrategy is ERC4626Strategy {
    constructor(address _myt, StrategyParams memory _params, address _vault)
        ERC4626Strategy(_myt, _params, _vault)
    {}
}

contract EulerARBUSDCStrategyTest is BaseStrategyTest {
    address public constant EULER_USDC_VAULT = 0x0a1eCC5Fe8C9be3C809844fcBe615B46A869b899;
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    // Error(string) selector (0x08c379a0), observed as "PD".
    // In this suite it is observed on allocate paths (deposit mock), not deallocate.
    bytes4 internal constant ERROR_STRING_SELECTOR = 0x08c379a0;
    // Euler custom error selector (0xca0985cf): `E_ZeroShares()`.
    // In this suite it is observed on deallocate paths (withdraw mock), not allocate.
    bytes4 internal constant ALLOWED_EULER_REVERT_SELECTOR = 0xca0985cf;

    function getStrategyConfig() internal pure override returns (IMYTStrategy.StrategyParams memory) {
        return IMYTStrategy.StrategyParams({
            owner: address(1),
            name: "EulerARBUSDC",
            protocol: "EulerARBUSDC",
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
        return address(new MockEulerARBUSDCStrategy(vault, params, EULER_USDC_VAULT));
    }

    function getForkBlockNumber() internal pure override returns (uint256) {
        return 0;
    }

    function getRpcUrl() internal view override returns (string memory) {
        return vm.envString("ARBITRUM_RPC_URL");
    }

    function _effectiveDeallocateAmount(uint256 requestedAssets) internal view override returns (uint256) {
        uint256 maxWithdrawable = IERC4626MaxWithdraw(EULER_USDC_VAULT).maxWithdraw(strategy);
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

    function test_allowlisted_revert_error_string_is_deterministic() public {
        uint256 amountToAllocate = 1e6;
        bytes4 depositSelector = bytes4(keccak256("deposit(uint256,address)"));

        vm.startPrank(allocator);
        _prepareVaultAssets(amountToAllocate);
        vm.mockCallRevert(
            EULER_USDC_VAULT, abi.encodePacked(depositSelector), abi.encodeWithSelector(ERROR_STRING_SELECTOR, "PD")
        );
        vm.expectRevert(bytes("PD"));
        IVaultV2(vault).allocate(strategy, getVaultParams(), amountToAllocate);
        vm.stopPrank();
    }

    function test_allowlisted_revert_custom_selector_is_deterministic() public {
        uint256 amountToAllocate = 2e6;
        uint256 amountToDeallocate = 1e6;
        bytes4 withdrawSelector = bytes4(keccak256("withdraw(uint256,address,address)"));

        vm.startPrank(allocator);
        _prepareVaultAssets(amountToAllocate);
        IVaultV2(vault).allocate(strategy, getVaultParams(), amountToAllocate);

        uint256 deallocPreview = IMYTStrategy(strategy).previewAdjustedWithdraw(amountToDeallocate);
        require(deallocPreview > 0, "preview is zero");

        vm.mockCallRevert(
            EULER_USDC_VAULT, abi.encodePacked(withdrawSelector), abi.encodeWithSelector(ALLOWED_EULER_REVERT_SELECTOR)
        );
        vm.expectRevert(ALLOWED_EULER_REVERT_SELECTOR);
        IVaultV2(vault).deallocate(strategy, getVaultParams(), deallocPreview);
        vm.stopPrank();
    }
}
