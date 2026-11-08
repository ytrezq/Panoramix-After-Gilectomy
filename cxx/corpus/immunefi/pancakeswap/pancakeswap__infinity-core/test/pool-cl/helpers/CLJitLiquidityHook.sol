// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IVault} from "../../../src/interfaces/IVault.sol";
import {ILockCallback} from "../../../src/interfaces/ILockCallback.sol";
import {Hooks} from "../../../src/libraries/Hooks.sol";
import {ICLPoolManager} from "../../../src/pool-cl/interfaces/ICLPoolManager.sol";
import {PoolKey} from "../../../src/types/PoolKey.sol";
import {Currency} from "../../../src/types/Currency.sol";
import {CurrencySettlement} from "../../helpers/CurrencySettlement.sol";
import {BalanceDelta} from "../../../src/types/BalanceDelta.sol";
import {BaseCLTestHook} from "./BaseCLTestHook.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../../../src/types/BeforeSwapDelta.sol";

/// @notice A just-in-time liquidity hook: injects a fresh position in `beforeSwap` and removes
/// it in `afterSwap`, on a pool with NO resident liquidity.
///
/// The `afterSwap` removal runs BEFORE the pool manager books the swap's own delta to
/// `reservesOfApp`, so on the swap-input currency it withdraws more than is currently booked.
/// This used to revert with an arithmetic underflow; it now records a transient deficit that
/// the swap's own booking repays before the lock ends.
contract CLJitLiquidityHook is BaseCLTestHook, ILockCallback {
    using CurrencySettlement for Currency;
    using Hooks for bytes32;

    IVault public immutable vault;
    ICLPoolManager public immutable poolManager;

    int24 public tickLower;
    int24 public tickUpper;
    uint128 public liquidity;

    /// @dev the pool manager's transient deficit observed right after the afterSwap removal,
    /// recorded so tests can assert the deficit path was actually exercised
    uint256 public deficitAfterRemove0;
    uint256 public deficitAfterRemove1;

    constructor(IVault _vault, ICLPoolManager _poolManager) {
        vault = _vault;
        poolManager = _poolManager;
    }

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                befreSwapReturnsDelta: false,
                afterSwapReturnsDelta: false,
                afterAddLiquidityReturnsDelta: false,
                afterRemoveLiquidityReturnsDelta: false
            })
        );
    }

    function setJitPosition(int24 _tickLower, int24 _tickUpper, uint128 _liquidity) external {
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        liquidity = _liquidity;
    }

    /// @notice Convert `amount0`/`amount1` of the hook's ERC20 balance into vault claim tokens,
    /// so the JIT settlement inside swap callbacks never needs mid-lock ERC20 transfers
    function depositClaims(Currency currency0, Currency currency1, uint256 amount0, uint256 amount1) external {
        vault.lock(abi.encode(currency0, currency1, amount0, amount1));
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        (Currency currency0, Currency currency1, uint256 amount0, uint256 amount1) =
            abi.decode(data, (Currency, Currency, uint256, uint256));
        currency0.settle(vault, address(this), amount0, false);
        currency0.take(vault, address(this), amount0, true);
        currency1.settle(vault, address(this), amount1, false);
        currency1.take(vault, address(this), amount1, true);
        return "";
    }

    function beforeSwap(address, PoolKey calldata key, ICLPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        poolManager.modifyLiquidity(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: int256(uint256(liquidity)), salt: 0
            }),
            ""
        );
        _settleOrTake(key.currency0);
        _settleOrTake(key.currency1);
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata key, ICLPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        poolManager.modifyLiquidity(
            key,
            ICLPoolManager.ModifyLiquidityParams({
                tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: -int256(uint256(liquidity)), salt: 0
            }),
            ""
        );

        // the removal ran before the swap's own delta was booked: on the swap-input currency the
        // pool manager's reserves are transiently overdrawn — snapshot the deficit for the test
        deficitAfterRemove0 = vault.appCurrencyDeficit(address(poolManager), key.currency0);
        deficitAfterRemove1 = vault.appCurrencyDeficit(address(poolManager), key.currency1);

        _settleOrTake(key.currency0);
        _settleOrTake(key.currency1);
        return (this.afterSwap.selector, 0);
    }

    /// @dev net out this hook's own vault delta using claim tokens
    function _settleOrTake(Currency currency) internal {
        int256 delta = vault.currencyDelta(address(this), currency);
        if (delta < 0) {
            currency.settle(vault, address(this), uint256(-delta), true);
        } else if (delta > 0) {
            currency.take(vault, address(this), uint256(delta), true);
        }
    }
}
