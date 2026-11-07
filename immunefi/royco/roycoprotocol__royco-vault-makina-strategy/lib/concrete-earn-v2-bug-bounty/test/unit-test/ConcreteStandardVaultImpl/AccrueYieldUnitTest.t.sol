// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcreteStandardVaultImplBaseSetup} from "../../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {IStrategyTemplate} from "../../../src/interface/IStrategyTemplate.sol";
import {IAllocateModule} from "../../../src/interface/IAllocateModule.sol";
import {ERC4626StrategyMock} from "../../mock/ERC4626StrategyMock.sol";
import {AddStrategyWithDeallocationOrder} from "../../common/AddStrategyWithDeallocationOrder.sol";
import {IConcreteStandardVaultImpl} from "../../../src/interface/IConcreteStandardVaultImpl.sol";

contract AccrueYieldUnitTest is ConcreteStandardVaultImplBaseSetup, AddStrategyWithDeallocationOrder {
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

        // allocate some funds to the strategy
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

    function testAccrueYieldWithPositiveYield() public {
        // increase underlying vault by 10e18 to reflect yield generation
        uint256 yield = 10e18;
        asset.mint(address(strategy.underlyingVault()), yield);

        uint256 allocatedAmount = concreteStandardVault.getStrategyData(address(strategy)).allocated;
        uint256 strategyTotalAllocatedValue = strategy.totalAllocatedValue();
        uint256 lastTotalAssetsBefore = concreteStandardVault.cachedTotalAssets();
        assertApproxEqAbs(strategyTotalAllocatedValue - allocatedAmount, yield, 1);
        (uint256 previewedLastTotalAssets,) = concreteStandardVault.previewAccrueYield();

        concreteStandardVault.accrueYield();

        assertEq(concreteStandardVault.getStrategyData(address(strategy)).allocated, strategyTotalAllocatedValue);
        assertEq(
            concreteStandardVault.cachedTotalAssets(),
            lastTotalAssetsBefore + (strategyTotalAllocatedValue - allocatedAmount)
        );
        assertEq(concreteStandardVault.cachedTotalAssets(), previewedLastTotalAssets);
    }

    function testAccrueYieldWithLoss() public {
        uint256 allocatedAmount = concreteStandardVault.getStrategyData(address(strategy)).allocated;
        uint256 loss = allocatedAmount / 2;
        // mock loss
        vm.mockCall(
            address(strategy), abi.encodeWithSelector(IStrategyTemplate.totalAllocatedValue.selector), abi.encode(loss)
        );

        uint256 lastTotalAssetsBefore = concreteStandardVault.cachedTotalAssets();
        (uint256 previewedLastTotalAssets,) = concreteStandardVault.previewAccrueYield();

        concreteStandardVault.accrueYield();

        assertEq(concreteStandardVault.cachedTotalAssets(), lastTotalAssetsBefore - loss);
        assertEq(concreteStandardVault.cachedTotalAssets(), previewedLastTotalAssets);
    }

    function testPreviewVsAccruePerformanceFee() public {
        // This test compares _previewAccrueYieldAndFees() with accruePerformanceFee() directly

        address managementFeeRecipient = makeAddr("managementFeeRecipient");
        address performanceFeeRecipient = makeAddr("performanceFeeRecipient");

        // Set management fee recipient first
        vm.prank(factory.owner());
        concreteStandardVault.updateManagementFeeRecipient(managementFeeRecipient);

        // Set performance fee recipient
        vm.prank(factory.owner());
        concreteStandardVault.updatePerformanceFeeRecipient(performanceFeeRecipient);

        // Set management fee (10% annually - high rate to ensure it's charged)
        vm.prank(vaultManager);
        concreteStandardVault.updateManagementFee(1000); // 10%

        // Set performance fee (10%)
        vm.prank(vaultManager);
        concreteStandardVault.updatePerformanceFee(1000);

        // Add yield using simulateYield
        uint256 yieldAmount = 300000e18; // 10% yield

        asset.mint(address(this), yieldAmount);
        asset.approve(address(strategy), yieldAmount);
        strategy.simulateYield(yieldAmount);

        // Fast forward time to ensure management fee is charged
        vm.warp(block.timestamp + 365 days); // 1 year

        // Get preview values BEFORE accrual
        (uint256 previewTotalAssets, uint256 previewTotalSupply) = concreteStandardVault.previewAccrueYield();

        // Now call the FULL accrual process (which includes management fee calculation)
        concreteStandardVault.accrueYield();

        assertEq(concreteStandardVault.totalAssets(), previewTotalAssets);
        assertEq(concreteStandardVault.totalSupply(), previewTotalSupply);
    }
}
