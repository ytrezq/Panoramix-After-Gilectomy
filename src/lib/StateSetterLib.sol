// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ConcreteStandardVaultImplStorageLib as SVLib} from "./storage/ConcreteStandardVaultImplStorageLib.sol";
import {EnumerableSet} from "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {IConcreteStandardVaultImpl} from "../interface/IConcreteStandardVaultImpl.sol";
import {ConcreteV2FeeParamsLib} from "./Constants.sol";

library StateSetterLib {
    using EnumerableSet for EnumerableSet.AddressSet;

    function updateManagementFee(uint16 managementFee_) external {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        if (managementFee_ > 0) {
            require($.managementFeeRecipient != address(0), IConcreteStandardVaultImpl.FeeRecipientNotSet());
            require(
                managementFee_ <= ConcreteV2FeeParamsLib.MAX_MANAGEMENT_FEE,
                IConcreteStandardVaultImpl.ManagementFeeExceedsMaximum()
            );
        }

        $.managementFee = managementFee_;
        emit IConcreteStandardVaultImpl.ManagementFeeUpdated(managementFee_);
    }

    /// @dev Updates the management fee recipient
    /// @param recipient The new management fee recipient
    function updateManagementFeeRecipient(address recipient) external {
        require(recipient != address(0), IConcreteStandardVaultImpl.InvalidFeeRecipient());

        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        $.managementFeeRecipient = recipient;
        emit IConcreteStandardVaultImpl.ManagementFeeRecipientUpdated(recipient);
    }

    function updatePerformanceFee(uint16 performanceFee_) external {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        if (performanceFee_ > 0) {
            require($.performanceFeeRecipient != address(0), IConcreteStandardVaultImpl.FeeRecipientNotSet());
            require(
                performanceFee_ <= ConcreteV2FeeParamsLib.MAX_PERFORMANCE_FEE,
                IConcreteStandardVaultImpl.PerformanceFeeExceedsMaximum()
            );
        }

        $.performanceFee = performanceFee_;
        emit IConcreteStandardVaultImpl.PerformanceFeeUpdated(performanceFee_);
    }

    function updatePerformanceFeeRecipient(address recipient) external {
        require(recipient != address(0), IConcreteStandardVaultImpl.InvalidFeeRecipient());

        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();
        $.performanceFeeRecipient = recipient;
        emit IConcreteStandardVaultImpl.PerformanceFeeRecipientUpdated(recipient);
    }

    function setDepositLimits(uint256 minDepositAmount, uint256 maxDepositAmount) external {
        require(maxDepositAmount >= minDepositAmount, IConcreteStandardVaultImpl.InvalidDepositLimits());

        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        $.maxDepositAmount = maxDepositAmount;
        $.minDepositAmount = minDepositAmount;
        emit IConcreteStandardVaultImpl.DepositLimitsUpdated(maxDepositAmount, minDepositAmount);
    }

    function setWithdrawLimits(uint256 minWithdrawAmount, uint256 maxWithdrawAmount) external {
        require(maxWithdrawAmount >= minWithdrawAmount, IConcreteStandardVaultImpl.InvalidWithdrawLimits());

        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        $.maxWithdrawAmount = maxWithdrawAmount;
        $.minWithdrawAmount = minWithdrawAmount;
        emit IConcreteStandardVaultImpl.WithdrawLimitsUpdated(maxWithdrawAmount, minWithdrawAmount);
    }

    function addStrategy(address strategy) external {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        require($.strategies.add(strategy), IConcreteStandardVaultImpl.StrategyAlreadyAdded());
        $.strategyData[strategy] = IConcreteStandardVaultImpl.StrategyData({
            status: IConcreteStandardVaultImpl.StrategyStatus.Active, allocated: 0
        });

        emit IConcreteStandardVaultImpl.StrategyAdded(strategy);
    }

    function removeStrategy(address strategy) external {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        IConcreteStandardVaultImpl.StrategyData memory strategyDataCached = $.strategyData[strategy];

        require(
            (strategyDataCached.allocated == 0 && _strategyNotInDeallocationOrder(strategy))
                || strategyDataCached.status == IConcreteStandardVaultImpl.StrategyStatus.Halted,
            IConcreteStandardVaultImpl.StrategyHasAllocation()
        );
        require($.strategies.remove(strategy), IConcreteStandardVaultImpl.StrategyDoesNotExist());

        delete $.strategyData[strategy];

        emit IConcreteStandardVaultImpl.StrategyRemoved(strategy);
    }

    function toggleStrategyStatus(address strategy) external {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        require($.strategies.contains(strategy), IConcreteStandardVaultImpl.StrategyDoesNotExist());

        IConcreteStandardVaultImpl.StrategyStatus currentStatus = $.strategyData[strategy].status;

        if (currentStatus == IConcreteStandardVaultImpl.StrategyStatus.Active) {
            $.strategyData[strategy].status = IConcreteStandardVaultImpl.StrategyStatus.Halted;
        } else {
            $.strategyData[strategy].status = IConcreteStandardVaultImpl.StrategyStatus.Active;
        }

        emit IConcreteStandardVaultImpl.StrategyStatusToggled(strategy);
    }

    /**
     * @dev Internal function to check if a strategy is not in the deallocation order.
     * @param strategy The strategy address to check.
     * @return True if the strategy is not in the deallocation order, false otherwise.
     */
    function _strategyNotInDeallocationOrder(address strategy) internal view returns (bool) {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        address[] memory deallocationOrder = $.deallocationOrder;
        uint256 deallocationOrderLength = deallocationOrder.length;
        for (uint256 i = 0; i < deallocationOrderLength; i++) {
            if (deallocationOrder[i] == strategy) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice overwrites the deallocation order from strategies;
     */
    function setDeallocationOrder(address[] calldata order) external {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        delete $.deallocationOrder;

        uint256 orderLength = order.length;
        for (uint256 i = 0; i < orderLength; i++) {
            address strategy = order[i];
            require($.strategies.contains(strategy), IConcreteStandardVaultImpl.StrategyDoesNotExist());
            require(
                $.strategyData[strategy].status == IConcreteStandardVaultImpl.StrategyStatus.Active,
                IConcreteStandardVaultImpl.StrategyIsHalted()
            );

            $.deallocationOrder.push(strategy);
        }

        emit IConcreteStandardVaultImpl.DeallocationOrderUpdated();
    }
}
