// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { MockERC20 } from "../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { LoanManagerHarness } from "./utils/Harnesses.sol";
import { TestBase }           from "./utils/TestBase.sol";

import {
    MockFactory,
    MockGlobals,
    MockLoan,
    MockLoanFactory,
    MockPoolManager
} from "./utils/Mocks.sol";

contract ClaimTestBase is TestBase {

    address borrower     = makeAddr("borrower");
    address poolDelegate = makeAddr("poolDelegate");
    address pool         = makeAddr("pool");

    LoanManagerHarness loanManager = new LoanManagerHarness();
    MockERC20          asset       = new MockERC20("A", "A", 18);
    MockFactory        factory     = new MockFactory();
    MockGlobals        globals     = new MockGlobals();
    MockLoan           loan        = new MockLoan();
    MockLoanFactory    loanFactory = new MockLoanFactory();
    MockPoolManager    poolManager = new MockPoolManager();

    function setUp() public virtual {
        globals.__setIsBorrower(true);

        factory.__setMapleGlobals(address(globals));

        poolManager.__setAsset(address(asset));
        poolManager.__setPool(pool);
        poolManager.__setPoolDelegate(address(poolDelegate));
        poolManager.__setHasSufficientCover(true);

        loan.__setFactory(address(loanFactory));

        loanManager.__setFactory(address(factory));
        loanManager.__setFundsAsset(address(asset));
        loanFactory.__setIsLoan(address(loan), true);
        loanManager.__setLocked(1);
        loanManager.__setPoolManager(address(poolManager));
    }

}

contract ClaimFailureTests is ClaimTestBase {

    function test_claim_notPaused() public {
        globals.__setFunctionPaused(true);

        vm.expectRevert("LM:PAUSED");
        loanManager.claim({
            principal_:          1,
            interest_:           0,
            delegateServiceFee_: 0,
            platformServiceFee_: 0,
            nextPaymentDueDate_: 0
        });
    }

    function test_claim_reentrancy() public {
        // TODO: Needs reentering ERC20.
    }

    function test_claim_notLoan() public {
        vm.expectRevert("LM:NOT_LOAN");
        vm.prank(address(loan));
        loanManager.claim({
            principal_:          1,
            interest_:           0,
            delegateServiceFee_: 0,
            platformServiceFee_: 0,
            nextPaymentDueDate_: 0
        });
    }

    function test_claim_invalidState1() public {
        loanManager.__setPaymentFor(address(loan), 0, 0, block.timestamp, 0);
        // Requesting more principal but providing no new payment due date.
        vm.expectRevert("LM:C:INVALID");
        vm.prank(address(loan));
        loanManager.claim({
            principal_:          -1,
            interest_:           0,
            delegateServiceFee_: 0,
            platformServiceFee_: 0,
            nextPaymentDueDate_: 0
        });
    }

    function test_claim_invalidState2() public {
        loanManager.__setPaymentFor(address(loan), 0, 0, block.timestamp, 0);
        // Requesting more principal but stating that there is no principal remaining (since `loan.principal() == 0`).
        vm.expectRevert("LM:C:INVALID");
        vm.prank(address(loan));
        loanManager.claim({
            principal_:          -1,
            interest_:           0,
            delegateServiceFee_: 0,
            platformServiceFee_: 0,
            nextPaymentDueDate_: 1
        });
    }

    function test_claim_invalidState3() public {
        loanManager.__setPaymentFor(address(loan), 0, 0, block.timestamp, 0);
        // Regardless of claim principal, next payment due date provided with no principal remaining (since `loan.principal() == 0`).
        vm.expectRevert("LM:C:INVALID");
        vm.prank(address(loan));
        loanManager.claim({
            principal_:          0,
            interest_:           0,
            delegateServiceFee_: 0,
            platformServiceFee_: 0,
            nextPaymentDueDate_: 1
        });
    }

    function test_claim_invalidState4() public {
        loanManager.__setPaymentFor(address(loan), 0, 0, block.timestamp, 0);
        // Regardless of claim principal, no next payment due date provided despite principal remaining.
        loan.__setPrincipal(1);

        vm.expectRevert("LM:C:INVALID");
        vm.prank(address(loan));
        loanManager.claim({
            principal_:          0,
            interest_:           0,
            delegateServiceFee_: 0,
            platformServiceFee_: 0,
            nextPaymentDueDate_: 0
        });
    }

}

