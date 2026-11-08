// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/types/Time.sol)
pragma solidity ^0.8.24;

import {IConcreteStandardVaultImpl} from "../../interface/IConcreteStandardVaultImpl.sol";
import {EnumerableSet} from "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {Hooks} from "../Hooks.sol";

library ConcreteStandardVaultImplStorageLib {
    /// @dev keccak256(abi.encode(uint256(keccak256("concrete.storage.ConcreteStandardVaultImplStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ConcreteStandardVaultImplStorageLocation =
        0xe74d828616eceb28be4a8cf3f9eeee868e1f44ce928ee17a9d7ad296fa52be00;

    /// @custom:storage-location erc7201:concrete.storage.ConcreteStandardVaultImplStorage
    struct ConcreteStandardVaultImplStorage {
        /// @dev max deposit amount
        uint256 maxDepositAmount;
        /// @dev max withdraw amount
        uint256 maxWithdrawAmount;
        /// @dev min deposit amount
        uint256 minDepositAmount;
        /// @dev min withdraw amount
        uint256 minWithdrawAmount;
        /// @dev allocate module's address
        address allocateModule;
        /// 1 slot: 160 + 16 + 32
        /// @dev management fee recipient
        address managementFeeRecipient;
        /// @dev annual management fee rate in basis points
        uint16 managementFee;
        /// @dev timestamp of last management fee accrual
        uint32 lastManagementFeeAccrual;
        /// 1 slot: 160 + 16
        /// @dev performance fee recipient
        address performanceFeeRecipient;
        /// @dev annual performance fee rate in basis points
        uint16 performanceFee;
        /// @dev high water mark
        uint128 performanceFeeHighWaterMark;
        /// Mapping between a strategy address and it's data
        mapping(address => IConcreteStandardVaultImpl.StrategyData) strategyData;
        /// An set of strategy addresses that ConcreteVault allocates to
        EnumerableSet.AddressSet strategies;
        /// Defines the order in which funds are retrieved from strategies to fulfill withdrawals
        address[] deallocationOrder;
        /// @dev hooks
        Hooks hooks;
    }

    /**
     *
     */
    function fetch() internal pure returns (ConcreteStandardVaultImplStorage storage $) {
        assembly {
            $.slot := ConcreteStandardVaultImplStorageLocation
        }
    }
}
