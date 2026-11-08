// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { MockERC20 } from "../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { LoanManagerHarness } from "./utils/Harnesses.sol";

import {
    MockFactory,
    MockGlobals,
    MockLoan,
    MockLoanFactory,
    MockPoolManager,
    MockReenteringLoan,
    MockRevertingERC20
} from "./utils/Mocks.sol";

import { TestBase } from "./utils/TestBase.sol";

contract FundTestBase is TestBase {

    address poolDelegate = makeAddr("poolDelegate");

    LoanManagerHarness loanManager = new LoanManagerHarness();
    MockERC20          asset       = new MockERC20("Asset", "A", 6);
    MockFactory        factory     = new MockFactory();
    MockGlobals        globals     = new MockGlobals();
    MockLoanFactory    loanFactory = new MockLoanFactory();
    MockPoolManager    poolManager = new MockPoolManager();

    function setUp() public virtual {
        factory.__setMapleGlobals(address(globals));

        poolManager.__setAsset(address(asset));
        poolManager.__setPoolDelegate(address(poolDelegate));

        loanManager.__setFactory(address(factory));
        loanManager.__setLocked(1);
        loanManager.__setPoolManager(address(poolManager));
    }

}

contract FundFailureTests is FundTestBase {

    MockLoan loan = new MockLoan();

    function setUp() public override {
        super.setUp();

        loan.__setFactory(address(loanFactory));
    }

    function test_fund_paused() public {
        globals.__setFunctionPaused(true);

        vm.expectRevert("LM:PAUSED");
        loanManager.fund(address(0));
    }

    function test_fund_notPoolDelegate() public {
        vm.expectRevert("LM:NOT_PD");
        loanManager.fund(address(0));
    }

    function test_fund_invalidFactory() public {
        vm.prank(poolDelegate);
        vm.expectRevert("LM:F:INVALID_LOAN_FACTORY");
        loanManager.fund(address(loan));
    }

    function test_fund_invalidLoan() public {
        globals.__setInstanceOf("OT_LOAN_FACTORY", address(loanFactory), true);

        vm.prank(poolDelegate);
        vm.expectRevert("LM:F:INVALID_LOAN_INSTANCE");
        loanManager.fund(address(loan));
    }

    function test_fund_invalidBorrower() public {
        globals.__setInstanceOf("OT_LOAN_FACTORY", address(loanFactory), true);

        loanFactory.__setIsLoan(address(loan), true);

        vm.prank(poolDelegate);
        vm.expectRevert("LM:F:INVALID_BORROWER");
        loanManager.fund(address(loan));
    }

    function test_fund_inactiveLoan() public {
        globals.__setIsBorrower(true);
        globals.__setInstanceOf("OT_LOAN_FACTORY", address(loanFactory), true);

        loan.__setPrincipal(0);

        loanFactory.__setIsLoan(address(loan), true);

        vm.prank(poolDelegate);
        vm.expectRevert("LM:F:LOAN_NOT_ACTIVE");
        loanManager.fund(address(loan));
    }

    function test_fund_failedApproval() public {
        globals.__setIsBorrower(true);
        globals.__setInstanceOf("OT_LOAN_FACTORY", address(loanFactory), true);

        loan.__setPrincipal(1);

        loanFactory.__setIsLoan(address(loan), true);
        loanManager.__setFundsAsset(address(new MockRevertingERC20()));

        vm.expectRevert("LM:PFFL:APPROVE_FAILED");
        vm.prank(poolDelegate);
        loanManager.fund(address(loan));
    }

    function test_fund_reentrancy() public {
        MockReenteringLoan loan_ = new MockReenteringLoan();

        globals.__setIsBorrower(true);
        globals.__setInstanceOf("OT_LOAN_FACTORY", address(loanFactory), true);

        loan_.__setFactory(address(loanFactory));
        loan_.__setPrincipal(1);

        loanFactory.__setIsLoan(address(loan_), true);
        loanManager.__setFundsAsset(address(asset));

        vm.expectRevert("LM:LOCKED");
        vm.prank(poolDelegate);
        loanManager.fund(address(loan_));
    }

    function test_fund_fundingMismatch() public {
        globals.__setIsBorrower(true);
        globals.__setInstanceOf("OT_LOAN_FACTORY", address(loanFactory), true);

        loan.__setPrincipal(1);
        loan.__setFundsLent(2);

        loanFactory.__setIsLoan(address(loan), true);
        loanManager.__setFundsAsset(address(asset));

        vm.expectRevert("LM:F:FUNDING_MISMATCH");
        vm.prank(poolDelegate);
        loanManager.fund(address(loan));
    }

}

