// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Integrations.t.sol";

import { OptionsHelper } from "@layerzerolabs/test-devtools-evm-foundry/contracts/OptionsHelper.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { OFTMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";

contract BridgeableTokenpP_LzReceive_Integrations_Test is Integrations_Test {
    using OptionsBuilder for bytes;
    using PercentageMathLib for uint256;
    using OFTMsgCodec for bytes;

    bool sendPrincipalToken = true;
    bool sendLzToken = false;

    bytes32 guid = hex"0000000000000000000000000000000000000000000000000000000000000001";

    function test_LzReceive_TokenP_From_PrincipalToken_Sent(uint256 amountSent) external {
        amountSent = _boundBridgeAmount(amountSent, 1e18, DEFAULT_DAILY_CREDIT_LIMIT);
        uint256 expectedFeesAmount = amountSent.percentMul(DEFAULT_FEE_RATE);
        uint256 expectedReceivedAmount = amountSent - expectedFeesAmount;

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        (uint256 gas, uint256 value) = OptionsHelper._parseExecutorLzReceiveOption(options);

        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(users.alice.addr),
            amountSent,
            amountSent,
            options,
            abi.encode(sendPrincipalToken),
            ""
        );

        Origin memory origin = Origin(aEid, addressToBytes32(address(aBridgeableTokenp)), 1);
        (bytes memory message, ) = buildMessage(sendParam);

        address endpoint = address(bBridgeableTokenp.endpoint());
        vm.startPrank(endpoint);
        bBridgeableTokenp.lzReceive{ value: value, gas: gas }(
            origin,
            guid,
            message,
            address(bBridgeableTokenp),
            bytes("")
        );

        assertEq(bEURp.balanceOf(users.alice.addr), expectedReceivedAmount);
        assertEq(bEURp.balanceOf(users.feesRecipient.addr), expectedFeesAmount);
    }

    function test_LzReceive_TokenP_From_LzToken_Sent(uint256 amountSent) external {
        amountSent = _boundBridgeAmount(amountSent, 1e18, DEFAULT_DAILY_CREDIT_LIMIT);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        (uint256 gas, uint256 value) = OptionsHelper._parseExecutorLzReceiveOption(options);

        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(users.alice.addr),
            amountSent,
            amountSent,
            options,
            abi.encode(sendLzToken),
            ""
        );

        Origin memory origin = Origin(aEid, addressToBytes32(address(aBridgeableTokenp)), 1);
        (bytes memory message, ) = buildMessage(sendParam);

        address endpoint = address(bBridgeableTokenp.endpoint());
        vm.startPrank(endpoint);
        bBridgeableTokenp.lzReceive{ value: value, gas: gas }(
            origin,
            guid,
            message,
            address(bBridgeableTokenp),
            bytes("")
        );

        assertEq(bEURp.balanceOf(users.alice.addr), amountSent);
        assertEq(bEURp.balanceOf(users.feesRecipient.addr), 0);
    }

    modifier reachGlobalCreditLimit() {
        vm.startPrank(users.guardian.addr);
        /// @dev By setting the credit daily limit to 0, we direclty reach the global credit limit
        accessManager.execute(address(bBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setGlobalCreditLimit.selector, 0));
        _;
    }

    function test_LzReceive_LzToken(uint256 amountSent) external reachGlobalCreditLimit {
        amountSent = _boundBridgeAmount(amountSent, 1e18, DEFAULT_DAILY_DEBIT_LIMIT);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        (uint256 gas, uint256 value) = OptionsHelper._parseExecutorLzReceiveOption(options);

        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(users.alice.addr),
            amountSent,
            amountSent,
            options,
            abi.encode(sendLzToken),
            ""
        );

        Origin memory origin = Origin(aEid, addressToBytes32(address(aBridgeableTokenp)), 1);
        (bytes memory message, ) = buildMessage(sendParam);

        address endpoint = address(bBridgeableTokenp.endpoint());
        vm.startPrank(endpoint);
        bBridgeableTokenp.lzReceive{ value: value, gas: gas }(
            origin,
            guid,
            message,
            address(bBridgeableTokenp),
            bytes("")
        );

        assertEq(bEURp.balanceOf(users.alice.addr), 0);
        assertEq(bBridgeableTokenp.balanceOf(users.alice.addr), amountSent);
        assertEq(bEURp.balanceOf(users.feesRecipient.addr), 0);
    }

    modifier reachGlobalLimitWithNegativeCreditDebitBalance() {
        uint256 amountToBridge = 10e18;
        vm.startPrank(users.admin.addr);
        bEURp.mint(users.alice.addr, amountToBridge);

        vm.startPrank(users.guardian.addr);
        /// @dev Set the global limit close to daily limit to simplify test
        accessManager.execute(address(bBridgeableTokenp), abi.encodeWithSelector(BridgeableTokenP.setGlobalCreditLimit.selector, 100e18));
    
        /// @dev Bridge to make creditDebitBalance Negative
        vm.startPrank(users.alice.addr);
        _sendToken(bBridgeableTokenp, address(aBridgeableTokenp), aEid, sendPrincipalToken, amountToBridge, users.alice.addr);

        assertEq(bBridgeableTokenp.getCreditDebitBalance(), -int256(amountToBridge));
        _;
    }
    
    function test_LzReceive_NotRevertWhen_CreditDebitLimitNegativeAndGlobalCreditAmountIsExceededDuringTx()
        external
        reachGlobalLimitWithNegativeCreditDebitBalance
    {
        uint256 expectedPrincipalReceived = 110e18;
        uint256 expectedOFTReceived = 1e18;
        uint256 amountToCredit = expectedPrincipalReceived + expectedOFTReceived;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        (uint256 gas, uint256 value) = OptionsHelper._parseExecutorLzReceiveOption(options);

        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(users.bob.addr),
            amountToCredit,
            amountToCredit,
            options,
            abi.encode(sendLzToken),
            ""
        );

        Origin memory origin = Origin(aEid, addressToBytes32(address(aBridgeableTokenp)), 1);
        (bytes memory message, ) = buildMessage(sendParam);

        address endpoint = address(bBridgeableTokenp.endpoint());
        vm.startPrank(endpoint);
        bBridgeableTokenp.lzReceive{ value: value, gas: gas }(
            origin,
            guid,
            message,
            address(bBridgeableTokenp),
            bytes("")
        );

        assertEq(bEURp.balanceOf(users.bob.addr), expectedPrincipalReceived);
        assertEq(bBridgeableTokenp.balanceOf(users.bob.addr), expectedOFTReceived);
    }

    function buildMessage(SendParam memory _sendParam) internal view returns (bytes memory, bytes memory) {
        (bytes memory message, ) = OFTMsgCodec.encode(
            _sendParam.to,
            uint64(_sendParam.amountLD / 1e12),
            _sendParam.composeMsg
        );
        return (message, _sendParam.extraOptions);
    }
}
