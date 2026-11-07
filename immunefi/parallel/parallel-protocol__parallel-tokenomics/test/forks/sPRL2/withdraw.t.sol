// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "test/forks/Fork.t.sol";

contract SPRL2_Withdraw_Fork_Test is Fork_Test {
    uint256 exactBptAmount = 1e18;
    uint256 prlAmountDeposited;
    uint256 wethAmountDeposited;

    function setUp() public override {
        super.setUp();
        sigUtils = new SigUtils(prl.DOMAIN_SEPARATOR());

        vm.startPrank(users.alice.addr);
        deal(address(prl), address(users.alice.addr), INITIAL_BALANCE);
        deal(address(weth), address(users.alice.addr), INITIAL_BALANCE);
        weth.approve(address(sprl2), type(uint256).max);

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            _signPermitData(users.alice.privateKey, address(sprl2), INITIAL_BALANCE, address(prl));

        (uint256[] memory amountsIn,) =
            sprl2.depositPRLAndWeth(INITIAL_BALANCE, INITIAL_BALANCE, exactBptAmount, deadline, v, r, s);
        prlAmountDeposited = amountsIn[0];
        wethAmountDeposited = amountsIn[1];
    }

    modifier requestWithdrawal() {
        sprl2.requestWithdraw(exactBptAmount);
        _;
    }

    function test_fork_sPRL2_WithdrawBPT() external requestWithdrawal {
        skip(sprl2.timeLockDuration());
        uint256 aliceBptBalance = sprl2.balanceOf(users.alice.addr);
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = 0;
        sprl2.withdrawBPT(requestIds, DEFAULT_PENALTY_PERCENTAGE);
        assertEq(sprl2.balanceOf(users.alice.addr), 0);
        assertEq(bpt.balanceOf(users.alice.addr), aliceBptBalance + exactBptAmount);
    }

    function test_fork_sPRL2_WithdrawPRLAndWeth() external requestWithdrawal {
        skip(sprl2.timeLockDuration());
        uint256 alicePrlBalance = prl.balanceOf(users.alice.addr);
        uint256 aliceWethBalance = weth.balanceOf(users.alice.addr);

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = 0;
        // Calculate the minimum amounts to withdraw 1% slippage
        uint256 minPrlAmount = prlAmountDeposited * 99 / 100;
        uint256 minWethAmount = wethAmountDeposited * 99 / 100;

        (uint256 prlAmount, uint256 wethAmount) =
            sprl2.withdrawPRLAndWeth(requestIds, minPrlAmount, minWethAmount, DEFAULT_PENALTY_PERCENTAGE);

        assertEq(sprl2.balanceOf(users.alice.addr), 0);
        assertEq(prl.balanceOf(users.alice.addr), alicePrlBalance + prlAmount);
        assertEq(weth.balanceOf(users.alice.addr), aliceWethBalance + wethAmount);
    }
}
