// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {console2 as console} from "forge-std/Test.sol";

import {
    IConcreteFactory,
    ConcreteFactoryBaseSetup,
    VaultProxy,
    IConcreteStandardVaultImpl,
    ConcreteStandardVaultImpl,
    ConcreteStandardVaultImplBaseSetup
} from "../../common/ConcreteStandardVaultImplBaseSetup.t.sol";

import {InvariantUtils} from "../../invariant/helpers/InvariantUtils.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";

import {ConcreteStandardVaultImplBaseSetup} from "../../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {IAllocateModule} from "../../../src/interface/IAllocateModule.sol";
import {ERC4626StrategyMock} from "../../mock/ERC4626StrategyMock.sol";
import {IConcreteStandardVaultImpl} from "../../../src/interface/IConcreteStandardVaultImpl.sol";
import {AddStrategyWithDeallocationOrder} from "../../common/AddStrategyWithDeallocationOrder.sol";
import {IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";
import {ConcreteV2FeeParamsLib} from "../../../src/lib/Constants.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {ERC4626} from "@openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";

contract ConcreteStandardVaultUserOpsFuzzTest is ConcreteStandardVaultImplBaseSetup, AddStrategyWithDeallocationOrder {
    address public user1;
    ERC4626StrategyMock public strategy1;
    ERC4626StrategyMock public strategy2;
    uint256 public constant ASSET_SUPPLY_THIS = 1_000_000;

    function setUp() public override {
        ConcreteStandardVaultImplBaseSetup.setUp();
        user1 = makeAddr("user1");
        // Deploy strategies
        strategy1 = new ERC4626StrategyMock(address(asset));
        strategy2 = new ERC4626StrategyMock(address(asset));

        vm.label(address(strategy1), "strategy1");
        vm.label(address(strategy2), "strategy2");
        vm.label(user1, "user1");

        // Add strategies to vault
        addStrategyWithDeallocationOrder(
            address(strategy1), address(concreteStandardVault), allocator, strategyOperator
        );
        addStrategyWithDeallocationOrder(
            address(strategy2), address(concreteStandardVault), allocator, strategyOperator
        );

        // mint a significant amount of assets to this contract
        asset.mint(address(this), ASSET_SUPPLY_THIS);
    }

    function _setFees(address recipient, uint256 performanceFee, uint256 managementFee) internal {
        vm.startPrank(factoryOwner);
        concreteStandardVault.updatePerformanceFeeRecipient(recipient);
        concreteStandardVault.updateManagementFeeRecipient(recipient);
        vm.stopPrank();
        vm.startPrank(vaultManager);
        concreteStandardVault.updatePerformanceFee(uint16(performanceFee));
        concreteStandardVault.updateManagementFee(uint16(managementFee));
        vm.stopPrank();
    }

    function _setWithdrawLimits(uint256 minWithdrawAmount, uint256 maxWithdrawAmount) internal {
        vm.startPrank(vaultManager);
        concreteStandardVault.setWithdrawLimits(minWithdrawAmount, maxWithdrawAmount);
        vm.stopPrank();
    }

    function _deposit(address user, uint256 assets) internal returns (uint256 shares) {
        asset.mint(user, assets);
        vm.startPrank(user);
        asset.approve(address(concreteStandardVault), assets);
        shares = concreteStandardVault.deposit(assets, user);
        vm.stopPrank();
    }

    struct AllocationAmounts {
        address[] strategies;
        uint256[] amounts;
    }

    function _allocate(AllocationAmounts memory allocationAmounts) internal {
        IAllocateModule.AllocateParams[] memory params =
            new IAllocateModule.AllocateParams[](allocationAmounts.strategies.length);
        for (uint256 i = 0; i < allocationAmounts.strategies.length; i++) {
            params[i] = IAllocateModule.AllocateParams({
                isDeposit: true,
                strategy: allocationAmounts.strategies[i],
                extraData: abi.encode(allocationAmounts.amounts[i])
            });
        }
        bytes memory data = abi.encode(params);
        vm.startPrank(allocator);
        concreteStandardVault.allocate(data);
        vm.stopPrank();
    }

    function testFuzzWithdrawStandardWithYieldFeesLimitsAndOnBehalfOf(
        uint256 assets,
        int256 yieldOrLoss,
        uint256 withdrawAmount,
        uint256 globalMinWithdrawAmount,
        uint256 globalMaxWithdrawAmount,
        uint256 performanceFee,
        uint256 managementFee,
        address sender,
        address receiver
    ) public {
        // set bounds for the asset
        assets = bound(assets, 1, ASSET_SUPPLY_THIS);
        uint256 strategy1AllocationAmount = uint256(assets / 2);
        yieldOrLoss = bound(yieldOrLoss, -int256(strategy1AllocationAmount), int256(ASSET_SUPPLY_THIS));
        withdrawAmount = bound(withdrawAmount, 1, 2 * ASSET_SUPPLY_THIS);
        performanceFee = bound(performanceFee, uint256(0), uint256(ConcreteV2FeeParamsLib.MAX_PERFORMANCE_FEE));
        managementFee = bound(managementFee, uint256(0), uint256(ConcreteV2FeeParamsLib.MAX_MANAGEMENT_FEE));
        globalMinWithdrawAmount = bound(globalMinWithdrawAmount, 0, ASSET_SUPPLY_THIS);
        globalMaxWithdrawAmount =
            bound(globalMaxWithdrawAmount, globalMinWithdrawAmount, ASSET_SUPPLY_THIS + uint256(1));
        // use vm.assume(a != 1);
        vm.assume(sender != address(0));
        vm.assume(receiver != address(0));

        if (uint256(uint160(sender)) % 5 == 0) {
            // occasionally collapse sender and receiver to user1
            sender = user1;
            receiver = user1;
        }

        _setFees(address(2), performanceFee, managementFee);
        _setWithdrawLimits(globalMinWithdrawAmount, globalMaxWithdrawAmount);

        // deposit some assets into the vault
        uint256 sharesMinted = _deposit(user1, assets);

        AllocationAmounts memory allocationAmounts;
        allocationAmounts.strategies = new address[](2);
        allocationAmounts.strategies[0] = address(strategy1);
        allocationAmounts.strategies[1] = address(strategy2);
        allocationAmounts.amounts = new uint256[](2);
        allocationAmounts.amounts[0] = strategy1AllocationAmount;
        allocationAmounts.amounts[1] = assets - strategy1AllocationAmount;

        _allocate(allocationAmounts);

        // earn yield or loss
        if (yieldOrLoss > 0) {
            // approve the yield amount to the strategy
            asset.approve(address(strategy1), uint256(yieldOrLoss));
            strategy1.simulateYield(uint256(yieldOrLoss));
        }
        if (yieldOrLoss < 0) {
            uint256 balanceOfUnderlyingVaultBeforeLoss = asset.balanceOf(address(strategy1.underlyingVault()));
            console.log("balanceOfUnderlyingVaultBeforeLoss", balanceOfUnderlyingVaultBeforeLoss);
            console.log("loss amount", uint256(-yieldOrLoss));
            strategy1.simulateLoss(uint256(-yieldOrLoss));
        }

        // get max withdrawable assets
        uint256 maxWithdrawableAssets = concreteStandardVault.maxWithdraw(user1);

        // preview the withdrawal
        uint256 sharesRedeemedPreviewed = concreteStandardVault.previewWithdraw(withdrawAmount);

        // approve the sender to spend the shares
        if (sender != user1) {
            vm.startPrank(user1);
            concreteStandardVault.approve(sender, sharesRedeemedPreviewed);
            vm.stopPrank();
        }

        // if maxWithdrawableAssets is greater than the requested amount, withdraw the requested amount
        if (maxWithdrawableAssets >= withdrawAmount) {
            if (withdrawAmount <= globalMaxWithdrawAmount && withdrawAmount >= globalMinWithdrawAmount) {
                vm.startPrank(sender);
                // 1) shares burn: Transfer(user1 -> address(0), shares)
                //    Emitted BY the shares token (vault itself if ERC20 is implemented there)
                vm.expectEmit(true, true, false, true, address(concreteStandardVault));
                emit IERC20.Transfer(user1, address(0), sharesRedeemedPreviewed);

                // 2) asset transfer: Transfer(vault -> receiver, assets)
                //    Emitted BY the underlying asset ERC20
                vm.expectEmit(true, true, false, true, address(asset));
                emit IERC20.Transfer(address(concreteStandardVault), receiver, withdrawAmount);

                // 3) ERC4626 Withdraw(caller, receiver, owner, assets, shares)
                //    Emitted BY the vault
                vm.expectEmit(true, true, true, true, address(concreteStandardVault));
                emit IERC4626.Withdraw(sender, receiver, user1, withdrawAmount, sharesRedeemedPreviewed);

                concreteStandardVault.withdraw(withdrawAmount, receiver, user1);
                vm.stopPrank();
            } else {
                // error AssetAmountOutOfBounds(address sender, uint256 assets, uint256 minDepositAmount, uint256 maxDepositAmount);
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IConcreteStandardVaultImpl.AssetAmountOutOfBounds.selector,
                        sender,
                        withdrawAmount,
                        globalMinWithdrawAmount,
                        globalMaxWithdrawAmount
                    )
                );
                vm.startPrank(sender);
                concreteStandardVault.withdraw(withdrawAmount, receiver, user1);
                vm.stopPrank();
            }
        } else {
            // error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ERC4626.ERC4626ExceededMaxWithdraw.selector, user1, withdrawAmount, maxWithdrawableAssets
                )
            );
            vm.startPrank(sender);
            concreteStandardVault.withdraw(withdrawAmount, receiver, user1);
            vm.stopPrank();
        }
    }
}
