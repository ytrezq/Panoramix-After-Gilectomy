// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IVaultV2} from "lib/vault-v2/src/interfaces/IVaultV2.sol";
import {VaultV2} from "lib/vault-v2/src/VaultV2.sol";
import {AlchemistAllocator} from "../AlchemistAllocator.sol";
import {IAllocator} from "../interfaces/IAllocator.sol";
import {AlchemistStrategyClassifier} from "../AlchemistStrategyClassifier.sol";
import {MYTTestHelper} from "./libraries/MYTTestHelper.sol";
import {IMYTStrategy} from "../interfaces/IMYTStrategy.sol";
import {TokenUtils} from "../libraries/TokenUtils.sol";
import {RevertContext, IRevertAllowlistProvider} from "./base/StrategyTypes.sol";
import {StrategyHandler} from "./base/StrategyHandler.sol";
import {BaseStrategySimple} from "./base/BaseStrategySimple.sol";
import {BaseStrategyMulti} from "./base/BaseStrategyMulti.sol";

/// @notice Compatibility entrypoint for strategy test inheritance.
/// @dev Strategy-specific test files should inherit this contract; internals are composed from `test/base/*`.
abstract contract BaseStrategyTest is BaseStrategySimple, BaseStrategyMulti {
    // Re-export `RevertContext`, `IRevertAllowlistProvider`, and `StrategyHandler` for compatibility.
}
