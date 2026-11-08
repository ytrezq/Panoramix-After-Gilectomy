// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "test/forks/Fork.t.sol";

contract SPRL2_Deposits_Fork_Test is Fork_Test {
    uint256 exactBptAmount = 1e18;

    function setUp() public override {
        super.setUp();
        sigUtils = new SigUtils(prl.DOMAIN_SEPARATOR());

        vm.startPrank(users.alice.addr);
        deal(address(prl), address(users.alice.addr), INITIAL_BALANCE);
        deal(address(weth), address(users.alice.addr), INITIAL_BALANCE);
    }

    function test_fork_sPRL2_DepositBPT() external {
        prl.approve(address(permit2), type(uint256).max);
        weth.approve(address(permit2), type(uint256).max);

        uint48 deadline = uint48(block.timestamp + 15);
        permit2.approve(address(prl), address(balancerV3RouterMock), uint160(INITIAL_BALANCE), deadline);
        permit2.approve(address(weth), address(balancerV3RouterMock), uint160(INITIAL_BALANCE), deadline);

        balancerV3RouterMock.addLiquidityProportional(
            address(bpt), _getMaxDepositAmountParams(INITIAL_BALANCE, INITIAL_BALANCE), exactBptAmount, false, ""
        );
        assertEq(bpt.balanceOf(users.alice.addr), exactBptAmount);

        bpt.approve(address(sprl2), exactBptAmount);
        sprl2.depositBPT(exactBptAmount);
        assertEq(sprl2.balanceOf(users.alice.addr), exactBptAmount);
        assertEq(bpt.balanceOf(users.alice.addr), 0);
    }

    function test_fork_sPRL2_DepositPRLAndWeth() external {
        weth.approve(address(sprl2), type(uint256).max);

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            _signPermitData(users.alice.privateKey, address(sprl2), INITIAL_BALANCE, address(prl));

        (uint256[] memory amountsIn, uint256 bptAmount) =
            sprl2.depositPRLAndWeth(INITIAL_BALANCE, INITIAL_BALANCE, exactBptAmount, deadline, v, r, s);
        assertEq(bptAmount, exactBptAmount);
        assertEq(INITIAL_BALANCE - amountsIn[0], prl.balanceOf(users.alice.addr));
        assertEq(INITIAL_BALANCE - amountsIn[1], weth.balanceOf(users.alice.addr));
        assertEq(bpt.balanceOf(users.alice.addr), 0);
        assertEq(sprl2.balanceOf(users.alice.addr), exactBptAmount);
    }

    function _getMaxDepositAmountParams(
        uint256 maxPrlAmount,
        uint256 maxWethAmount
    )
        internal
        view
        returns (uint256[] memory maxAmountsIn)
    {
        maxAmountsIn = new uint256[](2);
        (maxAmountsIn[0], maxAmountsIn[1]) =
            address(weth) > address(prl) ? (maxPrlAmount, maxWethAmount) : (maxWethAmount, maxPrlAmount);
    }
}
