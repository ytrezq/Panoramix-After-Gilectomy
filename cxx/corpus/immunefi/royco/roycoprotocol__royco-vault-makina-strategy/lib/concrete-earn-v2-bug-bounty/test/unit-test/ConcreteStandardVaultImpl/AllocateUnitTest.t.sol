// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {
    IConcreteStandardVaultImpl,
    ConcreteStandardVaultImplBaseSetup
} from "../../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {IAllocateModule} from "../../../src/interface/IAllocateModule.sol";
import {ERC4626StrategyMock} from "../../mock/ERC4626StrategyMock.sol";
import {AddStrategyWithDeallocationOrder} from "../../common/AddStrategyWithDeallocationOrder.sol";

contract AllocateUnitTest is ConcreteStandardVaultImplBaseSetup, AddStrategyWithDeallocationOrder {
    address public user1;

    ERC4626StrategyMock public strategy;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");

        strategy = new ERC4626StrategyMock(address(asset));

        addStrategyWithDeallocationOrder(address(strategy), address(concreteStandardVault), allocator, strategyOperator);

        address[] memory strategies = concreteStandardVault.getStrategies();
        assertEq(strategies.length, 1);
        assertEq(strategies[0], address(strategy));

        // fund user account
        asset.mint(user1, 1000000e18);
        // deposit some assets into the vault
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), 1000e18);
        concreteStandardVault.deposit(1000e18, user1);
        vm.stopPrank();

        // check the vault balance
        assertEq(concreteStandardVault.balanceOf(user1), 1000e18);
        assertEq(concreteStandardVault.cachedTotalAssets(), 1000e18);
    }

    function testAllocate() public {
        uint256 amount = concreteStandardVault.cachedTotalAssets();

        bytes memory extraData = abi.encode(amount);
        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] = IAllocateModule.AllocateParams({isDeposit: true, strategy: address(strategy), extraData: extraData});

        bytes memory data = abi.encode(params);
        vm.prank(allocator);
        concreteStandardVault.allocate(data);

        IConcreteStandardVaultImpl.StrategyData memory strategyData =
            concreteStandardVault.getStrategyData(address(strategy));
        assertEq(strategyData.allocated, 1000e18);
        assertEq(uint8(strategyData.status), uint8(IConcreteStandardVaultImpl.StrategyStatus.Active));
    }

    function testDeallocate() public {
        uint256 amount = concreteStandardVault.cachedTotalAssets();

        bytes memory extraData = abi.encode(amount);
        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] = IAllocateModule.AllocateParams({isDeposit: true, strategy: address(strategy), extraData: extraData});

        bytes memory data = abi.encode(params);
        vm.prank(allocator);
        concreteStandardVault.allocate(data);

        IConcreteStandardVaultImpl.StrategyData memory strategyData =
            concreteStandardVault.getStrategyData(address(strategy));
        assertEq(strategyData.allocated, 1000e18);
        assertEq(uint8(strategyData.status), uint8(IConcreteStandardVaultImpl.StrategyStatus.Active));

        extraData = abi.encode(amount);
        params[0] =
            IAllocateModule.AllocateParams({isDeposit: false, strategy: address(strategy), extraData: extraData});

        data = abi.encode(params);
        vm.prank(allocator);
        concreteStandardVault.allocate(data);

        strategyData = concreteStandardVault.getStrategyData(address(strategy));
        assertEq(strategyData.allocated, 0);
        assertEq(uint8(strategyData.status), uint8(IConcreteStandardVaultImpl.StrategyStatus.Active));
    }
}
