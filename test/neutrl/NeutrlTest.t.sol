// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {NeutrlDeploy} from "./NeutrlDeploy.t.sol";
import {IsNUSD} from "../../contracts/tranches/strategies/neutrl/IsNUSD.sol";
import {ICooldown} from "../../contracts/tranches/interfaces/cooldown/ICooldown.sol";

/**
 * @title NeutrlTest
 * @notice Unit tests for the Neutrl Strategy
 * @dev This test suite covers various deposit and withdrawal scenarios for Asset Lock cooldown mechanism
 */
contract NeutrlTest is NeutrlDeploy {
    // Test users
    address public alice;
    address public bob;

    // Test amounts
    uint256 constant INITIAL_BALANCE = 10000 ether;
    uint256 constant DEPOSIT_AMOUNT = 1000 ether;
    uint256 constant MIN_SHARES = 1 ether;

    function setUp() public override {
        super.setUp();

        // Create test users
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy the Strata stack
        _deployStrataStack();

        // Mint NUSD to test users
        _mintNUSD(alice, INITIAL_BALANCE);
        _mintNUSD(bob, INITIAL_BALANCE);

        // For testing withdrawals without the sNUSD cooldown affecting results,
        // we can optionally disable the sNUSD cooldown
        // This is done per-test as needed
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DepositNUSD_ToJrtVault() public {
        vm.startPrank(alice);

        uint256 balanceBefore = IERC20(NUSD).balanceOf(alice);

        // Approve and deposit NUSD into JRT vault
        IERC20(NUSD).approve(address(jrtVault), DEPOSIT_AMOUNT);
        uint256 shares = jrtVault.deposit(NUSD, DEPOSIT_AMOUNT, alice);

        // Verify shares received
        assertGt(shares, 0, "Should receive shares");
        assertEq(jrtVault.balanceOf(alice), shares, "Alice should have shares");

        // Verify NUSD was transferred
        uint256 balanceAfter = IERC20(NUSD).balanceOf(alice);
        assertEq(balanceBefore - balanceAfter, DEPOSIT_AMOUNT, "NUSD should be transferred");

        // Verify sNUSD was staked in strategy
        uint256 strategyBalance = IERC4626(sNUSD).balanceOf(address(strategy));
        assertEq(strategyBalance, DEPOSIT_AMOUNT, "Strategy should have deposited NUSD");

        vm.stopPrank();
    }

    function test_DepositNUSD_ToSrtVault() public {
        // First deposit to JRT to meet minimum ratio requirements
        _depositToJrt(alice, DEPOSIT_AMOUNT * 2);

        vm.startPrank(alice);

        uint256 balanceBefore = IERC20(NUSD).balanceOf(alice);

        // Approve and deposit NUSD into SRT vault
        IERC20(NUSD).approve(address(srtVault), DEPOSIT_AMOUNT);
        uint256 shares = srtVault.deposit(NUSD, DEPOSIT_AMOUNT, alice);

        // Verify shares received
        assertGt(shares, 0, "Should receive shares");
        assertEq(srtVault.balanceOf(alice), shares, "Alice should have shares");

        // Verify NUSD was transferred
        uint256 balanceAfter = IERC20(NUSD).balanceOf(alice);
        assertEq(balanceBefore - balanceAfter, DEPOSIT_AMOUNT, "NUSD should be transferred");

        uint256 strategyBalance = IERC4626(sNUSD).balanceOf(address(strategy));
        assertEq(strategyBalance, 3 * DEPOSIT_AMOUNT, "Strategy should have deposited NUSD");

        vm.stopPrank();
    }

    function test_DepositSNUSD_ToJrtVault() public {
        // First stake NUSD to get sNUSD
        uint256 sNUSDAmount = _stakeNUSDForSNUSD(alice, DEPOSIT_AMOUNT);

        vm.startPrank(alice);

        // Approve and deposit sNUSD into JRT vault
        IERC20(sNUSD).approve(address(jrtVault), sNUSDAmount);
        uint256 shares = jrtVault.deposit(sNUSD, sNUSDAmount, alice);

        // Verify shares received
        assertGt(shares, 0, "Should receive shares");
        assertEq(jrtVault.balanceOf(alice), shares, "Alice should have shares");

        vm.stopPrank();
    }

    function test_DepositToReceiver() public {
        vm.startPrank(alice);

        // Approve and deposit NUSD to Bob as receiver
        IERC20(NUSD).approve(address(jrtVault), DEPOSIT_AMOUNT);
        uint256 shares = jrtVault.deposit(NUSD, DEPOSIT_AMOUNT, bob);

        // Verify Bob received the shares
        assertEq(jrtVault.balanceOf(bob), shares, "Bob should have shares");
        assertEq(jrtVault.balanceOf(alice), 0, "Alice should have no shares");

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test withdrawing NUSD from JRT vault without cooldown
     * @dev Test the cooldown mechanism for NUSD when withdrawing from JRT vault
     */
    function test_WithdrawNUSD_FromJrtVault_NoCooldown() public {
        // Disable sNUSD protocol cooldown for this test
        _disableSNUSDCooldown();

        // Deposit first
        _depositToJrt(alice, DEPOSIT_AMOUNT);

        vm.startPrank(alice);

        uint256 shares = jrtVault.balanceOf(alice);
        uint256 withdrawAmount = shares - MIN_SHARES; // Leave minimum shares

        uint256 nusdBefore = IERC20(NUSD).balanceOf(alice);

        // Withdraw NUSD
        uint256 assetsReceived = jrtVault.redeem(NUSD, withdrawAmount, alice, alice);

        uint256 nusdAfter = IERC20(NUSD).balanceOf(alice);

        // Verify withdrawal
        assertGt(assetsReceived, 0, "Should receive assets");
        assertEq(nusdAfter - nusdBefore, assetsReceived, "Alice's NUSD balance should increase");
        assertEq(jrtVault.balanceOf(alice), MIN_SHARES, "Should have minimum shares left");

        vm.stopPrank();
    }

    /**
     * @notice Test withdrawing sNUSD from JRT vault
     * @dev Test the cooldown mechanism for sNUSD when withdrawing from JRT vault
     */
    function test_WithdrawSNUSD_FromJrtVault() public {
        // Deposit 1000 NUSD to JRT vault
        _depositToJrt(alice, DEPOSIT_AMOUNT);

        vm.startPrank(alice);

        uint256 shares = jrtVault.balanceOf(alice);
        uint256 withdrawShares = shares - MIN_SHARES;
        assertEq(withdrawShares, DEPOSIT_AMOUNT - MIN_SHARES);

        uint256 sNUSDBefore = IERC20(sNUSD).balanceOf(alice);
        assertEq(sNUSDBefore, 0, "Alice has no sNUSD before withdrawal");

        uint256 cooldownBalanceBefore = IERC20(sNUSD).balanceOf(address(erc20Cooldown));
        assertEq(cooldownBalanceBefore, 0, "Cooldown contract has no sNUSD before withdrawal");

        // Withdraw as sNUSD (goes through ERC20Cooldown if cooldown is set)
        uint256 tokensReceived = jrtVault.redeem(sNUSD, withdrawShares, alice, alice);

        // When cooldown is enabled (7 days for JRT), tokens go to cooldown
        // Check if user received sNUSD directly or it went to cooldown
        uint256 cooldownBalanceAfter = IERC20(sNUSD).balanceOf(address(erc20Cooldown));

        // 7 days cooldown is set for JRT
        // Check cooldown contract received the tokens
        assertEq(cooldownBalanceAfter - cooldownBalanceBefore, tokensReceived, "Cooldown contract should hold sNUSD");

        // Check alice's pending balance in cooldown
        ICooldown.TBalanceState memory cooldownState = erc20Cooldown.balanceOf(IERC20(sNUSD), alice);
        assertEq(cooldownState.pending, tokensReceived, "Alice should have pending sNUSD in cooldown");
        assertEq(cooldownState.claimable, 0, "Alice should have no claimable sNUSD yet");
        assertEq(cooldownState.totalRequests, 1, "Alice should have one cooldown request");

        uint256 sNUSDBeforeFinalise = IERC20(sNUSD).balanceOf(alice);

        // After cooldown period is over, claim the sNUSD
        vm.warp(block.timestamp + 7 days);

        cooldownState = erc20Cooldown.balanceOf(IERC20(sNUSD), alice);
        assertEq(cooldownState.claimable, tokensReceived, "Alice should have claimable sNUSD after cooldown period");

        uint256 claimed = erc20Cooldown.finalize(IERC20(sNUSD), alice);
        assertEq(claimed, tokensReceived, "Should claim sNUSD");

        uint256 sNUSDAfterFinalise = IERC20(sNUSD).balanceOf(alice);
        assertEq(sNUSDAfterFinalise - sNUSDBeforeFinalise, claimed, "Should receive sNUSD directly");
        assertEq(claimed, DEPOSIT_AMOUNT - MIN_SHARES);
        vm.stopPrank();
    }

    /**
     * @notice Test withdrawing NUSD from SRT vault
     * @dev Test the cooldown mechanism for NUSD when withdrawing from SRT vault
     */
    function test_WithdrawNUSD_FromSrtVault_NoCooldown() public {
        // Disable sNUSD protocol cooldown
        _disableSNUSDCooldown();

        // Deposit to JRT first (for coverage ratio)
        _depositToJrt(alice, DEPOSIT_AMOUNT * 2);

        // Deposit to SRT
        _depositToSrt(alice, DEPOSIT_AMOUNT);

        vm.startPrank(alice);

        uint256 shares = srtVault.balanceOf(alice);
        uint256 withdrawShares = shares - MIN_SHARES;

        uint256 nusdBefore = IERC20(NUSD).balanceOf(alice);

        // Withdraw NUSD (SRT has 0 cooldown in our setup)
        uint256 assetsReceived = srtVault.redeem(NUSD, withdrawShares, alice, alice);

        uint256 nusdAfter = IERC20(NUSD).balanceOf(alice);

        // Verify withdrawal
        assertGt(assetsReceived, 0, "Should receive assets");
        assertEq(nusdAfter - nusdBefore, assetsReceived, "NUSD balance should increase");

        vm.stopPrank();
    }

    /**
     * @notice Test withdrawing NUSD from JRT vault with sNUSD cooldown
     * @dev Test the cooldown mechanism for NUSD when withdrawing from JRT vault with sNUSD cooldown
     */
    function test_WithdrawNUSD_FinalizeAfterCooldown() public {
        // Bob deposits to maintain sNUSD liquidity (prevents MinSharesViolation)
        _depositToJrt(bob, DEPOSIT_AMOUNT);

        // Alice deposits
        _depositToJrt(alice, DEPOSIT_AMOUNT);

        vm.startPrank(alice);

        uint256 shares = jrtVault.balanceOf(alice);
        uint256 withdrawShares = shares - MIN_SHARES;

        uint256 nusdBefore = IERC20(NUSD).balanceOf(alice);

        // Withdraw NUSD
        jrtVault.redeem(NUSD, withdrawShares, alice, alice);

        // NUSD should NOT be received immediately due to sNUSD cooldown
        uint256 nusdAfter = IERC20(NUSD).balanceOf(alice);
        assertEq(nusdAfter, nusdBefore, "NUSD should not be received immediately");

        vm.stopPrank();

        // Check unstake cooldown balance
        (uint256 pending, uint256 claimable,,, uint256 totalRequests) = _getUnstakeCooldownBalance(alice);

        assertGt(pending, 0, "Should have pending amount in cooldown");
        assertEq(claimable, 0, "Should have no claimable amount yet");
        assertEq(totalRequests, 1, "Should have one request");

        // Get sNUSD cooldown duration
        uint24 cooldownDuration = IsNUSD(sNUSD).cooldownDuration();

        // Warp time past cooldown
        vm.warp(block.timestamp + cooldownDuration);

        // Check claimable amount
        (pending, claimable,,,) = _getUnstakeCooldownBalance(alice);
        assertEq(pending, 0, "Should have no pending amount");
        assertGt(claimable, 0, "Should have claimable amount");

        nusdBefore = IERC20(NUSD).balanceOf(alice);

        // Finalize the cooldown
        uint256 claimed = unstakeCooldown.finalize(IERC20(sNUSD), alice);
        console2.log("claimed", claimed);

        nusdAfter = IERC20(NUSD).balanceOf(alice);

        // Verify NUSD received
        assertGt(claimed, 0, "Should claim tokens");
        assertEq(nusdAfter - nusdBefore, claimed, "Should receive NUSD");
    }

    function test_WithdrawSNUSD_FromSrt_NoCooldown() public {
        // Deposit to JRT first
        _depositToJrt(alice, DEPOSIT_AMOUNT * 2);

        // Deposit to SRT
        _depositToSrt(alice, DEPOSIT_AMOUNT);

        vm.startPrank(alice);

        uint256 shares = srtVault.balanceOf(alice);
        uint256 withdrawShares = shares - MIN_SHARES;

        uint256 sNUSDBefore = IERC20(sNUSD).balanceOf(alice);

        // Withdraw as sNUSD from SRT (0 cooldown in our setup)
        uint256 tokensReceived = srtVault.redeem(sNUSD, withdrawShares, alice, alice);

        // SRT has 0 cooldown, so sNUSD should be received immediately
        uint256 sNUSDAfter = IERC20(sNUSD).balanceOf(alice);
        assertEq(sNUSDAfter - sNUSDBefore, tokensReceived, "Should receive sNUSD directly");

        vm.stopPrank();
    }

    function test_MultipleWithdrawRequests() public {
        // Bob deposits to maintain sNUSD liquidity (prevents MinSharesViolation)
        _depositToJrt(bob, DEPOSIT_AMOUNT);

        // Deposit a larger amount
        _depositToJrt(alice, DEPOSIT_AMOUNT * 5);

        vm.startPrank(alice);

        // Make multiple withdrawal requests
        uint256 withdrawAmount = DEPOSIT_AMOUNT;

        jrtVault.withdraw(NUSD, withdrawAmount, alice, alice);

        vm.warp(block.timestamp + 1 hours);

        jrtVault.withdraw(NUSD, withdrawAmount, alice, alice);

        vm.warp(block.timestamp + 1 hours);

        jrtVault.withdraw(NUSD, withdrawAmount, alice, alice);

        vm.stopPrank();

        // Check we have multiple pending requests
        (,,,, uint256 totalRequests) = _getUnstakeCooldownBalance(alice);
        assertEq(totalRequests, 3, "Should have 3 pending requests");

        // Warp past all cooldowns
        uint24 cooldownDuration = IsNUSD(sNUSD).cooldownDuration();
        vm.warp(block.timestamp + cooldownDuration);

        // Finalize all
        uint256 claimed = unstakeCooldown.finalize(IERC20(sNUSD), alice);
        assertGt(claimed, 0, "Should claim all pending tokens");
        assertEq(claimed, DEPOSIT_AMOUNT * 3, "Should claim all pending tokens");
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_RevertOnZeroDeposit() public {
        vm.startPrank(alice);
        IERC20(NUSD).approve(address(jrtVault), 1);

        vm.expectRevert();
        jrtVault.deposit(NUSD, 0, alice);

        vm.stopPrank();
    }

    function test_RevertOnExceedingMaxWithdraw() public {
        _depositToJrt(alice, DEPOSIT_AMOUNT);

        vm.startPrank(alice);

        uint256 maxWithdraw = jrtVault.maxWithdraw(alice);

        vm.expectRevert();
        jrtVault.withdraw(NUSD, maxWithdraw + 1 ether, alice, alice);

        vm.stopPrank();
    }

    function test_TotalAssets() public {
        _depositToJrt(alice, DEPOSIT_AMOUNT);
        _depositToJrt(bob, DEPOSIT_AMOUNT);

        uint256 totalAssets = strategy.totalAssets();
        assertGt(totalAssets, 0, "Total assets should be positive");

        // Total assets should be approximately equal to deposits (minus any fees)
        assertApproxEqRel(totalAssets, DEPOSIT_AMOUNT * 2, 0.01e18, "Total assets should match deposits");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _mintNUSD(address to, uint256 amount) internal {
        // Use deal to give NUSD to the user
        deal(NUSD, to, amount);
    }

    function _stakeNUSDForSNUSD(address user, uint256 nusdAmount) internal returns (uint256 sNUSDAmount) {
        vm.startPrank(user);

        IERC20(NUSD).approve(sNUSD, nusdAmount);
        sNUSDAmount = IERC4626(sNUSD).deposit(nusdAmount, user);

        vm.stopPrank();
    }

    function _depositToJrt(address user, uint256 amount) internal {
        vm.startPrank(user);

        IERC20(NUSD).approve(address(jrtVault), amount);
        jrtVault.deposit(NUSD, amount, user);

        vm.stopPrank();
    }

    function _depositToSrt(address user, uint256 amount) internal {
        vm.startPrank(user);

        IERC20(NUSD).approve(address(srtVault), amount);
        srtVault.deposit(NUSD, amount, user);

        vm.stopPrank();
    }

    function _disableSNUSDCooldown() internal {
        // Get sNUSD admin using the IERC5313 owner() function
        address admin = _getSNUSDAdmin();

        vm.startPrank(admin);

        // Call setCooldownDuration(0) to disable cooldown
        (bool success,) = sNUSD.call(abi.encodeWithSignature("setCooldownDuration(uint24)", uint24(0)));
        require(success, "Failed to disable cooldown");

        vm.stopPrank();

        // Verify cooldown is disabled
        assertEq(IsNUSD(sNUSD).cooldownDuration(), 0, "Cooldown should be disabled");
    }

    function _getSNUSDAdmin() internal view returns (address) {
        // sNUSD uses SingleAdminAccessControl which implements IERC5313
        // The owner() function returns the current admin
        (bool success, bytes memory data) = sNUSD.staticcall(abi.encodeWithSignature("owner()"));
        require(success, "Failed to get sNUSD owner");
        return abi.decode(data, (address));
    }

    function _getUnstakeCooldownBalance(address user)
        internal
        view
        returns (
            uint256 pending,
            uint256 claimable,
            uint256 nextUnlockAt,
            uint256 nextUnlockAmount,
            uint256 totalRequests
        )
    {
        ICooldown.TBalanceState memory state = unstakeCooldown.balanceOf(IERC20(sNUSD), user);
        return (state.pending, state.claimable, state.nextUnlockAt, state.nextUnlockAmount, state.totalRequests);
    }
}
