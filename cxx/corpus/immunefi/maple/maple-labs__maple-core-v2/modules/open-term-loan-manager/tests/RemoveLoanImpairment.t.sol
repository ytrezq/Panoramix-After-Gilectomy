// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { LoanManagerFactory }     from "../contracts/LoanManagerFactory.sol";
import { LoanManagerInitializer } from "../contracts/LoanManagerInitializer.sol";

import { LoanManagerHarness } from "./utils/Harnesses.sol";
import { TestBase }           from "./utils/TestBase.sol";

import {
    MockFactory,
    MockGlobals,
    MockLoan,
    MockLoanFactory,
    MockPoolManager
} from "./utils/Mocks.sol";

contract RemoveLoanImpairmentBase is TestBase {

    event AccountingStateUpdated(uint256 issuanceRate_, uint112 accountedInterest_);
    event UnrealizedLossesUpdated(uint128 unrealizedLosses_);

    address governor     = makeAddr("governor");
    address poolDelegate = makeAddr("poolDelegate");

    LoanManagerHarness loanManager = new LoanManagerHarness();
    MockFactory        factory     = new MockFactory();
    MockGlobals        globals     = new MockGlobals();
    MockLoan           loan        = new MockLoan();
    MockLoanFactory    loanFactory = new MockLoanFactory();
    MockPoolManager    poolManager = new MockPoolManager();

    function setUp() public virtual {
        factory.__setMapleGlobals(address(globals));

        globals.__setGovernor(governor);

        loanManager.__setFactory(address(factory));
        loanManager.__setPoolManager(address(poolManager));

        poolManager.__setPoolDelegate(poolDelegate);

        loan.__setFactory(address(loanFactory));

        loanFactory.__setIsLoan(address(loan), true);
    }

}

contract RemoveLoanImpairmentFailureTests is RemoveLoanImpairmentBase {

    function test_removeLoanImpairment_paused() external {
        globals.__setFunctionPaused(true);

        vm.expectRevert("LM:PAUSED");
        loanManager.removeLoanImpairment(address(loan));
    }

    function test_removeLoanImpairment_notLoan() external {
        vm.expectRevert("LM:NOT_LOAN");
        vm.prank(poolDelegate);
        loanManager.removeLoanImpairment(address(loan));
    }

    function test_removeLoanImpairment_noAuth() external {
        loanManager.__setPaymentFor(address(loan), 0, 0, 1, 0);
        loanManager.__setImpairmentFor(address(loan), 1, false);

        vm.expectRevert("LM:RLI:NO_AUTH");
        loanManager.removeLoanImpairment(address(loan));
    }

    function test_removeLoanImpairment_poolDelegateAfterGovernor() external {
        loanManager.__setPaymentFor(address(loan), 0, 0, 1, 0);
        loanManager.__setImpairmentFor(address(loan), 1, true);

        vm.expectRevert("LM:RLI:NO_AUTH");
        vm.prank(poolDelegate);
        loanManager.removeLoanImpairment(address(loan));
    }

}

contract RemoveLoanImpairmentSuccessTests is RemoveLoanImpairmentBase {

    uint256 constant principal    = 1_000_000e6;
    uint256 constant duration     = 1_000_000 seconds;
    uint256 constant issuanceRate = (1_000e6 * 1e27) / duration;

    uint256 start = block.timestamp;

    function setUp() public override {
        super.setUp();

        loan.__setDateFunded(start);
        loan.__setPrincipal(principal);
        loan.__setPaymentDueDate(start + duration);

        loanManager.__setPaymentFor({
            loan_:                      address(loan),
            platformManagementFeeRate_: 0,
            delegateManagementFeeRate_: 0,
            startDate_:                 start,
            issuanceRate_:              issuanceRate
        });

        loanManager.__setImpairmentFor({
            loan_:               address(loan),
            impairedDate_:       start + duration / 2,
            impairedByGovernor_: false
        });

        loanManager.__setAccountedInterest((issuanceRate * (duration / 2)) / 1e27);
        loanManager.__setDomainStart(start + duration / 2);
        loanManager.__setPrincipalOut(principal);
        loanManager.__setUnrealizedLosses(principal + (issuanceRate * (duration / 2)) / 1e27);

        vm.warp(start + duration);  // Warp to time after impairment.
    }

    function test_removeLoanImpairment_acl_governor_success() external {
        vm.prank(governor);
        loanManager.removeLoanImpairment(address(loan));
    }

    function test_removeLoanImpairment_success() public {
        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start + duration / 2,
            accountedInterest:     (issuanceRate * (duration / 2)) / 1e27,
            accruedInterest:       0,
            assetsUnderManagement: principal + (issuanceRate * (duration / 2)) / 1e27,
            principalOut:          principal,
            unrealizedLosses:      principal + (issuanceRate * (duration / 2)) / 1e27,
            issuanceRate:          0
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start,
            issuanceRate: issuanceRate
        });

        assertImpairment({
            loanManager:        address(loanManager),
            loan:               address(loan),
            impairedDate:       start + duration / 2,
            impairedByGovernor: false
        });

        loan.__expectCall();
        loan.removeImpairment();

        vm.prank(poolDelegate);
        loanManager.removeLoanImpairment(address(loan));

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start + duration,
            accountedInterest:     (issuanceRate * duration) / 1e27,
            accruedInterest:       0,
            assetsUnderManagement: principal + (issuanceRate * duration) / 1e27,
            principalOut:          principal,
            unrealizedLosses:      0,
            issuanceRate:          issuanceRate
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start,
            issuanceRate: issuanceRate
        });

        assertImpairment({
            loanManager:        address(loanManager),
            loan:               address(loan),
            impairedDate:       0,
            impairedByGovernor: false
        });
    }

    function test_removeLoanImpairment_success_alreadyUnimpaired() external {
        // TODO: This can be done cleaner by setting up harness state, but then it undoes `setUp`.
        test_removeLoanImpairment_success();

        vm.warp(start + (3 * duration) / 2);

        loan.__expectCall();
        loan.removeImpairment();

        vm.prank(poolDelegate);
        loanManager.removeLoanImpairment(address(loan));

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start + duration,
            accountedInterest:     (issuanceRate * duration) / 1e27,
            accruedInterest:       (issuanceRate * duration / 2) / 1e27,
            assetsUnderManagement: principal + (issuanceRate * 3 * duration / 2) / 1e27,  // accountedInterest + accruedInterest
            principalOut:          principal,
            unrealizedLosses:      0,
            issuanceRate:          issuanceRate
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start,
            issuanceRate: issuanceRate
        });

        assertImpairment({
            loanManager:        address(loanManager),
            loan:               address(loan),
            impairedDate:       0,
            impairedByGovernor: false
        });
    }

}


