// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Units.t.sol";

contract BridgeableToken_Constructor_Units_Test is Units_Test {
    function test_Constructor() external view {
        assertEq(aBridgeableTokenp.owner(), address(accessManager));
        assertEq(aBridgeableTokenp.getFeesRecipient(), users.feesRecipient.addr);
        assertEq(aBridgeableTokenp.getPrincipalToken(), address(aEURp));
        assertFalse(aBridgeableTokenp.getIsIsolateMode());
        assertEq(aBridgeableTokenp.getFeesRate(), DEFAULT_FEE_RATE);
        assertEq(aBridgeableTokenp.getDailyCreditLimit(), DEFAULT_DAILY_CREDIT_LIMIT);
        assertEq(aBridgeableTokenp.getGlobalCreditLimit(), DEFAULT_GLOBAL_CREDIT_LIMIT);
        assertEq(aBridgeableTokenp.getDailyDebitLimit(), DEFAULT_DAILY_DEBIT_LIMIT);
        assertEq(aBridgeableTokenp.getGlobalDebitLimit(), DEFAULT_GLOBAL_DEBIT_LIMIT);
        assertEq(aBridgeableTokenp.getMaxDebitableAmount(), DEFAULT_DAILY_DEBIT_LIMIT);
        assertEq(aBridgeableTokenp.getCreditDebitBalance(), 0);
    }

    function test_revertWhen_PrincipalTokenIsAddressZero() external {
        vm.expectRevert(abi.encodeWithSelector(CommonErrorsLib.AddressZero.selector));
        new BridgeableTokenP(
            "aLz-EURp",
            "aLzEURp",
            address(0),
            address(endpoints[aEid]),
            address(accessManager),
            configParams
        );
    }

    function test_revertWhen_FeesRecipientIsAddressZero() external {
        BridgeableTokenP.ConfigParams memory wrongConfigParams = BridgeableTokenP.ConfigParams({
            dailyCreditLimit: DEFAULT_DAILY_CREDIT_LIMIT,
            globalCreditLimit: DEFAULT_GLOBAL_CREDIT_LIMIT,
            dailyDebitLimit: DEFAULT_DAILY_DEBIT_LIMIT,
            globalDebitLimit: DEFAULT_GLOBAL_DEBIT_LIMIT,
            feesRecipient: address(0),
            feesRate: DEFAULT_FEE_RATE,
            isIsolateMode: false
        });
        vm.expectRevert(abi.encodeWithSelector(CommonErrorsLib.AddressZero.selector));
        new BridgeableTokenP(
            "aLz-EURp",
            "aLzEURp",
            address(aEURp),
            address(endpoints[aEid]),
            address(accessManager),
            wrongConfigParams
        );
    }

    function test_revertWhen_FeesRateExceedMaxAllowed() external {
        BridgeableTokenP.ConfigParams memory wrongConfigParams = BridgeableTokenP.ConfigParams({
            dailyCreditLimit: DEFAULT_DAILY_CREDIT_LIMIT,
            globalCreditLimit: DEFAULT_GLOBAL_CREDIT_LIMIT,
            dailyDebitLimit: DEFAULT_DAILY_DEBIT_LIMIT,
            globalDebitLimit: DEFAULT_GLOBAL_DEBIT_LIMIT,
            feesRecipient: users.feesRecipient.addr,
            feesRate: ContractConstantsLib.MAX_FEE + 1,
            isIsolateMode: false
        });
        vm.expectRevert(abi.encodeWithSelector(BridgeableTokenP_ErrorsLib.MaxFeesRateExceeded.selector));
        new BridgeableTokenP(
            "aLz-EURp",
            "aLzEURp",
            address(aEURp),
            address(endpoints[aEid]),
            address(accessManager),
            wrongConfigParams
        );
    }
}
