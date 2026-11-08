// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Vm } from "@forge-std/Test.sol";

struct Users {
     // Admin
    Vm.Wallet admin;
    // DAO.
    Vm.Wallet dao;
    // Guardian.
    Vm.Wallet guardian;
    // Fees recipient.
    Vm.Wallet feesRecipient;
    // Impartial user.
    Vm.Wallet alice;
    // Impartial user.
    Vm.Wallet bob;
    // Malicious user.
    Vm.Wallet hacker;
}
