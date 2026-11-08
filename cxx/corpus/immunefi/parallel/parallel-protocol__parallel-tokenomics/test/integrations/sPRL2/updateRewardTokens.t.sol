// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract sPRL2_UpdateRewardTokens_Integrations_Test is Integrations_Test {
    address[] internal newRewardTokens = [makeAddr("newRewardToken1"), makeAddr("newRewardToken2")];

    function test_sPRL2_UpdateRewardTokens_WithRewards() external {
        vm.startPrank(users.admin.addr);
        vm.expectEmit(address(sprl2));
        emit sPRL2.RewardTokensUpdated(newRewardTokens);
        sprl2.updateRewardTokens(newRewardTokens);
    }

    function test_sPRL2_UpdateRewardTokens_RevertWhen_CallerNotAuthorized() external {
        vm.startPrank(users.hacker.addr);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, users.hacker.addr));
        sprl2.updateRewardTokens(newRewardTokens);
    }

    function test_sPRL2_UpdateRewardTokens_RevertWhen_EmptyRewardTokens() external {
        vm.startPrank(users.admin.addr);
        vm.expectRevert(abi.encodeWithSelector(sPRL2.EmptyRewardTokens.selector));
        sprl2.updateRewardTokens(new address[](0));
    }
}
