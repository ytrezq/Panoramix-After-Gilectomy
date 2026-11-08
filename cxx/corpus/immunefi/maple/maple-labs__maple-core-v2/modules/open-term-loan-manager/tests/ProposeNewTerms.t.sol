// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { LoanManagerHarness } from "./utils/Harnesses.sol";
import { TestBase }           from "./utils/TestBase.sol";

import {
    MockFactory,
    MockGlobals,
    MockLoan,
    MockPoolManager
} from "./utils/Mocks.sol";

contract ProposeNewTermsTests is TestBase {

    address poolDelegate = makeAddr("poolDelegate");
    address refinancer   = makeAddr("refinancer");

    LoanManagerHarness loanManager = new LoanManagerHarness();

    MockFactory     factory     = new MockFactory();
    MockGlobals     globals     = new MockGlobals();
    MockLoan        loan        = new MockLoan();
    MockPoolManager poolManager = new MockPoolManager();

    function setUp() public {
        factory.__setMapleGlobals(address(globals));

        poolManager.__setPoolDelegate(poolDelegate);

        loanManager.__setLocked(1);
        loanManager.__setPoolManager(address(poolManager));
        loanManager.__setFactory(address(factory));
    }

    function test_proposeNewTerms_paused() public {
        globals.__setFunctionPaused(true);

        vm.expectRevert("LM:PAUSED");
        loanManager.proposeNewTerms(address(loan), refinancer, block.timestamp, new bytes[](1));
    }

    function test_proposeNewTerms_notPoolDelegate() public {
        vm.expectRevert("LM:NOT_PD");
        loanManager.proposeNewTerms(address(loan), refinancer, block.timestamp, new bytes[](1));
    }

    function test_proposeNewTerms_notLoan() public {
        vm.prank(poolDelegate);
        vm.expectRevert("LM:NOT_LOAN");
        loanManager.proposeNewTerms(address(0), refinancer, block.timestamp, new bytes[](1));
    }

    function test_proposeNewTerms_success() public {
        loanManager.__setPaymentFor(address(loan), 0, 0, block.timestamp, 0);
        
        loan.__expectCall();
        loan.proposeNewTerms(refinancer, block.timestamp, new bytes[](1));

        vm.prank(poolDelegate);
        loanManager.proposeNewTerms(address(loan), refinancer, block.timestamp, new bytes[](1));
    }

}