contract ClaimTests is ClaimTestBase {

    address treasury = makeAddr("treasury");

    uint256 constant delegateManagementFeeRate = 0.04e6;
    uint256 constant delegateServiceFee        = 50e6;
    uint256 constant interest1                 = 100e6;
    uint256 constant interest2                 = 200e6;
    uint256 constant paymentInterval           = 1_000_000;
    uint256 constant platformManagementFeeRate = 0.06e6;
    uint256 constant platformServiceFee        = 100e6;
    uint256 constant principal                 = 2_000_000e6;

    uint256 constant netInterest1 = interest1 - (interest1 * (platformManagementFeeRate + delegateManagementFeeRate)) / 1e6;
    uint256 constant netInterest2 = interest2 - (interest2 * (platformManagementFeeRate + delegateManagementFeeRate)) / 1e6;

    uint256 constant issuanceRate1 = netInterest1 * 1e27 / paymentInterval;
    uint256 constant issuanceRate2 = netInterest2 * 1e27 / paymentInterval;

    uint256 start = block.timestamp;

    function setUp() public override {
        super.setUp();

        globals.setMapleTreasury(treasury);

        // Set Management Fees
        globals.setPlatformManagementFeeRate(address(poolManager), platformManagementFeeRate);
        poolManager.setDelegateManagementFeeRate(delegateManagementFeeRate);

        loan.__setFundsLent(principal);
        loan.__setPrincipal(principal);
        loan.__setPaymentDueDate(start + paymentInterval);
        loan.__setInterest(start + paymentInterval, interest1);

        loanManager.__setPaymentFor({
            loan_:                      address(loan),
            platformManagementFeeRate_: platformManagementFeeRate,
            delegateManagementFeeRate_: delegateManagementFeeRate,
            startDate_:                 start,
            issuanceRate_:              issuanceRate1
        });

        loanManager.__setDomainStart(start);
        loanManager.__setIssuanceRate(issuanceRate1);
        loanManager.__setPrincipalOut(principal);

        vm.warp(start + paymentInterval);

        loan.__setPaymentDueDate(start + 2 * paymentInterval);
        loan.__setInterest(start + 2 * paymentInterval, interest2);
    }

    function test_claim_requestingPrincipalIncrease() external {
        // Simulate a refinance with a principal increase
        uint256 principalIncrease = 500_000e6;

        // Mint the partial payment + principal needed for increase
        asset.mint(address(loanManager), principalIncrease + interest1 + delegateServiceFee + platformServiceFee);

        loan.__setPrincipal(principal + principalIncrease);

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start,
            accountedInterest:     0,
            accruedInterest:       netInterest1,
            assetsUnderManagement: principal + netInterest1,
            principalOut:          principal,
            unrealizedLosses:      0,
            issuanceRate:          netInterest1 * 1e27 / paymentInterval
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start,
            issuanceRate: netInterest1 * 1e27 / paymentInterval
        });

        // Set PM to expect call
        poolManager.__expectCall();
        poolManager.requestFunds(address(loanManager), principalIncrease);

        vm.prank(address(loan));
        loanManager.claim({
            principal_:          -int256(principalIncrease),
            interest_:           interest1,
            delegateServiceFee_: delegateServiceFee,
            platformServiceFee_: platformServiceFee,
            nextPaymentDueDate_: uint40(start + 2 * paymentInterval)
        });

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start + paymentInterval,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: principal + principalIncrease,
            principalOut:          principal + principalIncrease,
            unrealizedLosses:      0,
            issuanceRate:          netInterest2 * 1e27 / paymentInterval
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start + paymentInterval,
            issuanceRate: netInterest2 * 1e27 / paymentInterval
        });

        assertEq(asset.allowance(address(loanManager), address(loan)), principalIncrease);

        assertEq(asset.balanceOf(address(loanManager)),  principalIncrease);
        assertEq(asset.balanceOf(address(poolDelegate)), delegateServiceFee + (interest1 * delegateManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(treasury)),     platformServiceFee + (interest1 * platformManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(pool)),         netInterest1);
    }

    function test_claim() external {
        // Simulate a payment in the loan
        asset.mint(address(loanManager), interest1 + platformServiceFee + delegateServiceFee);

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start,
            accountedInterest:     0,
            accruedInterest:       netInterest1,
            assetsUnderManagement: principal + netInterest1,
            principalOut:          principal,
            unrealizedLosses:      0,
            issuanceRate:          netInterest1 * 1e27 / paymentInterval
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start,
            issuanceRate: netInterest1 * 1e27 / paymentInterval
        });

        vm.prank(address(loan));
        loanManager.claim({
            principal_:          0,
            interest_:           interest1,
            delegateServiceFee_: delegateServiceFee,
            platformServiceFee_: platformServiceFee,
            nextPaymentDueDate_: uint40(start + 2 * paymentInterval)
        });

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start + paymentInterval,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: principal,
            principalOut:          principal,
            unrealizedLosses:      0,
            issuanceRate:          netInterest2 * 1e27 / paymentInterval
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start + paymentInterval,
            issuanceRate: netInterest2 * 1e27 / paymentInterval
        });

        assertEq(asset.allowance(address(loanManager), address(loan)), 0);

        assertEq(asset.balanceOf(address(loanManager)),  0);
        assertEq(asset.balanceOf(address(poolDelegate)), delegateServiceFee + (interest1 * delegateManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(treasury)),     platformServiceFee + (interest1 * platformManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(pool)),         netInterest1);
    }

    function test_claim_returningPrincipal() external {
        vm.warp(start + paymentInterval);

        uint256 returnedPrincipal = 500_000e6;

        // Simulate a partial payment in the loan
        asset.mint(address(loanManager), returnedPrincipal + interest1 + platformServiceFee + delegateServiceFee);

        loan.__setPrincipal(principal - returnedPrincipal);

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start,
            accountedInterest:     0,
            accruedInterest:       netInterest1,
            assetsUnderManagement: principal + netInterest1,
            principalOut:          principal,
            unrealizedLosses:      0,
            issuanceRate:          netInterest1 * 1e27 / paymentInterval
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start,
            issuanceRate: netInterest1 * 1e27 / paymentInterval
        });

        vm.prank(address(loan));
        loanManager.claim({
            principal_:          int256(returnedPrincipal),
            interest_:           interest1,
            delegateServiceFee_: delegateServiceFee,
            platformServiceFee_: platformServiceFee,
            nextPaymentDueDate_: uint40(start + 2 * paymentInterval)
        });

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start + paymentInterval,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: principal - returnedPrincipal,
            principalOut:          principal - returnedPrincipal,
            unrealizedLosses:      0,
            issuanceRate:          netInterest2 * 1e27 / paymentInterval
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start + paymentInterval,
            issuanceRate: netInterest2 * 1e27 / paymentInterval
        });

        assertEq(asset.allowance(address(loanManager), address(loan)), 0);

        assertEq(asset.balanceOf(address(loanManager)),  0);
        assertEq(asset.balanceOf(address(poolDelegate)), delegateServiceFee + (interest1 * delegateManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(treasury)),     platformServiceFee + (interest1 * platformManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(pool)),         returnedPrincipal + netInterest1);
    }

    function test_claim_impaired() external {
        uint256 impairedDate = start + paymentInterval / 2;

        loanManager.__setAccountedInterest(netInterest1 / 2);
        loanManager.__setDomainStart(impairedDate);
        loanManager.__setImpairmentFor(address(loan), impairedDate, false);
        loanManager.__setIssuanceRate(0);
        loanManager.__setUnrealizedLosses(principal + netInterest1 / 2);

        // Simulate a payment in the loan
        asset.mint(address(loanManager), interest1 + platformServiceFee + delegateServiceFee);

        vm.prank(address(loan));
        loanManager.claim({
            principal_:          0,
            interest_:           interest1,
            delegateServiceFee_: delegateServiceFee,
            platformServiceFee_: platformServiceFee,
            nextPaymentDueDate_: uint40(start + 2 * paymentInterval)
        });

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start + paymentInterval,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: principal,
            principalOut:          principal,
            unrealizedLosses:      0,
            issuanceRate:          netInterest2 * 1e27 / paymentInterval
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start + paymentInterval,
            issuanceRate: netInterest2 * 1e27 / paymentInterval
        });

        assertImpairment({
            loanManager:        address(loanManager),
            loan:               address(loan),
            impairedDate:       0,
            impairedByGovernor: false
        });

        assertEq(asset.allowance(address(loanManager), address(loan)), 0);

        assertEq(asset.balanceOf(address(loanManager)),  0);
        assertEq(asset.balanceOf(address(poolDelegate)), delegateServiceFee + (interest1 * delegateManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(treasury)),     platformServiceFee + (interest1 * platformManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(pool)),         netInterest1);
    }

    function test_claim_closingLoan() external {
        vm.warp(start + paymentInterval);

        // Simulate a closing payment in the loan
        asset.mint(address(loanManager), principal + interest1 + platformServiceFee + delegateServiceFee);

        loan.__setPrincipal(0);

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start,
            accountedInterest:     0,
            accruedInterest:       netInterest1,
            assetsUnderManagement: principal + netInterest1,
            principalOut:          principal,
            unrealizedLosses:      0,
            issuanceRate:          netInterest1 * 1e27 / paymentInterval
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start,
            issuanceRate: netInterest1 * 1e27 / paymentInterval
        });

        vm.prank(address(loan));
        loanManager.claim({
            principal_:          int256(principal),
            interest_:           interest1,
            delegateServiceFee_: delegateServiceFee,
            platformServiceFee_: platformServiceFee,
            nextPaymentDueDate_: 0
        });

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start + paymentInterval,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: 0,
            principalOut:          0,
            unrealizedLosses:      0,
            issuanceRate:          0
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    0,
            issuanceRate: 0
        });

        assertEq(asset.allowance(address(loanManager), address(loan)), 0);

        assertEq(asset.balanceOf(address(loanManager)),  0);
        assertEq(asset.balanceOf(address(poolDelegate)), delegateServiceFee + (interest1 * delegateManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(treasury)),     platformServiceFee + (interest1 * platformManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(pool)),         principal + netInterest1);
    }

    function test_claim_returnMorePrincipal() external {
        vm.warp(start + paymentInterval);

        uint256 returnedPrincipal = principal + 500_000e6;

        // Simulate a partial payment in the loan
        asset.mint(address(loanManager), returnedPrincipal + interest1 + platformServiceFee + delegateServiceFee);

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start,
            accountedInterest:     0,
            accruedInterest:       netInterest1,
            assetsUnderManagement: principal + netInterest1,
            principalOut:          principal,
            unrealizedLosses:      0,
            issuanceRate:          netInterest1 * 1e27 / paymentInterval
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start,
            issuanceRate: netInterest1 * 1e27 / paymentInterval
        });

        vm.prank(address(loan));
        loanManager.claim({
            principal_:          int256(returnedPrincipal),
            interest_:           interest1,
            delegateServiceFee_: delegateServiceFee,
            platformServiceFee_: platformServiceFee,
            nextPaymentDueDate_: uint40(start + 2 * paymentInterval)
        });

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start + paymentInterval,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: 0,
            principalOut:          0,
            unrealizedLosses:      0,
            issuanceRate:          netInterest2 * 1e27 / paymentInterval
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start + paymentInterval,
            issuanceRate: netInterest2 * 1e27 / paymentInterval
        });

        assertEq(asset.allowance(address(loanManager), address(loan)), 0);

        assertEq(asset.balanceOf(address(loanManager)),  0);
        assertEq(asset.balanceOf(address(poolDelegate)), delegateServiceFee + (interest1 * delegateManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(treasury)),     platformServiceFee + (interest1 * platformManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(pool)),         returnedPrincipal + netInterest1);
    }

    function test_claim_impaired_returningPrincipal() external {
        uint256 impairedDate = start + paymentInterval / 2;

        loanManager.__setAccountedInterest(netInterest1 / 2);
        loanManager.__setDomainStart(impairedDate);
        loanManager.__setImpairmentFor(address(loan), impairedDate, false);
        loanManager.__setIssuanceRate(0);
        loanManager.__setUnrealizedLosses(principal + netInterest1 / 2);

        uint256 returnedPrincipal = 500_000e6;

        // Simulate a partial payment in the loan
        asset.mint(address(loanManager), returnedPrincipal + interest1 + platformServiceFee + delegateServiceFee);

        loan.__setPrincipal(principal - returnedPrincipal);
        loan.__setBorrower(borrower);

        vm.prank(address(loan));
        loanManager.claim({
            principal_:          int256(returnedPrincipal),
            interest_:           interest1,
            delegateServiceFee_: delegateServiceFee,
            platformServiceFee_: platformServiceFee,
            nextPaymentDueDate_: uint40(start + 2 * paymentInterval)
        });

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start + paymentInterval,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: principal - returnedPrincipal,
            principalOut:          principal - returnedPrincipal,
            unrealizedLosses:      0,
            issuanceRate:          netInterest2 * 1e27 / paymentInterval
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start + paymentInterval,
            issuanceRate: netInterest2 * 1e27 / paymentInterval
        });

        assertImpairment({
            loanManager:        address(loanManager),
            loan:               address(loan),
            impairedDate:       0,
            impairedByGovernor: false
        });

        assertEq(asset.allowance(address(loanManager), address(loan)), 0);

        assertEq(asset.balanceOf(address(loanManager)),  0);
        assertEq(asset.balanceOf(address(poolDelegate)), delegateServiceFee + (interest1 * delegateManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(treasury)),     platformServiceFee + (interest1 * platformManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(pool)),         returnedPrincipal + netInterest1);
    }

    function test_claim_impaired_requestingPrincipal() external {
        uint256 impairedDate = start + paymentInterval / 2;

        loanManager.__setAccountedInterest(netInterest1 / 2);
        loanManager.__setDomainStart(impairedDate);
        loanManager.__setImpairmentFor(address(loan), impairedDate, false);
        loanManager.__setIssuanceRate(0);
        loanManager.__setUnrealizedLosses(principal + netInterest1 / 2);

        uint256 requestedPrincipal = 500_000e6;

        // Simulate a partial payment in the loan
        asset.mint(address(loanManager), requestedPrincipal + interest1 + platformServiceFee + delegateServiceFee);

        loan.__setPrincipal(principal + requestedPrincipal);

        vm.prank(address(loan));
        loanManager.claim({
            principal_:          int256(requestedPrincipal) * -1,
            interest_:           interest1,
            delegateServiceFee_: delegateServiceFee,
            platformServiceFee_: platformServiceFee,
            nextPaymentDueDate_: uint40(start + 2 * paymentInterval)
        });

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           start + paymentInterval,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: principal + requestedPrincipal,
            principalOut:          principal + requestedPrincipal,
            unrealizedLosses:      0,
            issuanceRate:          netInterest2 * 1e27 / paymentInterval
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan),
            startDate:    start + paymentInterval,
            issuanceRate: netInterest2 * 1e27 / paymentInterval
        });

        assertImpairment({
            loanManager:        address(loanManager),
            loan:               address(loan),
            impairedDate:       0,
            impairedByGovernor: false
        });

        assertEq(asset.allowance(address(loanManager), address(loan)), requestedPrincipal);

        assertEq(asset.balanceOf(address(loanManager)),  requestedPrincipal);
        assertEq(asset.balanceOf(address(poolDelegate)), delegateServiceFee + (interest1 * delegateManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(treasury)),     platformServiceFee + (interest1 * platformManagementFeeRate) / 1e6);
        assertEq(asset.balanceOf(address(pool)),         netInterest1);
    }

}
