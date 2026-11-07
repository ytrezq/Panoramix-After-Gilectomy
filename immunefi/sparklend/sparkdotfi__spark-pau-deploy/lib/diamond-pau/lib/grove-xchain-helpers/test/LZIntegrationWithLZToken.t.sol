// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { LZBridgeTesting }    from "src/testing/bridges/LZBridgeTesting.sol";
import { LZReceiver, Origin } from "src/receivers/LZReceiver.sol";
import { RecordedLogs }       from "src/testing/utils/RecordedLogs.sol";

import {
    ILayerZeroEndpointV2,
    LZForwarder,
    MessagingFee,
    MessagingParams
} from "src/forwarders/LZForwarder.sol";

import { MessageSender } from "test/mocks/MessageSender.sol";

import "./IntegrationBase.t.sol";

interface ITreasury {
    function setLzTokenEnabled(bool _lzTokenEnabled) external;
    function setLzTokenFee(uint256 _lzTokenFee) external;
}

contract LZIntegrationTestWithLZToken is IntegrationBaseTest {

    using DomainHelpers   for *;
    using LZBridgeTesting for *;
    using OptionsBuilder  for bytes;

    uint32 sourceEndpointId = LZForwarder.ENDPOINT_ID_ETHEREUM;
    uint32 destinationEndpointId;

    address sourceEndpoint = LZForwarder.ENDPOINT_ETHEREUM;
    address destinationEndpoint;

    address sourceExecutor = LZForwarder.EXECUTOR_ETHEREUM;
    address destinationExecutor;

    address[] sourceDVNs      = [LZForwarder.LAYER_ZERO_DVN_ETHEREUM, LZForwarder.NETHERMIND_DVN_ETHEREUM];
    address[] destinationDVNs = new address[](2);

    address lzToken  = 0x6985884C4392D348587B19cb9eAAf157F13271cd;
    address lzOwner  = 0xBe010A7e3686FdF65E93344ab664D065A0B02478;
    address treasury = 0x5ebB3f2feaA15271101a927869B3A56837e73056;

    Domain destination2;
    Bridge bridge2;

    function setUp() public override {
        super.setUp();

        source.selectFork();

        vm.startPrank(lzOwner);
        ILayerZeroEndpointV2(sourceEndpoint).setLzToken(lzToken);
        ITreasury(treasury).setLzTokenEnabled(true);
        ITreasury(treasury).setLzTokenFee(1e18);
        vm.stopPrank();
    }

    function test_invalidDVN() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationExecutor   = LZForwarder.EXECUTOR_BASE;
        destinationDVNs[0]    = LZForwarder.LAYER_ZERO_DVN_BASE;
        destinationDVNs[1]    = LZForwarder.NETHERMIND_DVN_BASE;
        sourceDVNs            = new address[](1);
        sourceDVNs[0]         = 0x747C741496a507E4B404b50463e691A8d692f6Ac; // Ethereum Mainnet Dead DVN
        initBaseContracts(getChain("base").createFork());

        source.selectFork();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        bytes memory message = abi.encodeCall(MessageOrdering.push, (1));

        MessagingParams memory params = MessagingParams({
            dstEid       : destinationEndpointId,
            receiver     : bytes32(uint256(uint160(destinationReceiver))),
            message      : message,
            options      : options,
            payInLzToken : true
        });

        // Not able to quote fee with misconfigured DVN
        vm.expectRevert("Please set your OApp's DVNs and/or Executor");
        ILayerZeroEndpointV2(bridge.sourceCrossChainMessenger).quote(params, sourceAuthority);

        uint256 forecastedNativeFee = 20_256_857_875_471;

        // Not able to send message with misconfigured DVN
        vm.prank(sourceAuthority);
        vm.expectRevert("Please set your OApp's DVNs and/or Executor");
        MessageSender(payable(sourceAuthority)).sendMessage{value: forecastedNativeFee}(
            destinationEndpointId,
            bytes32(uint256(uint160(destinationReceiver))),
            bridge.sourceCrossChainMessenger,
            message,
            options,
            sourceAuthority,
            true
        );
    }

    function test_base() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationExecutor   = LZForwarder.EXECUTOR_BASE;
        destinationDVNs[0]    = LZForwarder.LAYER_ZERO_DVN_BASE;
        destinationDVNs[1]    = LZForwarder.NETHERMIND_DVN_BASE;

        runCrossChainTests(getChain("base").createFork());
    }

    function test_binance() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BNB;
        destinationEndpoint   = LZForwarder.ENDPOINT_BNB;
        destinationExecutor   = LZForwarder.EXECUTOR_BNB;
        destinationDVNs[0]    = LZForwarder.NETHERMIND_DVN_BNB;
        destinationDVNs[1]    = LZForwarder.LAYER_ZERO_DVN_BNB;

        runCrossChainTests(getChain("bnb_smart_chain").createFork());
    }

    function test_monad() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_MONAD;
        destinationEndpoint   = LZForwarder.ENDPOINT_MONAD;
        destinationExecutor   = LZForwarder.EXECUTOR_MONAD;
        destinationDVNs[0]    = LZForwarder.LAYER_ZERO_DVN_MONAD;
        destinationDVNs[1]    = LZForwarder.NETHERMIND_DVN_MONAD;

        runCrossChainTests(getChain("monad").createFork());
    }

    function test_plasma() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_PLASMA;
        destinationEndpoint   = LZForwarder.ENDPOINT_PLASMA;
        destinationExecutor   = LZForwarder.EXECUTOR_PLASMA;
        destinationDVNs[0]    = LZForwarder.LAYER_ZERO_DVN_PLASMA;
        destinationDVNs[1]    = LZForwarder.NETHERMIND_DVN_PLASMA;

        runCrossChainTests(getChain("plasma").createFork());
    }

    function initSourceReceiver() internal override returns (address) {
        // Etch MessageSender at sourceAuthority
        MessageSender senderImpl = new MessageSender();
        vm.etch(sourceAuthority, address(senderImpl).code);
        vm.deal(sourceAuthority, 1000 ether);

        MessageSender(payable(sourceAuthority)).configureSender(
            sourceEndpoint,
            destinationEndpointId,
            sourceDVNs,
            sourceExecutor
        );

        LZReceiver.UlConfigParams memory ulnConfigParams
            = LZReceiver.UlConfigParams({
                confirmations        : 15,
                requiredDVNs         : sourceDVNs,
                optionalDVNs         : new address[](0),
                optionalDVNThreshold : 0
            });

        return address(new LZReceiver(
            sourceEndpoint,
            destinationEndpointId,
            bytes32(uint256(uint160(destinationAuthority))),
            address(moSource),
            makeAddr("delegate"),
            makeAddr("owner"),
            ulnConfigParams
        ));
    }

    function initDestinationReceiver() internal override returns (address) {
        MessageSender senderImpl = new MessageSender();
        vm.etch(destinationAuthority, address(senderImpl).code);
        vm.deal(destinationAuthority, 1000 ether);

        MessageSender(payable(destinationAuthority)).configureSender(
            destinationEndpoint,
            sourceEndpointId,
            destinationDVNs,
            destinationExecutor
        );

        LZReceiver.UlConfigParams memory ulnConfigParams
            = LZReceiver.UlConfigParams({
                confirmations        : 15,
                requiredDVNs         : destinationDVNs,
                optionalDVNs         : new address[](0),
                optionalDVNThreshold : 0
            });

        return address(new LZReceiver(
            destinationEndpoint,
            sourceEndpointId,
            bytes32(uint256(uint160(sourceAuthority))),
            address(moDestination),
            makeAddr("delegate"),
            makeAddr("owner"),
            ulnConfigParams
        ));
    }

    function initBridgeTesting() internal override returns (Bridge memory) {
        return LZBridgeTesting.createLZBridge(source, destination);
    }

    function queueSourceToDestination(bytes memory message) internal override {
        source.selectFork();

        // Gas to queue message
        vm.deal(sourceAuthority, 1 ether);
        deal(lzToken, sourceAuthority, 1 ether);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        assertEq(IERC20(lzToken).balanceOf(address(sourceAuthority)), 1 ether);
        assertEq(address(sourceAuthority).balance,                    1 ether);

        // Calculate fee
        MessagingParams memory params = MessagingParams({
            dstEid       : destinationEndpointId,
            receiver     : bytes32(uint256(uint160(destinationReceiver))),
            message      : message,
            options      : options,
            payInLzToken : true
        });
        MessagingFee memory fee = ILayerZeroEndpointV2(bridge.sourceCrossChainMessenger).quote(params, sourceAuthority);

        // Call through the MessageSender contract (sourceAuthority)
        MessageSender(payable(sourceAuthority)).sendMessage{value: fee.nativeFee}(
            destinationEndpointId,
            bytes32(uint256(uint160(destinationReceiver))),
            bridge.sourceCrossChainMessenger,
            message,
            options,
            sourceAuthority,
            true
        );

        // LZ token and ETH spent
        assertLt(IERC20(lzToken).balanceOf(address(sourceAuthority)), 1 ether);
        assertLt(address(sourceAuthority).balance,                    1 ether);
    }

    function queueDestinationToSource(bytes memory message) internal override {
        destination.selectFork();

        vm.deal(destinationAuthority, 1000 ether); // Gas to queue message

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        // Calculate fee
        MessagingParams memory params = MessagingParams({
            dstEid       : sourceEndpointId,
            receiver     : bytes32(uint256(uint160(sourceReceiver))),
            message      : message,
            options      : options,
            payInLzToken : false
        });
        MessagingFee memory fee = ILayerZeroEndpointV2(bridge.destinationCrossChainMessenger).quote(params, destinationAuthority);

        // Call through the MessageSender contract (destinationAuthority)
        MessageSender(payable(destinationAuthority)).sendMessage{value: fee.nativeFee}(
            sourceEndpointId,
            bytes32(uint256(uint160(sourceReceiver))),
            bridge.destinationCrossChainMessenger,
            message,
            options,
            destinationAuthority,
            false
        );
    }

    function relaySourceToDestination() internal override {
        bridge.relayMessagesToDestination(true, sourceAuthority, destinationReceiver);
    }

    function relayDestinationToSource() internal override {
        bridge.relayMessagesToSource(true, destinationAuthority, sourceReceiver);
    }

}