contract FundSuccessTests is FundTestBase {

    uint256 expectedAccountedInterest;
    uint256 expectedIssuanceRate;
    uint256 expectedPrincipalOut;

    function setUp() public override {
        super.setUp();

        globals.__setIsBorrower(true);
        globals.__setInstanceOf("OT_LOAN_FACTORY", address(loanFactory), true);

        loanManager.__setFundsAsset(address(asset));

        // Assert pre-state
        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           0,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: 0,
            principalOut:          0,
            unrealizedLosses:      0,
            issuanceRate:          0
        });
    }

    function testFuzz_fund_multipleLoans(uint256 seed) external {
        // Set both fees to sum up to 10%
        globals.setPlatformManagementFeeRate(address(poolManager), 0.06e6);
        poolManager.setDelegateManagementFeeRate(0.04e6);

        for (uint256 i = 1; i < seed % 50; ++i) {
            // Bound each loan parameter
            uint256 fundDate         = bound(randomize(seed, i, "fundDate"),  block.timestamp + 1 days, block.timestamp + 100 days);
            uint256 grossInterest_   = bound(randomize(seed, i, "interest"),  1e6,                      1e9 * 1e18);
            uint256 paymentInterval_ = bound(randomize(seed, i, "interval"),  1 days,                   365 days);
            uint256 principal_       = bound(randomize(seed, i, "principal"), 1e6,                      1e12 * 1e18);

            // Calculate net interest
            uint256 interest_ = grossInterest_ - (grossInterest_ * 0.1e6 / 1e6);

            expectedAccountedInterest += expectedIssuanceRate * (fundDate - block.timestamp) / 1e27;
            expectedIssuanceRate      += interest_ * 1e27 / paymentInterval_;
            expectedPrincipalOut      += principal_;

            vm.warp(fundDate);

            MockLoan loan_ = new MockLoan();

            loan_.__setFactory(address(loanFactory));
            loan_.__setFundsLent(principal_);
            loan_.__setPrincipal(principal_);
            loan_.__setPaymentDueDate(block.timestamp + paymentInterval_);
            loan_.__setInterest(block.timestamp + paymentInterval_, grossInterest_);

            loanFactory.__setIsLoan(address(loan_), true);

            asset.mint(address(loan_), principal_);

            loan_.__expectCall();
            loan_.fund();

            vm.prank(poolDelegate);
            loanManager.fund(address(loan_));

            assertGlobalState({
                loanManager:           address(loanManager),
                domainStart:           block.timestamp,
                accountedInterest:     expectedAccountedInterest,
                accruedInterest:       0,
                assetsUnderManagement: expectedPrincipalOut + expectedAccountedInterest,
                principalOut:          expectedPrincipalOut,
                unrealizedLosses:      0,
                issuanceRate:          expectedIssuanceRate
            });

            assertPaymentState({
                loanManager:  address(loanManager),
                loan:         address(loan_),
                startDate:    block.timestamp,
                issuanceRate: interest_ * 1e27 / paymentInterval_
            });

            assertEq(asset.allowance(address(loanManager), address(loan_)), principal_);
        }
    }

    function test_fund_paymentIssuanceRateLimit() external {
        uint256 interest_        = 3.2e10 * 1e18;  // 32 billion ether
        uint256 paymentInterval_ = 1 days;
        uint256 principal_       = 1e12 * 1e18;    // 1 trillion ether

        expectedIssuanceRate = interest_ * 1e27 / paymentInterval_;
        expectedPrincipalOut = principal_;

        MockLoan loan_ = new MockLoan();

        loan_.__setFactory(address(loanFactory));
        loan_.__setFundsLent(principal_);
        loan_.__setPrincipal(principal_);
        loan_.__setPaymentDueDate(block.timestamp + paymentInterval_);
        loan_.__setInterest(block.timestamp + paymentInterval_, interest_);

        loanFactory.__setIsLoan(address(loan_), true);

        asset.mint(address(loan_), principal_);

        loan_.__expectCall();
        loan_.fund();

        vm.prank(poolDelegate);
        loanManager.fund(address(loan_));

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           block.timestamp,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: expectedPrincipalOut,
            principalOut:          expectedPrincipalOut,
            unrealizedLosses:      0,
            issuanceRate:          expectedIssuanceRate
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan_),
            startDate:    block.timestamp,
            issuanceRate: interest_ * 1e27 / paymentInterval_
        });

        assertEq(asset.allowance(address(loanManager), address(loan_)), principal_);
    }

    function test_fund_principalLimit() external {
        uint256 interest_        = 1e6 * 1e18;         // 1 million ether
        uint256 paymentInterval_ = 1 days;
        uint256 principal_       = type(uint128).max;  // 3.4e38

        assertEq(principal_, 3.40282366920938463463374607431768211455e38);

        expectedIssuanceRate = interest_ * 1e27 / paymentInterval_;
        expectedPrincipalOut = principal_;

        MockLoan loan_ = new MockLoan();

        loan_.__setFactory(address(loanFactory));
        loan_.__setPaymentDueDate(block.timestamp + paymentInterval_);
        loan_.__setInterest(block.timestamp + paymentInterval_, interest_);

        loanFactory.__setIsLoan(address(loan_), true);

        asset.mint(address(loan_), principal_);

        loan_.__setFundsLent(principal_ + 1);
        loan_.__setPrincipal(principal_ + 1);

        loan_.__expectCall();
        loan_.fund();

        vm.prank(poolDelegate);
        vm.expectRevert("LM:INT256_OOB_FOR_UINT128");
        loanManager.fund(address(loan_));

        loan_.__setFundsLent(principal_);
        loan_.__setPrincipal(principal_);

        vm.prank(poolDelegate);
        loanManager.fund(address(loan_));

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           block.timestamp,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: expectedPrincipalOut,
            principalOut:          expectedPrincipalOut,
            unrealizedLosses:      0,
            issuanceRate:          expectedIssuanceRate
        });
    }

    function test_fund_startDateAndDomainStartLimit() external {
        uint256 interest_        = 1_000 * 1e18;
        uint256 paymentInterval_ = 1 seconds;  // 1 second since max uint40 value is used for due date.
        uint256 principal_       = 1_000_0000 * 1e18;

        uint256 lastValidStartDate = type(uint40).max - 1 seconds;

        assertEq(lastValidStartDate / 365 days, 34_865);  // 1970 + 34,865 = year 36,835

        expectedIssuanceRate = interest_ * 1e27 / paymentInterval_;
        expectedPrincipalOut = principal_;

        MockLoan loan_ = new MockLoan();

        loan_.__setFactory(address(loanFactory));
        loan_.__setFundsLent(principal_);
        loan_.__setPrincipal(principal_);
        loan_.__setPaymentDueDate(type(uint40).max);       // Set to max uint40 value
        loan_.__setInterest(type(uint40).max, interest_);  // Set to max uint40 value

        loanFactory.__setIsLoan(address(loan_), true);

        asset.mint(address(loan_), principal_);

        loan_.fund();

        vm.warp(lastValidStartDate + 1);  // Warp to 1 day before the max uint40 value to avoid division by 0 errors

        vm.expectRevert();
        vm.prank(poolDelegate);
        loanManager.fund(address(loan_));

        vm.warp(lastValidStartDate);

        vm.prank(poolDelegate);
        loanManager.fund(address(loan_));

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           lastValidStartDate,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: expectedPrincipalOut,
            principalOut:          expectedPrincipalOut,
            unrealizedLosses:      0,
            issuanceRate:          expectedIssuanceRate
        });

        assertPaymentState({
            loanManager:  address(loanManager),
            loan:         address(loan_),
            startDate:    lastValidStartDate,
            issuanceRate: interest_ * 1e27 / paymentInterval_
        });
    }

    function test_fund_managementFeeRateLimits() external {
        uint256 interest_        = 3.2e10 * 1e18;  // 32 billion ether
        uint256 paymentInterval_ = 1 days;
        uint256 principal_       = 1e12 * 1e18;    // 1 trillion ether

        expectedIssuanceRate = 0; // No issuance rate because of the management fee
        expectedPrincipalOut = principal_;

        globals.setPlatformManagementFeeRate(address(poolManager), 1e6);  // Even though is type uint24 can't be greater than 1e6 i.e. 100%

        poolManager.setDelegateManagementFeeRate(type(uint24).max);

        MockLoan loan_ = new MockLoan();

        loan_.__setFactory(address(loanFactory));
        loan_.__setFundsLent(principal_);
        loan_.__setPrincipal(principal_);
        loan_.__setPaymentDueDate(block.timestamp + paymentInterval_);       // Set to max uint40 value
        loan_.__setInterest(block.timestamp + paymentInterval_, interest_);

        loanFactory.__setIsLoan(address(loan_), true);

        asset.mint(address(loan_), principal_);

        loan_.fund();

        vm.prank(poolDelegate);
        loanManager.fund(address(loan_));

        assertGlobalState({
            loanManager:           address(loanManager),
            domainStart:           block.timestamp,
            accountedInterest:     0,
            accruedInterest:       0,
            assetsUnderManagement: expectedPrincipalOut,
            principalOut:          expectedPrincipalOut,
            unrealizedLosses:      0,
            issuanceRate:          expectedIssuanceRate
        });

        assertPaymentState({
            loanManager:               address(loanManager),
            loan:                      address(loan_),
            startDate:                 block.timestamp,
            issuanceRate:              expectedIssuanceRate,
            platformManagementFeeRate: 1e6,
            delegateManagementFeeRate: 0  // Value gets clamped to 0 as the sum of managementFeeRates can't be greater than 1e6
        });
    }

    function randomize(uint256 seed, uint256 salt1, string memory salt2) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(seed, salt1, salt2)));
    }

}
