// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract SPRL2_Constructor_Integrations_Test is Integrations_Test {
    function test_SPRL2_Constructor() external {
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(rewardToken);
        rewardTokens[1] = address(extraRewardToken);
        sprl2 = new sPRL2(
            address(auraBpt),
            users.daoTreasury.addr,
            address(accessManager),
            DEFAULT_PENALTY_PERCENTAGE,
            DEFAULT_TIME_LOCK_DURATION,
            sPRL2.BPTConfigParams({
                balancerRouter: IBalancerV3Router(address(balancerV3RouterMock)),
                auraBoosterLite: IAuraBoosterLite(address(auraBoosterLiteMock)),
                auraRewardsPool: IAuraRewardPool(address(auraRewardPoolMock)),
                balancerBPT: IERC20(address(bpt)),
                prl: IERC20(address(prl)),
                weth: IWrappedNative(address(weth)),
                rewardTokens: rewardTokens,
                permit2: IPermit2(address(permit2))
            })
        );
        assertEq(sprl2.authority(), address(accessManager));
        assertEq(address(sprl2.underlying()), address(auraBpt));
        assertEq(sprl2.timeLockDuration(), DEFAULT_TIME_LOCK_DURATION);
        assertEq(sprl2.startPenaltyPercentage(), DEFAULT_PENALTY_PERCENTAGE);
        assertEq(sprl2.unlockingAmount(), 0);
        assertEq(sprl2.feeReceiver(), users.daoTreasury.addr);
        assertEq(sprl2.name(), "Stake 20WETH-80PRL Aura Deposit Vault");
        assertEq(sprl2.symbol(), "sPRL2");
        assertEq(address(sprl2.BALANCER_ROUTER()), address(balancerV3RouterMock));
        assertEq(address(sprl2.AURA_BOOSTER_LITE()), address(auraBoosterLiteMock));
        assertEq(address(sprl2.AURA_REWARDS_POOL()), address(auraRewardPoolMock));
        assertEq(address(sprl2.BPT()), address(bpt));
        assertEq(address(sprl2.PRL()), address(prl));
        assertEq(address(sprl2.WETH()), address(weth));
        assertEq(address(sprl2.PERMIT2()), address(permit2));
        assertEq(sprl2.rewardTokens(0), address(rewardToken));
        assertEq(sprl2.rewardTokens(1), address(extraRewardToken));
    }

    function test_SPRL2_Constructor_RevertWhen_EmptyRewardTokens() external {
        address[] memory wrongRewardTokens = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(sPRL2.EmptyRewardTokens.selector));
        new sPRL2(
            address(auraBpt),
            users.daoTreasury.addr,
            address(accessManager),
            DEFAULT_PENALTY_PERCENTAGE,
            DEFAULT_TIME_LOCK_DURATION,
            sPRL2.BPTConfigParams({
                balancerRouter: IBalancerV3Router(address(balancerV3RouterMock)),
                auraBoosterLite: IAuraBoosterLite(address(auraBoosterLiteMock)),
                auraRewardsPool: IAuraRewardPool(address(auraRewardPoolMock)),
                balancerBPT: IERC20(address(bpt)),
                prl: IERC20(address(prl)),
                weth: IWrappedNative(address(weth)),
                rewardTokens: wrongRewardTokens,
                permit2: IPermit2(address(permit2))
            })
        );
    }
}
