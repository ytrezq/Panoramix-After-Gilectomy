// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcreteStandardVaultImplBaseSetup} from "../../common/ConcreteStandardVaultImplBaseSetup.t.sol";
import {IAllocateModule} from "../../../src/interface/IAllocateModule.sol";
import {ERC4626StrategyMock} from "../../mock/ERC4626StrategyMock.sol";
import {InvariantUtils} from "../../invariant/helpers/InvariantUtils.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";
import {AddStrategyWithDeallocationOrder} from "../../common/AddStrategyWithDeallocationOrder.sol";

contract PerformanceFeeFuzzTest is ConcreteStandardVaultImplBaseSetup, AddStrategyWithDeallocationOrder {
    address public user1;
    address public performanceFeeRecipient;
    ERC4626StrategyMock public strategy;
    uint256 public constant INITIAL_DEPOSIT = 1000e18;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        performanceFeeRecipient = makeAddr("performanceFeeRecipient");

        // Create and add strategy
        strategy = new ERC4626StrategyMock(address(asset));
        addStrategyWithDeallocationOrder(address(strategy), address(concreteStandardVault), allocator, strategyOperator);

        // Make initial deposit
        asset.mint(user1, INITIAL_DEPOSIT);
        vm.startPrank(user1);
        asset.approve(address(concreteStandardVault), INITIAL_DEPOSIT);
        concreteStandardVault.deposit(INITIAL_DEPOSIT, user1);
        vm.stopPrank();
    }

    function testFuzzPerformanceFeeAccrual(uint16 performanceFee, uint256 positiveYield, uint256 allocateAmount)
        public
    {
        // Bound inputs to realistic ranges
        performanceFee = uint16(bound(performanceFee, 1, 1000)); // 0.01% to 10% (max allowed)
        allocateAmount = bound(allocateAmount, 0, INITIAL_DEPOSIT);
        positiveYield = bound(positiveYield, 0, INITIAL_DEPOSIT / 2); // 0 to 50% of initial deposit

        // Set performance fee on existing vault
        vm.prank(factoryOwner);
        concreteStandardVault.updatePerformanceFeeRecipient(performanceFeeRecipient);

        vm.prank(vaultManager);
        concreteStandardVault.updatePerformanceFee(performanceFee);

        // Allocate funds to strategy using proper AllocateParams structure
        bytes memory extraData = abi.encode(allocateAmount);
        IAllocateModule.AllocateParams[] memory params = new IAllocateModule.AllocateParams[](1);
        params[0] = IAllocateModule.AllocateParams({isDeposit: true, strategy: address(strategy), extraData: extraData});

        bytes memory data = abi.encode(params);
        vm.prank(allocator);
        concreteStandardVault.allocate(data);

        // simulate yield
        asset.mint(address(this), positiveYield);
        asset.approve(address(strategy), positiveYield);
        strategy.simulateYield(positiveYield);

        // Calculate expected performance fee
        uint256 netPositiveYield =
            strategy.totalAllocatedValue() - concreteStandardVault.getStrategyData(address(strategy)).allocated;
        uint256 expectedFeeAmount = (netPositiveYield * performanceFee) / 10_000;
        uint256 expectedShares;

        if (expectedFeeAmount > 0) {
            expectedShares = InvariantUtils.convertToShares(
                expectedFeeAmount,
                concreteStandardVault.totalSupply(),
                concreteStandardVault.cachedTotalAssets() + netPositiveYield - expectedFeeAmount,
                Math.Rounding.Floor
            );
        }

        // Performance fee recipient should have 0 shares before yield accrual
        assertEq(concreteStandardVault.balanceOf(performanceFeeRecipient), 0);

        // Accrue yield and verify performance fee
        concreteStandardVault.accrueYield();
        uint256 actualShares = concreteStandardVault.balanceOf(performanceFeeRecipient);

        if (netPositiveYield == 0) {
            // No net positive yield, no performance fee
            assertEq(actualShares, 0);
        } else {
            // Should have minted performance fee shares (allow 1 wei tolerance for rounding)
            assertApproxEqAbs(actualShares, expectedShares, 1);
        }
    }
}
