// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test }  from "../modules/forge-std/src/Test.sol";

import { MapleLoanInitializerHarness }          from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals, MockLender } from "./utils/Mocks.sol";

// TODO: Consider just attaching the initializer to the harness via an `__initialize` on the harness.

contract InitializerTests is Test {

    event Initialized(
        address indexed borrower_,
        address indexed lender_,
        address indexed fundsAsset_,
        uint256 principalRequested_,
        uint32[3] termDetails_,
        uint64[4] rates_
    );

    uint32 constant validGracePeriod     = 1;  // Technically, 0 is valid too, but makes it easier to maintain this test.
    uint32 constant validNoticePeriod    = 1;
    uint32 constant validPaymentInterval = 1;

    uint64 constant validDelegateServiceFeeRate  = 1;  // Technically, 0 is valid too, but makes it easier to maintain this test.
    uint64 constant validInterestRate            = 1;  // Technically, 0 is valid too, but makes it easier to maintain this test.
    uint64 constant validLateFeeRate             = 1;  // Technically, 0 is valid too, but makes it easier to maintain this test.
    uint64 constant validLateInterestPremiumRate = 1;  // Technically, 0 is valid too, but makes it easier to maintain this test.

    uint256 constant validPrincipalRequested = 1;

    address validBorrower;
    address validFundsAsset;
    address validLender;

    MapleLoanInitializerHarness initializer;
    MockGlobals                 globals;
    MockLender                  lender;
    MockFactory                 factory;
    MockFactory                 lenderFactory;

    function setUp() external {
        lender = new MockLender();

        factory         = new MockFactory();
        globals         = new MockGlobals();
        initializer     = new MapleLoanInitializerHarness();
        lenderFactory   = new MockFactory();
        validBorrower   = makeAddr("borrower");
        validFundsAsset = makeAddr("fundsAsset");
        validLender     = address(lender);

        factory.__setGlobals(address(globals));

        globals.__setIsBorrower(validBorrower, true);
        globals.__setIsInstanceOf("OT_LOAN_MANAGER_FACTORY", address(lenderFactory), true);

        globals.__setIsPoolAsset(validFundsAsset, true);

        lender.__setFactory(address(lenderFactory));
        lender.__setFundsAsset(validFundsAsset);

        lenderFactory.__setGlobals(address(globals));
        lenderFactory.__setIsInstance(validLender, true);
    }

    function test_initialize_invalidPrincipal() external {
        vm.expectRevert("MLI:I:INVALID_PRINCIPAL");
        initializer.__initialize(
            validBorrower,
            validLender,
            validFundsAsset,
            0,
            [validGracePeriod, validNoticePeriod, validPaymentInterval],
            [validDelegateServiceFeeRate, validInterestRate, validLateFeeRate, validLateInterestPremiumRate]
        );
    }

    function test_initialize_invalidNoticePeriod() external {
        vm.expectRevert("MLI:I:INVALID_NOTICE_PERIOD");
        initializer.__initialize(
            validBorrower,
            validLender,
            validFundsAsset,
            validPrincipalRequested,
            [validGracePeriod, 0, validPaymentInterval],
            [validDelegateServiceFeeRate, validInterestRate, validLateFeeRate, validLateInterestPremiumRate]
        );
    }

    function test_initialize_invalidPaymentInterval() external {
        vm.expectRevert("MLI:I:INVALID_PAYMENT_INTERVAL");
        initializer.__initialize(
            validBorrower,
            validLender,
            validFundsAsset,
            validPrincipalRequested,
            [validGracePeriod, validNoticePeriod, 0],
            [validDelegateServiceFeeRate, validInterestRate, validLateFeeRate, validLateInterestPremiumRate]
        );
    }

    function test_initialize_zeroBorrower() external {
        vm.expectRevert("MLI:I:ZERO_BORROWER");
        vm.prank(address(factory));
        initializer.__initialize(
            address(0),
            validLender,
            validFundsAsset,
            validPrincipalRequested,
            [validGracePeriod, validNoticePeriod, validPaymentInterval],
            [validDelegateServiceFeeRate, validInterestRate, validLateFeeRate, validLateInterestPremiumRate]
        );
    }

    function test_initialize_invalidBorrower() external {
        vm.expectRevert("MLI:I:INVALID_BORROWER");
        vm.prank(address(factory));
        initializer.__initialize(
            makeAddr("invalidBorrower"),
            validLender,
            validFundsAsset,
            validPrincipalRequested,
            [validGracePeriod, validNoticePeriod, validPaymentInterval],
            [validDelegateServiceFeeRate, validInterestRate, validLateFeeRate, validLateInterestPremiumRate]
        );
    }

    function test_initialize_invalidFundsAsset() external {
        vm.expectRevert("MLI:I:INVALID_FUNDS_ASSET");
        vm.prank(address(factory));
        initializer.__initialize(
            validBorrower,
            validLender,
            makeAddr("invalidFundsAsset"),
            validPrincipalRequested,
            [validGracePeriod, validNoticePeriod, validPaymentInterval],
            [validDelegateServiceFeeRate, validInterestRate, validLateFeeRate, validLateInterestPremiumRate]
        );
    }

    function test_initialize_zeroLender() external {
        vm.expectRevert("MLI:I:ZERO_LENDER");
        vm.prank(address(factory));
        initializer.__initialize(
            validBorrower,
            address(0),
            validFundsAsset,
            validPrincipalRequested,
            [validGracePeriod, validNoticePeriod, validPaymentInterval],
            [validDelegateServiceFeeRate, validInterestRate, validLateFeeRate, validLateInterestPremiumRate]
        );
    }

    function test_initialize_differentFundsAsset() external {
        address otherAsset = makeAddr("otherAsset");

        globals.__setIsPoolAsset(otherAsset, true);

        vm.expectRevert("MLI:I:DIFFERENT_ASSET");
        vm.prank(address(factory));
        initializer.__initialize(
            validBorrower,
            validLender,
            otherAsset,
            validPrincipalRequested,
            [validGracePeriod, validNoticePeriod, validPaymentInterval],
            [validDelegateServiceFeeRate, validInterestRate, validLateFeeRate, validLateInterestPremiumRate]
        );
    }

    function test_initialize_invalidLenderFactory() external {
        MockLender invalidLender = new MockLender();
        invalidLender.__setFundsAsset(validFundsAsset);

        vm.expectRevert("MLI:I:INVALID_FACTORY");
        vm.prank(address(factory));
        initializer.__initialize(
            validBorrower,
            address(invalidLender),
            validFundsAsset,
            validPrincipalRequested,
            [validGracePeriod, validNoticePeriod, validPaymentInterval],
            [validDelegateServiceFeeRate, validInterestRate, validLateFeeRate, validLateInterestPremiumRate]
        );
    }

    function test_initialize_invalidLenderFactoryInstance() external {
        MockLender invalidLender = new MockLender();
        invalidLender.__setFactory(address(lenderFactory));
        invalidLender.__setFundsAsset(validFundsAsset);

        vm.expectRevert("MLI:I:INVALID_INSTANCE");
        vm.prank(address(factory));
        initializer.__initialize(
            validBorrower,
            address(invalidLender),
            validFundsAsset,
            validPrincipalRequested,
            [validGracePeriod, validNoticePeriod, validPaymentInterval],
            [validDelegateServiceFeeRate, validInterestRate, validLateFeeRate, validLateInterestPremiumRate]
        );
    }

    function test_initialize_success() external {
        address poolManager                 = makeAddr("poolManager");
        uint256 validPlatformServiceFeeRate = 1;

        lender.__setPoolManager(poolManager);
        globals.__setPlatformServiceFeeRate(poolManager, validPlatformServiceFeeRate);

        vm.expectEmit();
        emit Initialized(
            validBorrower,
            validLender,
            validFundsAsset,
            validPrincipalRequested,
            [validGracePeriod, validNoticePeriod, validPaymentInterval],
            [validDelegateServiceFeeRate, validInterestRate, validLateFeeRate, validLateInterestPremiumRate]
        );

        vm.prank(address(factory));
        initializer.__initialize(
            validBorrower,
            validLender,
            validFundsAsset,
            validPrincipalRequested,
            [validGracePeriod, validNoticePeriod, validPaymentInterval],
            [validDelegateServiceFeeRate, validInterestRate, validLateFeeRate, validLateInterestPremiumRate]
        );

        assertEq(initializer.borrower(),                validBorrower);
        assertEq(initializer.lender(),                  validLender);
        assertEq(initializer.fundsAsset(),              validFundsAsset);
        assertEq(initializer.principal(),               validPrincipalRequested);
        assertEq(initializer.gracePeriod(),             validGracePeriod);
        assertEq(initializer.noticePeriod(),            validNoticePeriod);
        assertEq(initializer.paymentInterval(),         validPaymentInterval);
        assertEq(initializer.delegateServiceFeeRate(),  validDelegateServiceFeeRate);
        assertEq(initializer.interestRate(),            validInterestRate);
        assertEq(initializer.lateFeeRate(),             validLateFeeRate);
        assertEq(initializer.lateInterestPremiumRate(), validLateInterestPremiumRate);
        assertEq(initializer.platformServiceFeeRate(),  validPlatformServiceFeeRate);
    }

}
