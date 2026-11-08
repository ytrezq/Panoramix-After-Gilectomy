// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract sPRL2_UpdateFeeReceiver_Integrations_Test is Integrations_Test {
    address internal newPaymentReceiver = makeAddr("newPaymentReceiver");
    uint256 REWARD_AMOUNT = 10e18;

    modifier addRewards() {
        rewardToken.mint(address(sprl2), REWARD_AMOUNT);
        extraRewardToken.mint(address(sprl2), REWARD_AMOUNT);
        _;
    }

    function test_sPRL2_UpdateFeeReceiver_WithRewards() external addRewards {
        uint256 feeReceiverMainRewardBalance = rewardToken.balanceOf(users.daoTreasury.addr);
        uint256 feeReceiverExtraRewardBalance = extraRewardToken.balanceOf(users.daoTreasury.addr);
        vm.startPrank(users.admin.addr);
        vm.expectEmit(address(sprl2));
        emit TimeLockPenaltyERC20.FeeReceiverUpdated(newPaymentReceiver);
        sprl2.updateFeeReceiver(newPaymentReceiver);

        assertEq(rewardToken.balanceOf(address(sprl2)), 0);
        assertEq(rewardToken.balanceOf(users.daoTreasury.addr), feeReceiverMainRewardBalance + REWARD_AMOUNT);
        assertEq(extraRewardToken.balanceOf(address(sprl2)), 0);
        assertEq(extraRewardToken.balanceOf(users.daoTreasury.addr), feeReceiverExtraRewardBalance + REWARD_AMOUNT);
    }

    function test_sPRL2_UpdateFeeReceiver_WithoutRewards() external {
        vm.startPrank(users.admin.addr);
        vm.expectEmit(address(sprl2));
        emit TimeLockPenaltyERC20.FeeReceiverUpdated(newPaymentReceiver);
        sprl2.updateFeeReceiver(newPaymentReceiver);
    }

    function test_TimeLockPenaltyERC20_UpdateFeeReceiver_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        sprl2.updateFeeReceiver(newPaymentReceiver);
    }
}
