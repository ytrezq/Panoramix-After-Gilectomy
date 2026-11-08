// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { MockERC20 } from "../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { LoanManagerHarness } from "./utils/Harnesses.sol";
import { TestBase }           from "./utils/TestBase.sol";

import { MockGlobals, MockLoan, MockLoanFactory, MockPoolManager, MockFactory } from "./utils/Mocks.sol";

contract DistributeLiquidationFundsBase is TestBase {

    address borrower     = makeAddr("borrower");
    address pool         = makeAddr("pool");
    address poolDelegate = makeAddr("poolDelegate");
    address treasury     = makeAddr("treasury");

    LoanManagerHarness loanManager = new LoanManagerHarness();
    MockERC20          asset       = new MockERC20("A", "A", 18);
    MockFactory        factory     = new MockFactory();
    MockGlobals        globals     = new MockGlobals();
    MockLoan           loan        = new MockLoan();
    MockLoanFactory    loanFactory = new MockLoanFactory();
    MockPoolManager    poolManager = new MockPoolManager();

    function setUp() public virtual {
        factory.__setMapleGlobals(address(globals));

        poolManager.__setAsset(address(asset));

        loanManager.__setFactory(address(factory));
        loanManager.__setFundsAsset(address(asset));
        loanManager.__setPoolManager(address(poolManager));
    }

}

contract DistributeLiquidationFundsFailureTests is DistributeLiquidationFundsBase {

    function test_distributeLiquidationFunds_zeroBorrower() public {
        vm.expectRevert("LM:DLF:TRANSFER_B");
        loanManager.__distributeLiquidationFunds(address(loan), 0, 0, 0, 0);
    }

    function test_distributeLiquidationFunds_transferBorrower() public {
        loan.__setBorrower(borrower);

        vm.expectRevert("LM:DLF:TRANSFER_B");
        loanManager.__distributeLiquidationFunds(address(loan), 0, 0, 0, 1);
    }

    function test_distributeLiquidationFunds_zeroPool() public {
        loan.__setBorrower(borrower);

        vm.expectRevert("LM:DLF:TRANSFER_P");
        loanManager.__distributeLiquidationFunds(address(loan), 0, 0, 0, 0);
    }

    function test_distributeLiquidationFunds_transferPool() public {
        loan.__setBorrower(borrower);
        poolManager.__setPool(pool);

        vm.expectRevert("LM:DLF:TRANSFER_P");
        loanManager.__distributeLiquidationFunds(address(loan), 1, 0, 0, 1);
    }

    function test_distributeLiquidationFunds_zeroTreasury() public {
        loan.__setBorrower(borrower);
        poolManager.__setPool(pool);

        vm.expectRevert("LM:DLF:TRANSFER_MT");
        loanManager.__distributeLiquidationFunds(address(loan), 1, 0, 0, 0);
    }

    function test_distributeLiquidationFunds_transferTreasury() public {
        loan.__setBorrower(borrower);
        poolManager.__setPool(pool);
        globals.setMapleTreasury(treasury);

        vm.expectRevert("LM:DLF:TRANSFER_MT");
        loanManager.__distributeLiquidationFunds(address(loan), 0, 0, 1, 1);
    }

}

contract DistributeLiquidationFundsTests is DistributeLiquidationFundsBase {

    uint256 constant platformManagementFeeRate = 0.06e6;
    uint256 constant delegateManagementFeeRate = 0.04e6;

    uint256 start = block.timestamp;

    function setUp() public override {
        super.setUp();

        globals.setMapleTreasury(treasury);

        loan.__setBorrower(borrower);

        poolManager.__setPool(pool);
        poolManager.__setPoolDelegate(poolDelegate);

        loanManager.__setPaymentFor({
            loan_:                      address(loan),
            platformManagementFeeRate_: platformManagementFeeRate,
            delegateManagementFeeRate_: delegateManagementFeeRate,
            startDate_:                 0,                          // Not needed by `_distributeLiquidationFunds`.
            issuanceRate_:              0                           // Not needed by `_distributeLiquidationFunds`.
        });
    }

    function testFuzz_distributeLiquidationFunds(
        uint256 principal,
        uint256 interest,
        uint256 platformServiceFee,
        uint256 recoveredFunds
    )
        external
    {
        principal          = bound(principal,          0, 1e30);
        interest           = bound(interest,           0, 1e30);
        platformServiceFee = bound(platformServiceFee, 0, 1e30);
        recoveredFunds     = bound(recoveredFunds,     0, 1e30);

        asset.mint(address(loanManager), recoveredFunds);

        ( uint256 returnedRemainingLosses , uint256 returnedUnrecoveredPlatformFees ) =
            loanManager.__distributeLiquidationFunds(address(loan), principal, interest, platformServiceFee, recoveredFunds);

        uint256 delegateManagementFee = interest * delegateManagementFeeRate / 1e6;
        uint256 platformManagementFee = interest * platformManagementFeeRate / 1e6;
        uint256 netInterest           = interest - (delegateManagementFee + platformManagementFee);
        uint256 platformFee           = platformServiceFee + platformManagementFee;

        uint256 toTreasury = _min(recoveredFunds,              platformFee);
        uint256 toPool     = _min(recoveredFunds - toTreasury, principal + netInterest);

        assertEq(returnedRemainingLosses,         principal + netInterest - toPool);
        assertEq(returnedUnrecoveredPlatformFees, platformFee - toTreasury);

        assertEq(
            toTreasury + toPool + returnedRemainingLosses + returnedUnrecoveredPlatformFees,
            principal + netInterest + platformFee
        );

        assertEq(asset.balanceOf(borrower), recoveredFunds - toTreasury - toPool);
        assertEq(asset.balanceOf(pool),     toPool);
        assertEq(asset.balanceOf(treasury), toTreasury);

        assertEq(asset.balanceOf(poolDelegate),         0);
        assertEq(asset.balanceOf(address(loanManager)), 0);
    }

    function _min(uint256 a_, uint256 b_) internal pure returns (uint256 minimum_) {
        minimum_ = a_ < b_ ? a_ : b_;
    }

}
