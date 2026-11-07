// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import "./AccessControlManagerGrantCall.sol";
import "./AccountingOnAprChangedSandwich.sol";
import "./AccountingRetroactiveAPR.sol";
import "./AccountingRiskLag.sol";
import "./AccountingRiskDoS.sol";
import "./JrtSupplyRunaway.sol";
import "./ReserveWithdrawalUnitMismatch.sol";
import "./TrancheMaxMint.sol";
import "./WithdrawGriefingDoS.sol";

import "@openzeppelin/contracts/access/IAccessControl.sol";

contract GuardianPoCsTest is Test {

    function testReserveWithdrawalUnitMismatchTest_testReserveWithdrawalShareMismatch() public {
        ReserveWithdrawalUnitMismatchTest reserveWithdrawalUnitMismatchTest = new ReserveWithdrawalUnitMismatchTest();
        reserveWithdrawalUnitMismatchTest.setUp();
        vm.expectRevert();
        reserveWithdrawalUnitMismatchTest.testReserveWithdrawalShareMismatch();
    }

    function testJrtSupplyRunawayTest_test_poc() public {
        JrtSupplyRunawayTest jrtSupplyRunawayTest = new JrtSupplyRunawayTest();
        jrtSupplyRunawayTest.setUp();
        vm.expectRevert(bytes("(PoC) JRT deposit is still enabled"));
        jrtSupplyRunawayTest.testJrtSupplyRunawayDueToTinyPrice();
    }

    function testWithdrawGriefingDoS_test_poc() public {
        WithdrawGriefingDoS withdrawGriefingDoS = new WithdrawGriefingDoS();
        withdrawGriefingDoS.setUp();
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            0xa959355654849CbEAbBf65235f8235833b9e031D,
            0x97d8f58e0f008a842799f9fb6a4e6212ac93db0249409467f149ba102924e880
        ));
        withdrawGriefingDoS.test_poc();
    }

    function testAccountingOnAprChangedSandwichTest_testOnAprChangedCanBeSandwiched() public {
        AccountingOnAprChangedSandwichTest accountingOnAprChangedSandwichTest = new AccountingOnAprChangedSandwichTest();
        accountingOnAprChangedSandwichTest.setUp();
        vm.expectRevert(bytes("APR must stay sticky"));
        accountingOnAprChangedSandwichTest.testOnAprChangedCanBeSandwiched();
    }

    function testAccessControlManagerGrantCallTest_testGrantCallFallbackSelectorGivesDefaultAdmin() public {
        AccessControlManagerGrantCallTest accessControlManagerGrantCallTest = new AccessControlManagerGrantCallTest();
        accessControlManagerGrantCallTest.setUp();
        vm.expectRevert(bytes("StrictPermissionOnly"));
        accessControlManagerGrantCallTest.testGrantCallFallbackSelectorGivesDefaultAdmin();
    }

    function testAccountingRiskLag_testRiskUsesPreSplitBalances() public {
        AccountingRiskLagTest accountingRiskLagTest = new AccountingRiskLagTest();
        accountingRiskLagTest.setUp();
        vm.expectRevert(bytes(">=100%"));
        accountingRiskLagTest.testRiskUsesPreSplitBalances();
    }

    function testTrancheMaxMintTest_testJrtMaxMintRevertsWhenSharePriceBelowOne() public {
        TrancheMaxMintTest trancheMaxMintTest = new TrancheMaxMintTest();
        trancheMaxMintTest.setUp();
        //vm.expectRevert();
        trancheMaxMintTest.testJrtMaxMintRevertsWhenSharePriceBelowOne();
    }

    function testAccountingRiskDoSTest_testRiskOverOneHundredPercentRevertsUpdate() public {
        AccountingRiskDoSTest accountingRiskDoSTest = new AccountingRiskDoSTest();
        accountingRiskDoSTest.setUp();
        vm.expectRevert(">=100%");
        accountingRiskDoSTest.testRiskOverOneHundredPercentRevertsUpdate();
    }

    function testAccountingRetroactiveAPR_testRiskOverOneHundredPercentRevertsUpdate() public {
        AccountingRetroactiveAPR accountingRetroactiveAPR = new AccountingRetroactiveAPR();
        accountingRetroactiveAPR.setUp();
        vm.expectRevert("index accrues at new apr");
        accountingRetroactiveAPR.testRetroactiveAPRJump();
    }

}
