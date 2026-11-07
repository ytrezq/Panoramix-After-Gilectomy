// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {ICLPoolManager} from "../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {CLPoolManager} from "../../src/pool-cl/CLPoolManager.sol";
import {Currency} from "../../src/types/Currency.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {CLPoolManagerRouter} from "./helpers/CLPoolManagerRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Deployers} from "./helpers/Deployers.sol";
import {TokenFixture} from "../helpers/TokenFixture.sol";
import {CLPoolParametersHelper} from "../../src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {TickMath} from "../../src/pool-cl/libraries/TickMath.sol";
import {CLJitLiquidityHook} from "./helpers/CLJitLiquidityHook.sol";

/// @notice End-to-end regression for the mid-lock `reservesOfApp` underflow: a hook that
/// injects liquidity in `beforeSwap` and removes it in `afterSwap`, on a pool with NO other
/// liquidity. The afterSwap removal withdraws the swap input before the pool manager books it,
/// which used to revert with an arithmetic underflow and now settles via a transient deficit.
contract CLJitLiquidityHookTest is Test, Deployers, TokenFixture {
    using CLPoolParametersHelper for bytes32;

    PoolKey key;
    IVault public vault;
    CLPoolManager public poolManager;
    CLPoolManagerRouter public router;
    CLJitLiquidityHook public jitHook;

    function setUp() public {
        initializeTokens();
        (vault, poolManager) = createFreshManager();

        router = new CLPoolManagerRouter(vault, poolManager);
        jitHook = new CLJitLiquidityHook(vault, poolManager);

        IERC20(Currency.unwrap(currency0)).approve(address(router), 1000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(router), 1000 ether);

        // fund the hook's inventory as vault claims, enough to cover its JIT injections
        MockERC20(Currency.unwrap(currency0)).transfer(address(jitHook), 100 ether);
        MockERC20(Currency.unwrap(currency1)).transfer(address(jitHook), 100 ether);
        jitHook.depositClaims(currency0, currency1, 100 ether, 100 ether);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: jitHook,
            poolManager: poolManager,
            fee: uint24(3000),
            parameters: bytes32(uint256(jitHook.getHooksRegistrationBitmap())).setTickSpacing(10)
        });
        poolManager.initialize(key, SQRT_RATIO_1_1);

        jitHook.setJitPosition(-120, 120, 1000 ether);
    }

    /// @dev The pool holds ONLY the hook's just-in-time liquidity. Before the fix this swap
    /// reverted: the afterSwap removal underflowed `reservesOfApp` on the swap-input currency.
    function test_swap_jitRemoveInAfterSwap_bufferlessPool() external {
        router.swap(
            key,
            ICLPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether, // exact-in 1 ether of currency0
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            ""
        );

        // the deficit path was actually exercised: right after the afterSwap removal the pool
        // manager's reserves were transiently overdrawn on the input currency only
        assertGt(jitHook.deficitAfterRemove0(), 0, "removal overdraws the swap-input currency mid-lock");
        assertEq(jitHook.deficitAfterRemove1(), 0, "output currency reserve never overdraws");

        // fully repaid once the swap's own delta was booked; nothing outstanding after the lock
        assertEq(vault.getAppDeficitCount(), 0, "deficit fully repaid by the swap's own booking");
        assertEq(vault.appCurrencyDeficit(address(poolManager), currency0), 0);
        assertEq(vault.appCurrencyDeficit(address(poolManager), currency1), 0);

        // the JIT position is gone, so the app's reserves are back to ~0 (mint/burn rounding dust)
        assertLe(vault.reservesOfApp(address(poolManager), currency0), 10, "only rounding dust remains");
        assertLe(vault.reservesOfApp(address(poolManager), currency1), 10, "only rounding dust remains");
    }

    /// @dev Same flow in the other direction (input = currency1) plus repeated round-trip swaps:
    /// every swap exercises the overdraw-then-repay cycle and none of them revert.
    function test_swap_jitRemoveInAfterSwap_repeated() external {
        for (uint256 i; i < 3; ++i) {
            router.swap(
                key,
                ICLPoolManager.SwapParams({
                    zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
                }),
                CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
                ""
            );
            assertGt(jitHook.deficitAfterRemove0(), 0);

            router.swap(
                key,
                ICLPoolManager.SwapParams({
                    zeroForOne: false, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1
                }),
                CLPoolManagerRouter.SwapTestSettings({withdrawTokens: true, settleUsingTransfer: true}),
                ""
            );
            assertGt(jitHook.deficitAfterRemove1(), 0);

            assertEq(vault.getAppDeficitCount(), 0);
        }
    }
}
