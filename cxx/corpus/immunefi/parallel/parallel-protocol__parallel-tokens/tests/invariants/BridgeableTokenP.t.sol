// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { SendParam, OFTReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";

import "../Invariants.t.sol";

contract BridgeableTokenPP_Invariants_Test is Invariants_Test {
    using OptionsBuilder for bytes;

    uint256 constant DEFAULT_MAX_BRIDGE_AMOUNT = 10e18;
    uint256 constant TOTAL_PAR_INITIAL_SUPPLY = INITIAL_BALANCE * 2;

    struct BridgeCall {
        address sendingBridgeableTokenP;
        address receivingBridgeableTokenPsContract;
        uint32 receivingEid;
        IERC20 principalToken;
    }

    BridgeCall[] internal bridgeableTokensContract;

    function setUp() public virtual override {
        _weightSelector(this.setFeesRate.selector, 10);
        _weightSelector(this.sendNoRevert.selector, 100);
        _weightSelector(this.getLzToken.selector, 80);
        _weightSelector(this.swapLzTokenToPrincipalTokenNoRevert.selector, 20);


        super.setUp();

        bridgeableTokensContract.push(
            BridgeCall({
                sendingBridgeableTokenP: address(aBridgeableTokenp),
                receivingBridgeableTokenPsContract: address(bBridgeableTokenp),
                receivingEid: bEid,
                principalToken: aEURp
            })
        );

        bridgeableTokensContract.push(
            BridgeCall({
                sendingBridgeableTokenP: address(bBridgeableTokenp),
                receivingBridgeableTokenPsContract: address(aBridgeableTokenp),
                receivingEid: aEid,
                principalToken: bEURp
            })
        );

        vm.startPrank(users.admin.addr);
        accessManager.grantRole(MINTER_ROLE_aEURp, address(aBridgeableTokenp),0);
        accessManager.grantRole(MINTER_ROLE_bEURp, address(bBridgeableTokenp),0);
        aEURp.mint(address(users.alice.addr), INITIAL_BALANCE);
        bEURp.mint(address(users.alice.addr), INITIAL_BALANCE);
        aEURp.mint(address(users.bob.addr), INITIAL_BALANCE);
        bEURp.mint(address(users.bob.addr), INITIAL_BALANCE);
        vm.stopPrank();
    }

    //-------------------------------------------
    // Invariants functions
    //-------------------------------------------

    function invariant_CreditDebitBalanceMatchBalances() external view {
        uint256 aliceBalanceaEURp = aEURp.balanceOf(users.alice.addr);
        uint256 aliceBalancebEURp = bEURp.balanceOf(users.alice.addr);

        uint256 bobBalanceaEURp = aEURp.balanceOf(users.bob.addr);
        uint256 bobBalancebEURp = bEURp.balanceOf(users.bob.addr);

        uint256 feesRecipientBalanceaEURp = aEURp.balanceOf(users.feesRecipient.addr);
        uint256 feesRecipientBalancebEURp = bEURp.balanceOf(users.feesRecipient.addr);

        uint256 totalaEURp = aliceBalanceaEURp + bobBalanceaEURp + feesRecipientBalanceaEURp;
        uint256 totalbEURp = aliceBalancebEURp + bobBalancebEURp + feesRecipientBalancebEURp;

        assertEq(aBridgeableTokenp.getCreditDebitBalance(), int256(totalaEURp) - int256(TOTAL_PAR_INITIAL_SUPPLY));
        assertEq(bBridgeableTokenp.getCreditDebitBalance(), int256(totalbEURp) - int256(TOTAL_PAR_INITIAL_SUPPLY));
    }

    function invariant_ParInitialSupplyMatchParPlusLzParSupply() external view {
        uint256 aliceBalanceaEURp = aEURp.balanceOf(users.alice.addr);
        uint256 aliceBalancebEURp = bEURp.balanceOf(users.alice.addr);

        uint256 bobBalanceaEURp = aEURp.balanceOf(users.bob.addr);
        uint256 bobBalancebEURp = bEURp.balanceOf(users.bob.addr);

        uint256 feesRecipientBalanceaEURp = aEURp.balanceOf(users.feesRecipient.addr);
        uint256 feesRecipientBalancebEURp = bEURp.balanceOf(users.feesRecipient.addr);
        uint256 totalaEURp = aliceBalanceaEURp + bobBalanceaEURp + feesRecipientBalanceaEURp;
        uint256 totalbEURp = aliceBalancebEURp + bobBalancebEURp + feesRecipientBalancebEURp;
        _assertTotalSupply(TOTAL_PAR_INITIAL_SUPPLY * 2, totalaEURp, totalbEURp);
    }

    //-------------------------------------------
    // Handlers functions
    //-------------------------------------------

    function setFeesRate(uint16 rate, uint256 bridgeSeed) external logCall("setFeesRate") {
        rate = _boundUint16(rate, 0, ContractConstantsLib.MAX_FEE);
        vm.startPrank(users.guardian.addr);
        BridgeCall memory bridgeCall = _randomBridgeableTokenPContract(bridgeSeed);
        accessManager.execute(address(bridgeCall.sendingBridgeableTokenP), abi.encodeWithSelector(BridgeableTokenP.setFeesRate.selector, rate));
        vm.stopPrank();
    }

    function sendNoRevert(uint256 amountToSend, uint256 bridgeSeed, bool sendPrincipalToken) external logCall("send") {
        BridgeCall memory bridgeCall = _randomBridgeableTokenPContract(bridgeSeed);
        amountToSend = _boundBridgeAmount(amountToSend, 1e18, DEFAULT_MAX_BRIDGE_AMOUNT);
        _bridgeToken(amountToSend, sendPrincipalToken, bridgeCall);
    }

    function getLzToken(uint256 amountToSend, uint256 bridgeSeed) external logCall("getLzToken") {
        amountToSend = _boundBridgeAmount(amountToSend, 1e18, DEFAULT_MAX_BRIDGE_AMOUNT);
        _getLzToken(amountToSend, bridgeSeed);
    }

    function swapLzTokenToPrincipalTokenNoRevert(
        uint256 amountToSwap,
        uint256 bridgeSeed
    ) external logCall("swapLzTokenToPrincipalToken") {
        BridgeCall memory bridgeCall = _randomBridgeableTokenPContract(bridgeSeed);
        BridgeableTokenP bridgeableToken = BridgeableTokenP(bridgeCall.sendingBridgeableTokenP);
        uint256 senderLzBalance = bridgeableToken.balanceOf(msg.sender);
        if (senderLzBalance == 0) return;
        amountToSwap = _boundBridgeAmount(amountToSwap, 1e18, senderLzBalance);
        bridgeableToken.swapLzTokenToPrincipalToken(users.alice.addr, amountToSwap);
    }

    //-------------------------------------------
    // Internal functions
    //-------------------------------------------

    function _getLzToken(uint256 lzAmountToReceive, uint256 bridgeSeed) internal logCall("getLzToken") {
        address sender = msg.sender;
        BridgeCall memory bridgeCall = _randomBridgeableTokenPContract(bridgeSeed);
        BridgeableTokenP bridgeableToken = BridgeableTokenP(bridgeCall.receivingBridgeableTokenPsContract);
        vm.startPrank(users.guardian.addr);
        accessManager.execute(address(bridgeableToken), abi.encodeWithSelector(BridgeableTokenP.setDailyCreditLimit.selector, 0));
        vm.stopPrank();

        vm.startPrank(sender);
        _bridgeToken(lzAmountToReceive, true, bridgeCall);

        vm.startPrank(users.guardian.addr);
        accessManager.execute(address(bridgeableToken), abi.encodeWithSelector(BridgeableTokenP.setDailyCreditLimit.selector, DEFAULT_DAILY_CREDIT_LIMIT));
        vm.stopPrank();

        vm.startPrank(sender);
    }

    function _bridgeToken(
        uint256 amountToSend,
        bool sendPrincipalToken,
        BridgeCall memory bridgeCall
    ) internal logCall("bridgeToken") {
        BridgeableTokenP bridgeableToken = BridgeableTokenP(bridgeCall.sendingBridgeableTokenP);
        if (!sendPrincipalToken && bridgeableToken.balanceOf(msg.sender) < amountToSend) {
            sendPrincipalToken = true;
        }

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParam = SendParam(
            bridgeCall.receivingEid,
            addressToBytes32(msg.sender),
            amountToSend,
            amountToSend,
            options,
            abi.encode(sendPrincipalToken),
            ""
        );
        MessagingFee memory fees = bridgeableToken.quoteSend(sendParam, false);
        vm.startPrank(msg.sender);
        bridgeableToken.send{ value: fees.nativeFee }(sendParam, fees, payable(msg.sender));
        verifyPackets(bridgeCall.receivingEid, addressToBytes32(address(bridgeCall.receivingBridgeableTokenPsContract)));
    }

    function _randomBridgeableTokenPContract(uint256 seed) internal view returns (BridgeCall memory) {
        return bridgeableTokensContract[seed % bridgeableTokensContract.length];
    }

    function _assertTotalSupply(uint256 expectedTotalSupply, uint256 totalaEURp, uint256 totalbEURp) internal view {
        uint256 aliceLzaEURp = aBridgeableTokenp.balanceOf(users.alice.addr);
        uint256 aliceLzbEURp = bBridgeableTokenp.balanceOf(users.alice.addr);
        uint256 bobBalanceLzaEURp = aBridgeableTokenp.balanceOf(users.bob.addr);
        uint256 bobBalanceLzbEURp = bBridgeableTokenp.balanceOf(users.bob.addr);
        assertEq(
            expectedTotalSupply,
            totalaEURp + totalbEURp + aliceLzaEURp + aliceLzbEURp + bobBalanceLzaEURp + bobBalanceLzbEURp
        );
    }
}
