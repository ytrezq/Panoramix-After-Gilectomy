// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/base/GammaPoolERC20.sol";

import "../../contracts/interfaces/IRewardTracker.sol";
import "./fixtures/CPMMGammaSwapSetup.sol";
import "../../contracts/tokens/EsToken.sol";

contract StakingRouterTest is CPMMGammaSwapSetup {
    function setUp() public {
        super.initCPMMGammaSwap();
        depositLiquidityInCFMM(user1, address(usdc), address(weth), 2*1e24, 2*1e21);
        depositLiquidityInCFMM(user2, address(usdc), address(weth), 2*1e24, 2*1e21);
        depositLiquidityInPool(user1, address(cfmm), address(pool));
        depositLiquidityInPool(user2, address(cfmm), address(pool));

        approveUserForStaking(user1, address(pool));
        approveUserForStaking(user2, address(pool));

        depositLiquidityInCFMM(user1, address(usdt), address(weth), 2*1e24, 2*1e21);
        depositLiquidityInCFMM(user2, address(usdt), address(weth), 2*1e24, 2*1e21);
        depositLiquidityInPool(user1, address(cfmm2), address(pool2));
        depositLiquidityInPool(user2, address(cfmm2), address(pool2));

        approveUserForStaking(user1, address(pool2));
        approveUserForStaking(user2, address(pool2));
    }

    function testEscrowToken() public {
        EsToken esToken = new EsToken("test token", "TOK1", address(0x123));
        assertEq(esToken.claimableToken(), address(0x123));

        vm.expectRevert("ZERO_ADDRESS");
        EsToken esTokenTest = new EsToken("test token", "TOK1", address(0));
    }

    function testStakingContractsAlreadySet() public {
        vm.expectRevert(bytes4(keccak256("GSTokensAlreadySet()")));
        stakingRouter.initializeGSTokens(address(gs), address(esGs), address(esGsb), address(bnGs), address(weth));

        vm.expectRevert(bytes4(keccak256("StakingContractsAlreadySet()")));
        stakingRouter.setupGsStaking();

        vm.expectRevert(bytes4(keccak256("StakingContractsAlreadySet()")));
        stakingRouter.setupGsStakingForLoan();

        vm.expectRevert(bytes4(keccak256("StakingContractsAlreadySet()")));
        stakingRouter.setupPoolStaking(address(pool), address(esGs), address(gs));

        vm.expectRevert(bytes4(keccak256("StakingContractsAlreadySet()")));
        stakingRouter.setupPoolStakingForLoan(address(pool), 1);

        vm.expectRevert(bytes4(keccak256("StakingContractsAlreadySet()")));
        stakingRouter.setupPoolStaking(address(pool2), address(esGs), address(gs));

        vm.expectRevert(bytes4(keccak256("StakingContractsAlreadySet()")));
        stakingRouter.setupPoolStakingForLoan(address(pool2), 1);
    }

    function testInterfaceIds() public {
        assertEq(type(IBeaconProxyFactory).interfaceId, hex'775c300c');
        assertEq(type(IBonusDistributor).interfaceId, hex'd2330c9f');
        assertEq(type(IFeeTracker).interfaceId, hex'95394ba2');
        assertEq(type(ILoanTracker).interfaceId, hex'3c68ad7c');
        assertEq(type(IRestrictedToken).interfaceId, hex'61e39026');
        assertEq(type(IRewardDistributor).interfaceId, hex'ddd97191');
        assertEq(type(IRewardTracker).interfaceId, hex'0f7dfb3c');
        assertEq(type(IStakingAdmin).interfaceId, hex'c7799f36');
        assertEq(type(IStakingRouter).interfaceId, hex'f31ccce9');
        assertEq(type(IVester).interfaceId, hex'e0a5cde6');
    }

    function testProtocolAssets() public {
        assertGt(pool.totalSupply(), 0);
    }

    function testStakeInvalidAssetInPoolError() public {
        vm.startPrank(user1);
        vm.expectRevert();
        stakingRouter.stakeLp(address(weth), address(esGs), 1000e18);
        vm.stopPrank();
    }

    function testSuccessStakeLpInPool() public {
        (address poolRewardTracker,,,,) = stakingRouter.poolTrackers(address(pool), address(esGs));
    
        vm.startPrank(user1);
        stakingRouter.stakeLp(address(pool), address(esGs), 1000e18);
        assertEq(IERC20(poolRewardTracker).balanceOf(user1), 1000e18);
        assertEq(IRewardTracker(poolRewardTracker).stakedAmounts(user1), 1000e18);
        assertEq(IRewardTracker(poolRewardTracker).depositBalances(user1, address(pool)), 1000e18);
        vm.stopPrank();
    }

    /// @notice stake lp in pool -> claim -> vest -> claim
    function testStakeLpClaimVestInPool(uint256 lpAmount1, uint256 lpAmount2) public {
        lpAmount1 = bound(lpAmount1, 1e18, 10000e18);
        lpAmount2 = bound(lpAmount2, 1e18, 10000e18);
        (address poolRewardTracker,,,,) = stakingRouter.poolTrackers(address(pool), address(esGs));
        (address poolRewardTracker2,,,,address vester2) = stakingRouter.poolTrackers(address(pool2), address(esGs));

        uint256 lpBalanceBeforeUser1 = GammaPoolERC20(pool).balanceOf(user1);
        uint256 lpBalanceBeforeUser2 = GammaPoolERC20(pool).balanceOf(user2);

        ////////// STAKING //////////
        vm.prank(user1);
        stakingRouter.stakeLp(address(pool), address(esGs), lpAmount1);
        vm.prank(user1);
        stakingRouter.stakeLp(address(pool2), address(esGs), lpAmount1);
        vm.prank(user2);
        stakingRouter.stakeLp(address(pool), address(esGs), lpAmount2);
        vm.prank(user2);
        stakingRouter.stakeLp(address(pool2), address(esGs), lpAmount2);

        assertApproxEqRel(GammaPoolERC20(pool).balanceOf(user1), lpBalanceBeforeUser1 - lpAmount1, 1e4);
        assertApproxEqRel(GammaPoolERC20(pool).balanceOf(user2), lpBalanceBeforeUser2 - lpAmount2, 1e4);

        vm.warp(block.timestamp + 1 days);

        uint256 esGsRewards1 = 86400 * 1e16 * lpAmount1/(lpAmount1+lpAmount2);
        uint256 esGsRewards2 = 86400 * 1e16 * lpAmount2/(lpAmount1+lpAmount2);
        assertApproxEqRel(IRewardTracker(poolRewardTracker).claimable(user1), esGsRewards1, 1e4);
        assertApproxEqRel(IRewardTracker(poolRewardTracker).claimable(user2), esGsRewards2, 1e4);
        assertApproxEqRel(IRewardTracker(poolRewardTracker2).claimable(user1), esGsRewards1, 1e4);
        assertApproxEqRel(IRewardTracker(poolRewardTracker2).claimable(user2), esGsRewards2, 1e4);

        ////////// CLAIMING //////////
        vm.prank(user1);
        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        vm.prank(user1);
        stakingRouter.claimPool(address(pool2), address(esGs), true, true);
        vm.prank(user2);
        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        vm.prank(user2);
        stakingRouter.claimPool(address(pool2), address(esGs), true, true);
        assertApproxEqRel(esGs.balanceOf(user1), 2*esGsRewards1, 1e4);
        assertApproxEqRel(esGs.balanceOf(user2), 2*esGsRewards2, 1e4);
        assertEq(gs.balanceOf(user1), 0);
        assertEq(gs.balanceOf(user2), 0);

        ////////// VESTING //////////
        vm.prank(user1);
        vm.expectRevert("StakingRouter: forbidden");
        stakingRouter.unstakeLpForAccount(user2, address(pool), address(esGs), lpAmount2);

        vm.prank(address(manager));
        stakingRouter.unstakeLpForAccount(user2, address(pool), address(esGs), lpAmount2);

        vm.startPrank(user2);
        vm.expectRevert("Vester: invalid _amount");
        stakingRouter.vestEsTokenForPool(address(pool), address(esGs), 0);
        esGsRewards2 = esGs.balanceOf(user2);
        vm.expectRevert();
        stakingRouter.vestEsTokenForPool(address(pool), address(esGs), esGsRewards2/2);

        stakingRouter.stakeLp(address(pool), address(esGs), lpAmount2);    // Stake Lp tokens again to satisfy average staked amounts
        stakingRouter.vestEsTokenForPool(address(pool), address(esGs), esGsRewards2/2);

        stakingRouter.stakeLp(address(pool2), address(esGs), lpAmount2);    // Stake Lp tokens again to satisfy average staked amounts
        stakingRouter.vestEsTokenForPool(address(pool2), address(esGs), esGsRewards2/2);

        vm.warp(block.timestamp + 180 days);

        stakingRouter.claimPool(address(pool2), address(esGs), true, true);
        assertEq(gs.balanceOf(user2), esGsRewards2/2);

        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertLt(gs.balanceOf(user2), esGsRewards2);

        vm.warp(block.timestamp + 365 days);

        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertEq(gs.balanceOf(user2), esGsRewards2);

        stakingRouter.claimPool(address(pool2), address(esGs), true, true);
        assertEq(gs.balanceOf(user2), esGsRewards2);

        vm.stopPrank();
    }

    /// @notice stake lp in pool -> claim -> vest -> claim
    function testUpdateVestingDuration(uint256 lpAmount1, uint256 lpAmount2) public {
        lpAmount1 = bound(lpAmount1, 1e18, 10000e18);
        lpAmount2 = bound(lpAmount2, 1e18, 10000e18);
        (address poolRewardTracker,,,,address vester) = stakingRouter.poolTrackers(address(pool), address(esGs));
        (address poolRewardTracker2,,,,address vester2) = stakingRouter.poolTrackers(address(pool2), address(esGs));

        uint256 lpBalanceBeforeUser1 = GammaPoolERC20(pool).balanceOf(user1);
        uint256 lpBalanceBeforeUser2 = GammaPoolERC20(pool).balanceOf(user2);

        ////////// STAKING //////////
        vm.prank(user1);
        stakingRouter.stakeLp(address(pool), address(esGs), lpAmount1);
        vm.prank(user1);
        stakingRouter.stakeLp(address(pool2), address(esGs), lpAmount1);
        vm.prank(user2);
        stakingRouter.stakeLp(address(pool), address(esGs), lpAmount2);
        vm.prank(user2);
        stakingRouter.stakeLp(address(pool2), address(esGs), lpAmount2);

        assertApproxEqRel(GammaPoolERC20(pool).balanceOf(user1), lpBalanceBeforeUser1 - lpAmount1, 1e4);
        assertApproxEqRel(GammaPoolERC20(pool).balanceOf(user2), lpBalanceBeforeUser2 - lpAmount2, 1e4);

        vm.warp(block.timestamp + 1 days);

        uint256 esGsRewards1 = 86400 * 1e16 * lpAmount1/(lpAmount1+lpAmount2);
        uint256 esGsRewards2 = 86400 * 1e16 * lpAmount2/(lpAmount1+lpAmount2);
        assertApproxEqRel(IRewardTracker(poolRewardTracker).claimable(user1), esGsRewards1, 1e4);
        assertApproxEqRel(IRewardTracker(poolRewardTracker).claimable(user2), esGsRewards2, 1e4);
        assertApproxEqRel(IRewardTracker(poolRewardTracker2).claimable(user1), esGsRewards1, 1e4);
        assertApproxEqRel(IRewardTracker(poolRewardTracker2).claimable(user2), esGsRewards2, 1e4);

        ////////// CLAIMING //////////
        vm.prank(user1);
        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        vm.prank(user1);
        stakingRouter.claimPool(address(pool2), address(esGs), true, true);
        vm.prank(user2);
        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        vm.prank(user2);
        stakingRouter.claimPool(address(pool2), address(esGs), true, true);
        assertApproxEqRel(esGs.balanceOf(user1), 2*esGsRewards1, 1e4);
        assertApproxEqRel(esGs.balanceOf(user2), 2*esGsRewards2, 1e4);
        assertEq(gs.balanceOf(user1), 0);
        assertEq(gs.balanceOf(user2), 0);

        ////////// VESTING //////////
        vm.prank(user1);
        vm.expectRevert("StakingRouter: forbidden");
        stakingRouter.unstakeLpForAccount(user2, address(pool), address(esGs), lpAmount2);

        vm.prank(address(manager));
        stakingRouter.unstakeLpForAccount(user2, address(pool), address(esGs), lpAmount2);

        vm.startPrank(user2);
        vm.expectRevert("Vester: invalid _amount");
        stakingRouter.vestEsTokenForPool(address(pool), address(esGs), 0);
        esGsRewards2 = esGs.balanceOf(user2);
        vm.expectRevert();
        stakingRouter.vestEsTokenForPool(address(pool), address(esGs), esGsRewards2/2);

        // pool is 365 days
        stakingRouter.stakeLp(address(pool), address(esGs), lpAmount2);    // Stake Lp tokens again to satisfy average staked amounts
        stakingRouter.vestEsTokenForPool(address(pool), address(esGs), esGsRewards2/2);

        // pool2 is 180 days
        stakingRouter.stakeLp(address(pool2), address(esGs), lpAmount2);    // Stake Lp tokens again to satisfy average staked amounts
        stakingRouter.vestEsTokenForPool(address(pool2), address(esGs), esGsRewards2/2);

        vm.warp(block.timestamp + 90 days);

        stakingRouter.claimPool(address(pool2), address(esGs), true, true);
        assertEq(gs.balanceOf(user2), esGsRewards2/4);

        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertEq(gs.balanceOf(user2), esGsRewards2/4 + esGsRewards2/8);

        vm.warp(block.timestamp + 90 days);

        assertLt(esGsRewards2/8 + IVester(vester).claimable(user2), esGsRewards2/2);
        assertApproxEqAbs(esGsRewards2/4 + IVester(vester2).claimable(user2), esGsRewards2/4
            + (esGsRewards2/4) * 90 / 180,10); // remaining amount is vesting over 180 days

        vm.stopPrank();

        vm.prank(address(stakingRouter));
        IVester(vester).setVestingDuration(90 days); // 360 days to 90 days
        vm.prank(address(stakingRouter));
        IVester(vester2).setVestingDuration(360 days); // 180 to 360 days

        assertEq(esGsRewards2/8 + IVester(vester).claimable(user2), esGsRewards2/2);
        assertLt(esGsRewards2/4 + IVester(vester2).claimable(user2), esGsRewards2/2);

        vm.startPrank(user2);
        stakingRouter.claimPool(address(pool2), address(esGs), true, true);
        assertApproxEqAbs(gs.balanceOf(user2), esGsRewards2/8 + esGsRewards2/4 + (esGsRewards2/4)*90/360,10);
        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertApproxEqAbs(gs.balanceOf(user2), esGsRewards2/2 + esGsRewards2/4 +(esGsRewards2/4)*90/360,10);

        vm.stopPrank();
    }

    /// @notice stake lp in pool -> claim -> vest -> claim
    function testVestingDuration(uint256 lpAmount1) public {
        lpAmount1 = bound(lpAmount1, 1e18, 10000e18);
        (address poolRewardTracker,,,,address vester) = stakingRouter.poolTrackers(address(pool), address(esGs));

        uint256 lpBalanceBeforeUser1 = GammaPoolERC20(pool).balanceOf(user1);

        ////////// STAKING //////////
        vm.startPrank(user1);
        stakingRouter.stakeLp(address(pool), address(esGs), lpAmount1);

        assertApproxEqRel(GammaPoolERC20(pool).balanceOf(user1), lpBalanceBeforeUser1 - lpAmount1, 1e4);

        vm.warp(block.timestamp + 1 days + 1);

        uint256 esGsRewards1 = 86400 * 1e16;
        assertApproxEqRel(IRewardTracker(poolRewardTracker).claimable(user1), esGsRewards1, 1e14);

        ////////// CLAIMING //////////
        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertApproxEqRel(esGs.balanceOf(user1), esGsRewards1, 1e14);
        assertEq(gs.balanceOf(user1), 0);

        ////////// VESTING //////////);
        // pool is 365 days
        stakingRouter.stakeLp(address(pool), address(esGs), lpAmount1);    // Stake Lp tokens again to satisfy average staked amounts

        uint256 esGSDeposit1 = esGsRewards1 / 2;
        stakingRouter.vestEsTokenForPool(address(pool), address(esGs), esGSDeposit1);

        vm.warp(block.timestamp + 365 days);

        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertEq(IVester(vester).balanceOf(user1), 0);

        uint256 vestedAmountBeforeClaim = IVester(vester).getVestedAmount(user1);
        assertGt(vestedAmountBeforeClaim, 0);

        stakingRouter.vestEsTokenForPool(address(pool), address(esGs), esGSDeposit1);
        assertEq(IVester(vester).balanceOf(user1), esGSDeposit1);

        uint256 vestedAmountAfterClaim = IVester(vester).getVestedAmount(user1);
        assertEq(vestedAmountAfterClaim, vestedAmountBeforeClaim*2);

        vm.warp(block.timestamp + ((365 days)/1));

        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertEq(IVester(vester).balanceOf(user1), 0);

        vm.stopPrank();
    }

    /// @notice stake lp in pool -> claim -> vest -> claim
    function testVestingDurationPartialVestDeposit(uint256 lpAmount) public {
        lpAmount = bound(lpAmount, 1e18, 10000e18);
        (address poolRewardTracker,,,,address vester) = stakingRouter.poolTrackers(address(pool), address(esGs));

        uint256 lpBalanceBeforeUser1 = GammaPoolERC20(pool).balanceOf(user1);

        ////////// STAKING //////////
        vm.startPrank(user1);
        stakingRouter.stakeLp(address(pool), address(esGs), lpAmount);

        assertApproxEqRel(GammaPoolERC20(pool).balanceOf(user1), lpBalanceBeforeUser1 - lpAmount, 1e4);

        vm.warp(block.timestamp + 1 days + 1);

        uint256 esGsRewards1 = 86400 * 1e16;
        assertApproxEqRel(IRewardTracker(poolRewardTracker).claimable(user1), esGsRewards1, 1e14);

        ////////// CLAIMING //////////
        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertApproxEqRel(esGs.balanceOf(user1), esGsRewards1, 1e14);
        assertEq(gs.balanceOf(user1), 0);

        ////////// VESTING //////////);
        // pool is 365 days
        stakingRouter.stakeLp(address(pool), address(esGs), lpAmount); // Stake Lp tokens again to satisfy average staked amounts

        uint256 esGSDeposit1 = esGsRewards1 / 2;
        stakingRouter.vestEsTokenForPool(address(pool), address(esGs), esGSDeposit1);

        vm.warp(block.timestamp + 180 days);

        uint256 vestedAmountBeforeClaim = IVester(vester).getVestedAmount(user1);
        assertGt(vestedAmountBeforeClaim, 0);

        stakingRouter.vestEsTokenForPool(address(pool), address(esGs), esGSDeposit1);
        assertEq(IVester(vester).balanceOf(user1), esGSDeposit1 + esGSDeposit1/2);

        uint256 vestedAmountAfterClaim = IVester(vester).getVestedAmount(user1);
        assertEq(vestedAmountAfterClaim, vestedAmountBeforeClaim*2);

        vm.warp(block.timestamp + ((270 days)/1)); // the total vesting should take longer because you doubled the deposit.
        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertGt(IVester(vester).balanceOf(user1), 0); // period restarted so it has to vest in a total of 360 days

        vm.warp(block.timestamp + ((180 days)/1));
        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertGt(IVester(vester).balanceOf(user1), 0);

        vm.warp(block.timestamp + ((360 days)/1));
        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertEq(IVester(vester).balanceOf(user1), 0);

        vm.stopPrank();
    }

    /// @notice stake lp in pool -> claim -> vest -> claim
    function testVestingDurationFullVestDeposit(uint256 lpAmount) public {
        lpAmount = bound(lpAmount, 1e18, 10000e18);
        (address poolRewardTracker,,,,address vester) = stakingRouter.poolTrackers(address(pool), address(esGs));

        uint256 lpBalanceBeforeUser1 = GammaPoolERC20(pool).balanceOf(user1);

        ////////// STAKING //////////
        vm.startPrank(user1);
        stakingRouter.stakeLp(address(pool), address(esGs), lpAmount);

        assertApproxEqRel(GammaPoolERC20(pool).balanceOf(user1), lpBalanceBeforeUser1 - lpAmount, 1e4);

        vm.warp(block.timestamp + 1 days + 1);

        uint256 esGsRewards1 = 86400 * 1e16;
        assertApproxEqRel(IRewardTracker(poolRewardTracker).claimable(user1), esGsRewards1, 1e14);

        ////////// CLAIMING //////////
        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertApproxEqRel(esGs.balanceOf(user1), esGsRewards1, 1e14);
        assertEq(gs.balanceOf(user1), 0);

        ////////// VESTING //////////);
        // pool is 365 days
        stakingRouter.stakeLp(address(pool), address(esGs), lpAmount); // Stake Lp tokens again to satisfy average staked amounts

        uint256 esGSDeposit1 = esGsRewards1 / 2;
        stakingRouter.vestEsTokenForPool(address(pool), address(esGs), esGSDeposit1);
        vm.warp(block.timestamp + 360 days);

        uint256 vestedAmountBeforeClaim = IVester(vester).getVestedAmount(user1);
        assertGt(vestedAmountBeforeClaim, 0);

        stakingRouter.vestEsTokenForPool(address(pool), address(esGs), esGSDeposit1);
        assertEq(IVester(vester).balanceOf(user1), esGSDeposit1);

        uint256 vestedAmountAfterClaim = IVester(vester).getVestedAmount(user1);
        assertEq(vestedAmountAfterClaim, vestedAmountBeforeClaim*2);

        vm.warp(block.timestamp + ((360 days)/1));

        stakingRouter.claimPool(address(pool), address(esGs), true, true);
        assertEq(IVester(vester).balanceOf(user1), 0);

        vm.stopPrank();
    }

    function testAutoStakeAndUnstake() public {
        (address poolRewardTracker,,,,) = stakingRouter.poolTrackers(address(pool), address(esGs));

        vm.startPrank(user1);
        usdc.approve(address(manager), type(uint256).max);
        weth.approve(address(manager), type(uint256).max);
        pool.approve(address(manager), type(uint256).max);

        uint256[] memory amountsDesired = new uint256[](2);
        uint256[] memory amountsMin = new uint256[](2);
        amountsDesired[0] = 1e21;
        amountsDesired[1] = 1e18;
        IPositionManager.DepositReservesParams memory params = IPositionManager.DepositReservesParams({
            protocolId: 1,
            cfmm: cfmm,
            to: user1,
            deadline: type(uint256).max,
            amountsDesired: amountsDesired,
            amountsMin: amountsMin
        });

        assertEq(IERC20(poolRewardTracker).balanceOf(user1), 0);
        (uint256[] memory reserves, uint256 shares) = manager.depositReservesAndStake(params, address(esGs));

        assertGt(reserves[0], 0);
        assertGt(reserves[1], 0);
        assertGt(shares, 0);

        assertEq(IERC20(poolRewardTracker).balanceOf(user1), shares);

        IPositionManager.WithdrawReservesParams memory params2 = IPositionManager.WithdrawReservesParams({
            protocolId: 1,
            cfmm: cfmm,
            to: user1,
            deadline: type(uint256).max,
            amount: shares,
            amountsMin: amountsMin
        });
        (uint256[] memory reserves2,) = manager.withdrawReservesAndUnstake(params2, address(esGs));
        assertApproxEqRel(reserves[0], reserves2[0], 1e2);
        assertApproxEqRel(reserves[1], reserves2[1], 1e2);
    }
}