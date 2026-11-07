// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IConcreteStandardVaultImpl} from "../../src/interface/IConcreteStandardVaultImpl.sol";
import {ERC20Mock} from "../mock/ERC20Mock.sol";
import {AllocateModule} from "../../src/module/AllocateModule.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../src/lib/Roles.sol";

contract AddStrategyWithDeallocationOrder is Test {
    /**
     * @dev Helper function to add a strategy and automatically add it to the deallocation order
     * @param strategy_ The strategy address to add
     * @param concreteVaulAddress_ The address of the concrete vault to add the strategy to
     * @param allocator_ The address of the allocator to add the strategy to
     */
    function addStrategyWithDeallocationOrder(
        address strategy_,
        address concreteVaulAddress_,
        address allocator_,
        address strategyOperator_
    ) internal {
        IConcreteStandardVaultImpl concreteStandardVault_ = IConcreteStandardVaultImpl(concreteVaulAddress_);
        vm.startPrank(strategyOperator_);
        concreteStandardVault_.addStrategy(strategy_);
        vm.stopPrank();

        // Add to deallocation order
        address[] memory currentOrder = concreteStandardVault_.getDeallocationOrder();
        address[] memory newOrder = new address[](currentOrder.length + 1);

        // Copy existing order
        for (uint256 i = 0; i < currentOrder.length; i++) {
            newOrder[i] = currentOrder[i];
        }

        // Add new strategy at the end
        newOrder[currentOrder.length] = strategy_;

        vm.prank(allocator_);
        concreteStandardVault_.setDeallocationOrder(newOrder);
    }
}
