// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { MockERC20 } from "../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { LoanManagerHarness } from "./utils/Harnesses.sol";
import { TestBase }            from "./utils/TestBase.sol";

import { MockGlobals, MockLoan, MockLoanFactory, MockPoolManager, MockFactory } from "./utils/Mocks.sol";

contract DistributeClaimedFundsBase is TestBase {

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
        poolManager.__setHasSufficientCover(true);

        loanManager.__setFactory(address(factory));
        loanManager.__setFundsAsset(address(asset));
        loanManager.__setPoolManager(address(poolManager));
    }

}

contract DistributeClaimedFundsFailureTests is DistributeClaimedFundsBase {

    function test_distributeClaimFunds_zeroPool() public {
        vm.expectRevert("LM:DCF:TRANSFER_P");
        loanManager.__distributeClaimedFunds(address(loan), 0, 0, 0, 0);
    }

    function test_distributeClaimFunds_poolTransfer() public {
        poolManager.__setPool(pool);

        vm.expectRevert("LM:DCF:TRANSFER_P");
        loanManager.__distributeClaimedFunds(address(loan), 0, 1, 0, 0);
    }

    function test_distributeClaimFunds_zeroPoolDelegate() public {
        poolManager.__setPool(pool);

        vm.expectRevert("LM:DCF:TRANSFER_PD");
        loanManager.__distributeClaimedFunds(address(loan), 0, 0, 0, 0);
    }

    function test_distributeClaimFunds_zeroDelegate() public {
        poolManager.__setPool(pool);
        poolManager.__setPoolDelegate(poolDelegate);

        vm.expectRevert("LM:DCF:TRANSFER_PD");
        loanManager.__distributeClaimedFunds(address(loan), 0, 0, 1, 0);
    }

    function test_distributeClaimFunds_zeroTreasury() public {
        poolManager.__setPool(pool);
        poolManager.__setPoolDelegate(poolDelegate);

        vm.expectRevert("LM:DCF:TRANSFER_MT");
        loanManager.__distributeClaimedFunds(address(loan), 0, 0, 0, 0);
    }

    function test_distributeClaimFunds_platformTransfer() public {
        poolManager.__setPool(pool);
        poolManager.__setPoolDelegate(poolDelegate);
        globals.setMapleTreasury(treasury);

        vm.expectRevert("LM:DCF:TRANSFER_MT");
        loanManager.__distributeClaimedFunds(address(loan), 0, 0, 0, 1);
    }

}

contract DistributeClaimedFundsTests is DistributeClaimedFundsBase {

    uint256 constant platformManagementFeeRate = 0.06e6;
    uint256 constant delegateManagementFeeRate = 0.04e6;

    uint256 start = block.timestamp;

    function setUp() public override {
        super.setUp();

        globals.setMapleTreasury(treasury);

        poolManager.__setPool(pool);
        poolManager.__setPoolDelegate(poolDelegate);

        // Set Management Fees
        globals.setPlatformManagementFeeRate(address(poolManager), platformManagementFeeRate);
        poolManager.setDelegateManagementFeeRate(delegateManagementFeeRate);

        loanManager.__setPaymentFor({
            loan_:                      address(loan),
            platformManagementFeeRate_: platformManagementFeeRate,
            delegateManagementFeeRate_: delegateManagementFeeRate,
            startDate_:                 0,                          // Not needed by `_distributeClaimedFunds`.
            issuanceRate_:              0                           // Not needed by `_distributeClaimedFunds`.
        });
    }

    // TODO: Handle negative `principal`.
    // TODO: Handle no cover.
    function testFuzz_distributeClaimFunds(
        int256  principal,
        uint256 interest,
        uint256 delegateServiceFee,
        uint256 platformServiceFee,
        bool    isCovered
    )
        public
    {
        principal          = bound(principal,          -1e30, 1e30);
        interest           = bound(interest,           0,     1e30);
        delegateServiceFee = bound(delegateServiceFee, 0,     1e30);
        platformServiceFee = bound(platformServiceFee, 0,     1e30);

        uint256 clampedPrincipal = principal < 0 ? 0 : uint256(principal);

        asset.mint(address(loanManager), clampedPrincipal + interest + delegateServiceFee + platformServiceFee);

        poolManager.__setHasSufficientCover(isCovered);

        vm.prank(address(loanManager));
        loanManager.__distributeClaimedFunds(address(loan), int256(principal), interest, delegateServiceFee, platformServiceFee);

        uint256 platformManagementFee = interest * platformManagementFeeRate / 1e6;
        uint256 delegateManagementFee = interest * delegateManagementFeeRate / 1e6;

        uint256 toPool     = clampedPrincipal + interest - delegateManagementFee - platformManagementFee;
        uint256 toDelegate = delegateServiceFee + delegateManagementFee;
        uint256 toTreasury = platformServiceFee + platformManagementFee;

        assertEq(asset.balanceOf(address(loanManager)), 0);
        assertEq(asset.balanceOf(pool),                 isCovered ? toPool     : toPool + delegateManagementFee);
        assertEq(asset.balanceOf(poolDelegate),         isCovered ? toDelegate : 0);
        assertEq(asset.balanceOf(treasury),             isCovered ? toTreasury : toTreasury + delegateServiceFee);
    }

}
