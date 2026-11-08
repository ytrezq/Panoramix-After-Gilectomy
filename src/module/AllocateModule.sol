// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20, IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";
import {IAllocateModule} from "../interface/IAllocateModule.sol";
import {IStrategyTemplate} from "../interface/IStrategyTemplate.sol";
import {IConcreteStandardVaultImpl} from "../interface/IConcreteStandardVaultImpl.sol";
import {ConcreteStandardVaultImplStorageLib} from "../lib/storage/ConcreteStandardVaultImplStorageLib.sol";
import {SafeCast} from "@openzeppelin-contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract AllocateModule is IAllocateModule {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    /// @inheritdoc IAllocateModule
    function allocateFunds(bytes calldata data) external {
        AllocateParams[] memory params = abi.decode(data, (AllocateParams[]));

        ConcreteStandardVaultImplStorageLib.ConcreteStandardVaultImplStorage storage $ =
            ConcreteStandardVaultImplStorageLib.fetch();

        for (uint256 i; i < params.length; ++i) {
            // Only allocate to Active strategies
            if ($.strategyData[params[i].strategy].status != IConcreteStandardVaultImpl.StrategyStatus.Active) {
                continue;
            }

            uint256 amount;
            if (params[i].isDeposit) {
                IERC20(IERC4626(address(this)).asset()).forceApprove(params[i].strategy, type(uint256).max);

                amount = IStrategyTemplate(params[i].strategy).allocateFunds(params[i].extraData);

                IERC20(IERC4626(address(this)).asset()).forceApprove(params[i].strategy, 0);

                $.strategyData[params[i].strategy].allocated += amount.toUint120();
            } else {
                amount = IStrategyTemplate(params[i].strategy).deallocateFunds(params[i].extraData);
                $.strategyData[params[i].strategy].allocated -= amount.toUint120();
            }

            emit AllocatedFunds(params[i].strategy, params[i].isDeposit, amount, params[i].extraData);
        }
    }
}
