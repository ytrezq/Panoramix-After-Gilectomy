// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Integrations.t.sol";

contract BridgeableTokenpP_Send_Integrations_Test is Integrations_Test {
    using OptionsBuilder for bytes;
    using PercentageMathLib for uint256;

    uint256 PRINCIPAL_TOKEN_AMOUNT_MINTED = DEFAULT_DAILY_DEBIT_LIMIT / 2;
    bool sendPrincipalToken = true;
    bool sendLzToken = false;
    
    function setUp() public override {
        super.setUp();
        sigUtils = new SigUtils(aEURp.DOMAIN_SEPARATOR());

        vm.startPrank(users.admin.addr);
        accessManager.grantRole(MINTER_ROLE_aEURp, address(aBridgeableTokenp),0);
        accessManager.grantRole(MINTER_ROLE_bEURp, address(bBridgeableTokenp),0);
        aEURp.mint(address(users.alice.addr), INITIAL_BALANCE);
        bEURp.mint(address(users.alice.addr), INITIAL_BALANCE);
        vm.stopPrank();
    }

    function test_Send_EURp_Receive_EURp(uint256 amountToSend) external {
        amountToSend = _boundBridgeAmount(amountToSend, 1e18, DEFAULT_DAILY_DEBIT_LIMIT);
        uint256 expectedFeesAmount = amountToSend.percentMul(DEFAULT_FEE_RATE);
        uint256 expectedReceivedAmount = amountToSend - expectedFeesAmount;

        vm.startPrank(users.alice.addr);

        _sendToken(aBridgeableTokenp, address(bBridgeableTokenp), bEid, sendPrincipalToken, amountToSend, users.alice.addr);

        assertEq(aEURp.balanceOf(users.alice.addr), INITIAL_BALANCE - amountToSend);
        assertEq(aEURp.balanceOf(address(aBridgeableTokenp)), 0);

        assertEq(aBridgeableTokenp.balanceOf(users.alice.addr), 0);
        assertEq(aBridgeableTokenp.getCurrentDailyCreditAmount(), 0);
        assertEq(aBridgeableTokenp.getCurrentDailyDebitAmount(), amountToSend);
        assertEq(aBridgeableTokenp.getCreditDebitBalance(), -int256(amountToSend));
        assertEq(aBridgeableTokenp.getMaxDebitableAmount(), DEFAULT_DAILY_DEBIT_LIMIT - amountToSend);

        assertEq(bEURp.balanceOf(users.alice.addr), INITIAL_BALANCE + expectedReceivedAmount);
        assertEq(bEURp.balanceOf(users.feesRecipient.addr), expectedFeesAmount);
        assertEq(bBridgeableTokenp.balanceOf(users.alice.addr), 0);
        assertEq(bBridgeableTokenp.getCurrentDailyCreditAmount(), amountToSend);
        assertEq(bBridgeableTokenp.getCurrentDailyDebitAmount(), 0);
        assertEq(bBridgeableTokenp.getCreditDebitBalance(), int256(amountToSend));
        assertEq(bBridgeableTokenp.getMaxCreditableAmount(), DEFAULT_DAILY_CREDIT_LIMIT - amountToSend);
    }

    modifier resetAllowance() {
        vm.startPrank(users.alice.addr);
        aEURp.approve(address(aBridgeableTokenp), 0);
        vm.stopPrank();
        _;
    }
    
    function test_SendWithPermit_Send_EURp_Receive_EURp(uint256 amountToSend) external resetAllowance{
        amountToSend = _boundBridgeAmount(amountToSend, 1e18, DEFAULT_DAILY_DEBIT_LIMIT);
        uint256 expectedFeesAmount = amountToSend.percentMul(DEFAULT_FEE_RATE);
        uint256 expectedReceivedAmount = amountToSend - expectedFeesAmount;
        
        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = 
            _signPermitData(users.alice.privateKey, address(aBridgeableTokenp), amountToSend, address(aEURp));

        vm.startPrank(users.alice.addr);
       _sendTokenWithPermit(aBridgeableTokenp, address(bBridgeableTokenp), bEid, sendPrincipalToken, amountToSend, users.alice.addr, BridgeableTokenP.PermitCalldata(deadline, v, r, s));

        assertEq(aEURp.balanceOf(users.alice.addr), INITIAL_BALANCE - amountToSend);
        assertEq(aEURp.balanceOf(address(aBridgeableTokenp)), 0);

        assertEq(aBridgeableTokenp.balanceOf(users.alice.addr), 0);
        assertEq(aBridgeableTokenp.getCurrentDailyCreditAmount(), 0);
        assertEq(aBridgeableTokenp.getCurrentDailyDebitAmount(), amountToSend);
        assertEq(aBridgeableTokenp.getCreditDebitBalance(), -int256(amountToSend));
        assertEq(aBridgeableTokenp.getMaxDebitableAmount(), DEFAULT_DAILY_DEBIT_LIMIT - amountToSend);

        assertEq(bEURp.balanceOf(users.alice.addr), INITIAL_BALANCE + expectedReceivedAmount);
        assertEq(bEURp.balanceOf(users.feesRecipient.addr), expectedFeesAmount);
        assertEq(bBridgeableTokenp.balanceOf(users.alice.addr), 0);
        assertEq(bBridgeableTokenp.getCurrentDailyCreditAmount(), amountToSend);
        assertEq(bBridgeableTokenp.getCurrentDailyDebitAmount(), 0);
        assertEq(bBridgeableTokenp.getCreditDebitBalance(), int256(amountToSend));
        assertEq(bBridgeableTokenp.getMaxCreditableAmount(), DEFAULT_DAILY_CREDIT_LIMIT - amountToSend);
    }

    modifier getLzEURp() {
        vm.startPrank(users.guardian.addr);
        /// @dev By setting the daily credit limit to 0, we can only mint bLz-EURp
        accessManager.execute(address(bBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setGlobalCreditLimit.selector, 0));

        /// @dev recieve bLz-Eurp
        vm.startPrank(users.alice.addr);
        _sendToken(
            aBridgeableTokenp,
            address(bBridgeableTokenp),
            bEid,
            sendPrincipalToken,
            DEFAULT_DAILY_DEBIT_LIMIT,
            users.alice.addr
        );
        _;
    }

    function test_Send_LzEURp_Receive_EURp(uint256 amountToSend) external getLzEURp {
        vm.startPrank(users.alice.addr);
        uint256 bLzEURpAmount = _serializeAmountForOFT(DEFAULT_DAILY_DEBIT_LIMIT);
        uint256 aEURpAliceBalance = INITIAL_BALANCE - bLzEURpAmount;
        amountToSend = _boundBridgeAmount(amountToSend, 1e18, bLzEURpAmount);

        assertEq(aEURp.balanceOf(users.alice.addr), aEURpAliceBalance);
        assertEq(bEURp.balanceOf(users.alice.addr), INITIAL_BALANCE);
        assertEq(bBridgeableTokenp.balanceOf(users.alice.addr), bLzEURpAmount);

        _sendToken(bBridgeableTokenp, address(aBridgeableTokenp), aEid, sendLzToken, amountToSend, users.alice.addr);

        assertEq(aEURp.balanceOf(users.alice.addr), aEURpAliceBalance + amountToSend);
        assertEq(aEURp.balanceOf(users.feesRecipient.addr), 0);

        assertEq(aBridgeableTokenp.balanceOf(users.alice.addr), 0);
        assertEq(aBridgeableTokenp.getCurrentDailyDebitAmount(), bLzEURpAmount);
        assertEq(aBridgeableTokenp.getCurrentDailyCreditAmount(), amountToSend);
        assertEq(aBridgeableTokenp.getCreditDebitBalance(), int256(amountToSend) - int256(bLzEURpAmount));

        assertEq(bEURp.balanceOf(users.alice.addr), INITIAL_BALANCE);
        assertEq(bEURp.balanceOf(users.feesRecipient.addr), 0);
        assertEq(bBridgeableTokenp.balanceOf(users.alice.addr), bLzEURpAmount - amountToSend);
        assertEq(bBridgeableTokenp.getCurrentDailyCreditAmount(), 0);
        assertEq(bBridgeableTokenp.getCurrentDailyDebitAmount(), 0);
        assertEq(bBridgeableTokenp.getCreditDebitBalance(), 0);
    }

    modifier reachGlobalCreditLimit() {
        vm.startPrank(users.guardian.addr);
        /// @dev By setting the credit daily limit to 0, we direclty reach the global credit limit
        accessManager.execute(address(bBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setGlobalCreditLimit.selector, 0));
        _;
    }

    function test_ReachGlobalCreditLimit_ShouldReceiveLzEURp(uint256 amountToSend) external reachGlobalCreditLimit {
        amountToSend = _boundBridgeAmount(amountToSend, 1e18, DEFAULT_DAILY_DEBIT_LIMIT);
        vm.startPrank(users.alice.addr);
        _sendToken(aBridgeableTokenp, address(bBridgeableTokenp), bEid, sendPrincipalToken, amountToSend, users.alice.addr);

        assertEq(aEURp.balanceOf(users.alice.addr), INITIAL_BALANCE - amountToSend);
        assertEq(aBridgeableTokenp.balanceOf(users.alice.addr), 0);
        assertEq(aBridgeableTokenp.getCurrentDailyDebitAmount(), amountToSend);
        assertEq(aBridgeableTokenp.getCurrentDailyCreditAmount(), 0);
        assertEq(aBridgeableTokenp.getCreditDebitBalance(), -int256(amountToSend));

        assertEq(bEURp.balanceOf(users.alice.addr), INITIAL_BALANCE);
        assertEq(bEURp.balanceOf(users.feesRecipient.addr), 0);
        assertEq(bBridgeableTokenp.balanceOf(users.alice.addr), amountToSend);
        assertEq(bBridgeableTokenp.getCurrentDailyCreditAmount(), 0);
        assertEq(bBridgeableTokenp.getCurrentDailyDebitAmount(), 0);
        assertEq(bBridgeableTokenp.getCreditDebitBalance(), 0);
    }

    modifier reachDailyCreditLimit() {
        vm.startPrank(users.guardian.addr);
        /// @dev By setting the daily credit limit to 0, we direclty reach the limit.
        accessManager.execute(address(bBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setDailyCreditLimit.selector, 0));
        _;
    }

    function test_ReachDailyCreditLimit_ShouldReceiveLzEURp(uint256 amountToSend) external reachDailyCreditLimit {
        amountToSend = _boundBridgeAmount(amountToSend, 1e18, DEFAULT_DAILY_DEBIT_LIMIT);
        vm.startPrank(users.alice.addr);
        _sendToken(aBridgeableTokenp, address(bBridgeableTokenp), bEid, sendPrincipalToken, amountToSend, users.alice.addr);

        assertEq(aEURp.balanceOf(users.alice.addr), INITIAL_BALANCE - amountToSend);
        assertEq(aBridgeableTokenp.balanceOf(users.alice.addr), 0);
        assertEq(aBridgeableTokenp.getCurrentDailyDebitAmount(), amountToSend);
        assertEq(aBridgeableTokenp.getCurrentDailyCreditAmount(), 0);
        assertEq(aBridgeableTokenp.getCreditDebitBalance(), -int256(amountToSend));

        assertEq(bEURp.balanceOf(users.alice.addr), INITIAL_BALANCE);
        assertEq(bEURp.balanceOf(users.feesRecipient.addr), 0);
        assertEq(bBridgeableTokenp.balanceOf(users.alice.addr), amountToSend);
        assertEq(bBridgeableTokenp.getCurrentDailyCreditAmount(), 0);
        assertEq(bBridgeableTokenp.getCurrentDailyDebitAmount(), 0);
        assertEq(bBridgeableTokenp.getCreditDebitBalance(), 0);
    }

    modifier reachDailyDebitLimit() {
        vm.startPrank(users.guardian.addr);
        /// @dev By setting the daily debit limit to 0, we direclty reach the limit.
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setDailyDebitLimit.selector, 0));
        _;
    }

    function test_RevertWhen_DailyDebitLimitReached(uint256 amountToSend) external reachDailyDebitLimit {
        amountToSend = _boundBridgeAmount(amountToSend, DEFAULT_DAILY_DEBIT_LIMIT, uint256(type(int256).max));

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(users.alice.addr),
            amountToSend,
            amountToSend,
            options,
            abi.encode(sendPrincipalToken),
            ""
        );

        MessagingFee memory fees = aBridgeableTokenp.quoteSend(sendParam, false);
        vm.startPrank(users.alice.addr);
        vm.expectRevert(BridgeableTokenP_ErrorsLib.DailyDebitLimitReached.selector);
        aBridgeableTokenp.send{ value: fees.nativeFee }(sendParam, fees, payable(users.alice.addr));
    }

    modifier reachGlobalDebitLimit() {
        vm.startPrank(users.guardian.addr);
        /// @dev By setting the global debit limit to 0, we direclty reach the limit.
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setGlobalDebitLimit.selector, 0));
        _;
    }

    function test_RevertWhen_GlobalDebitLimitReached(uint256 amountToSend) external reachGlobalDebitLimit {
        amountToSend = _boundBridgeAmount(amountToSend, 1e18, DEFAULT_DAILY_DEBIT_LIMIT);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(users.alice.addr),
            amountToSend,
            amountToSend,
            options,
            abi.encode(sendPrincipalToken),
            ""
        );

        MessagingFee memory fees = aBridgeableTokenp.quoteSend(sendParam, false);

        vm.startPrank(users.alice.addr);
        vm.expectRevert(BridgeableTokenP_ErrorsLib.GlobalDebitLimitReached.selector);
        aBridgeableTokenp.send{ value: fees.nativeFee }(sendParam, fees, payable(users.alice.addr));
    }

    modifier setIsolateMode() {
        vm.startPrank(users.guardian.addr);
        accessManager.execute(address(aBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.toggleIsolateMode.selector));
        _;
    }

    function test_RevertWhen_InIsolateModeCreditDebitBalanceBelowZero(uint256 amountToSend) external setIsolateMode {
        amountToSend = _boundBridgeAmount(amountToSend, 1e18, DEFAULT_DAILY_DEBIT_LIMIT);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(users.alice.addr),
            amountToSend,
            amountToSend,
            options,
            abi.encode(sendPrincipalToken),
            ""
        );

        MessagingFee memory fees = aBridgeableTokenp.quoteSend(sendParam, false);

        vm.startPrank(users.alice.addr);
        vm.expectRevert(BridgeableTokenP_ErrorsLib.IsolateModeLimitReach.selector);
        aBridgeableTokenp.send{ value: fees.nativeFee }(sendParam, fees, payable(users.alice.addr));
    }

    modifier sendAndUpdateGlobalCreditAmount(uint256 amountToSend) {
        amountToSend = _boundBridgeAmount(amountToSend, 1e18, DEFAULT_DAILY_DEBIT_LIMIT / 10);
        uint256 expectedFeesAmount = amountToSend.percentMul(DEFAULT_FEE_RATE);
        uint256 expectedReceivedAmount = amountToSend - expectedFeesAmount;
        vm.startPrank(users.alice.addr);
        _sendToken(aBridgeableTokenp, address(bBridgeableTokenp), bEid, sendPrincipalToken, amountToSend, users.alice.addr);

        vm.startPrank(users.guardian.addr);
        accessManager.execute(address(bBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setGlobalCreditLimit.selector, expectedReceivedAmount / 10));
        _;
    }

    function test_ReceivedLzEURp_When_GlobalCreditAmountUpdatedBelowCreditDebitBalance(
        uint256 amountToSend
    ) external sendAndUpdateGlobalCreditAmount(amountToSend) {
        amountToSend = _boundBridgeAmount(amountToSend, 1e18, DEFAULT_DAILY_DEBIT_LIMIT / 10);
        uint256 bLzEURpAmountAlice = bBridgeableTokenp.balanceOf(users.alice.addr);
        uint256 aEURpAmountAlice = aEURp.balanceOf(users.alice.addr);
        uint256 bEURpAmountAlice = bEURp.balanceOf(users.alice.addr);
        vm.startPrank(users.alice.addr);
        _sendToken(aBridgeableTokenp, address(bBridgeableTokenp), bEid, sendPrincipalToken, amountToSend, users.alice.addr);

        assertEq(aEURp.balanceOf(users.alice.addr), aEURpAmountAlice - amountToSend);
        assertEq(bEURp.balanceOf(users.alice.addr), bEURpAmountAlice);
        assertEq(bBridgeableTokenp.balanceOf(users.alice.addr), bLzEURpAmountAlice + amountToSend);
    }

    function test_RevertWhen_ComposeMsgLengthIsNot32Bytes() external {
        uint256 amountToSend = 1e18;
        vm.startPrank(users.alice.addr);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        /// @dev ComposeMsg is empty
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(users.alice.addr),
            amountToSend,
            amountToSend,
            options,
            "",
            ""
        );
        MessagingFee memory fees = aBridgeableTokenp.quoteSend(sendParam, false);
        vm.expectRevert(BridgeableTokenP_ErrorsLib.InvalidMsgLength.selector);
        aBridgeableTokenp.send{ value: fees.nativeFee }(sendParam, fees, payable(users.alice.addr));

        /// @dev ComposeMsg length is greater than 32 bytes
        sendParam = SendParam(
            bEid,
            addressToBytes32(users.alice.addr),
            amountToSend,
            amountToSend,
            options,
            abi.encode(true, false),
            ""
        );
        fees = aBridgeableTokenp.quoteSend(sendParam, false);
        vm.expectRevert(BridgeableTokenP_ErrorsLib.InvalidMsgLength.selector);
        aBridgeableTokenp.send{ value: fees.nativeFee }(sendParam, fees, payable(users.alice.addr));
    }

    function test_RevertWhen_ToIsAddressZero() external {
        vm.startPrank(users.alice.addr);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(address(0)),
            1e18,
            1e18,
            options,
            abi.encode(true),
            ""
        );
        MessagingFee memory fees = aBridgeableTokenp.quoteSend(sendParam, false);
        vm.expectRevert(CommonErrorsLib.AddressZero.selector);
        aBridgeableTokenp.send{ value: fees.nativeFee }(sendParam, fees, payable(msg.sender));
    }

}
