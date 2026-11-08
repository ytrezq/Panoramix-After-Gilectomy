// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./IntegrationBase.t.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { UlnConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

import {
    LZForwarder,
    ILayerZeroEndpointV2,
    MessagingParams,
    MessagingFee
} from "src/forwarders/LZForwarder.sol";

import { LZReceiver, Origin } from "src/receivers/LZReceiver.sol";

import { LZBridgeTesting } from "src/testing/bridges/LZBridgeTesting.sol";
import { RecordedLogs }    from "src/testing/utils/RecordedLogs.sol";

import { MessageSender } from "test/mocks/MessageSender.sol";

contract LZIntegrationTest is IntegrationBaseTest {

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

    Domain destination2;
    Bridge bridge2;

    error NoPeer(uint32 eid);
    error OnlyEndpoint(address addr);
    error OnlyPeer(uint32 eid, bytes32 sender);

    function test_invalidEndpoint() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationExecutor   = LZForwarder.EXECUTOR_BASE;
        destinationDVNs[0]    = LZForwarder.LAYER_ZERO_DVN_BASE;
        destinationDVNs[1]    = LZForwarder.NETHERMIND_DVN_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(OnlyEndpoint.selector, randomAddress));
        LZReceiver(destinationReceiver).lzReceive(
            Origin({
                srcEid: sourceEndpointId,
                sender: bytes32(uint256(uint160(sourceAuthority))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(MessageOrdering.push, (1)),
            address(0),
            ""
        );
    }

    function test_lzReceive_revertsNoPeer() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationExecutor   = LZForwarder.EXECUTOR_BASE;
        destinationDVNs[0]    = LZForwarder.LAYER_ZERO_DVN_BASE;
        destinationDVNs[1]    = LZForwarder.NETHERMIND_DVN_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert(abi.encodeWithSelector(NoPeer.selector, 0));
        LZReceiver(destinationReceiver).lzReceive(
            Origin({
                srcEid: 0,
                sender: bytes32(uint256(uint160(sourceAuthority))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(MessageOrdering.push, (1)),
            address(0),
            ""
        );
    }

    function test_lzReceive_revertsOnlyPeer() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationExecutor   = LZForwarder.EXECUTOR_BASE;
        destinationDVNs[0]    = LZForwarder.LAYER_ZERO_DVN_BASE;
        destinationDVNs[1]    = LZForwarder.NETHERMIND_DVN_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert(abi.encodeWithSelector(OnlyPeer.selector, sourceEndpointId, bytes32(uint256(uint160(randomAddress)))));
        LZReceiver(destinationReceiver).lzReceive(
            Origin({
                srcEid: sourceEndpointId,
                sender: bytes32(uint256(uint160(randomAddress))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(MessageOrdering.push, (1)),
            address(0),
            ""
        );
    }

    function test_invalidSourceEid() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationExecutor   = LZForwarder.EXECUTOR_BASE;
        destinationDVNs[0]    = LZForwarder.LAYER_ZERO_DVN_BASE;
        destinationDVNs[1]    = LZForwarder.NETHERMIND_DVN_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        // NOTE: To pass initial check, we set the peer.
        vm.prank(makeAddr("owner"));
        LZReceiver(destinationReceiver).setPeer(0, bytes32(uint256(uint160(sourceAuthority))));

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert("LZReceiver/invalid-srcEid");
        LZReceiver(destinationReceiver).lzReceive(
            Origin({
                srcEid: 0,
                sender: bytes32(uint256(uint160(sourceAuthority))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(MessageOrdering.push, (1)),
            address(0),
            ""
        );
    }

    function test_invalidSourceAuthority() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationExecutor   = LZForwarder.EXECUTOR_BASE;
        destinationDVNs[0]    = LZForwarder.LAYER_ZERO_DVN_BASE;
        destinationDVNs[1]    = LZForwarder.NETHERMIND_DVN_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        // NOTE: To pass initial check, we set the peer.
        vm.prank(makeAddr("owner"));
        LZReceiver(destinationReceiver).setPeer(sourceEndpointId, bytes32(uint256(uint160(randomAddress))));

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert("LZReceiver/invalid-sourceAuthority");
        LZReceiver(destinationReceiver).lzReceive(
            Origin({
                srcEid: sourceEndpointId,
                sender: bytes32(uint256(uint160(randomAddress))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(MessageOrdering.push, (1)),
            address(0),
            ""
        );
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
            payInLzToken : false
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
            false
        );
    }

    function test_initBaseContracts_forwarderIsUsedToCorrectlyConfigureSender_source() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationExecutor   = LZForwarder.EXECUTOR_BASE;
        destinationDVNs[0]    = LZForwarder.LAYER_ZERO_DVN_BASE;
        destinationDVNs[1]    = LZForwarder.NETHERMIND_DVN_BASE;

        initBaseContracts(getChain("base").createFork());

        source.selectFork();

        // ULN configType = 2, Executor configType = 1
        address sendLib = ILayerZeroEndpointV2(sourceEndpoint).getSendLibrary(sourceAuthority, destinationEndpointId);

        // ULN Config
        bytes memory ulnConfigBytes = ILayerZeroEndpointV2(sourceEndpoint).getConfig(
            sourceAuthority, sendLib, destinationEndpointId, 2
        );
        UlnConfig memory ulnConfig = abi.decode(ulnConfigBytes, (UlnConfig));
        assertEq(ulnConfig.confirmations,        15,            "uln confirmations should be 15");
        assertEq(ulnConfig.requiredDVNCount,     2,             "uln requiredDVNCount should be 2");
        assertEq(ulnConfig.optionalDVNCount,     0,             "uln optionalDVNCount should be 0");
        assertEq(ulnConfig.optionalDVNThreshold, 0,             "uln optionalDVNThreshold should be 0");
        assertEq(ulnConfig.requiredDVNs.length,  2,             "uln requiredDVNs length should be 2");
        assertEq(ulnConfig.requiredDVNs[0],      sourceDVNs[0], "uln requiredDVNs[0]");
        assertEq(ulnConfig.requiredDVNs[1],      sourceDVNs[1], "uln requiredDVNs[1]");
        assertEq(ulnConfig.optionalDVNs.length,  0,             "uln optionalDVNs length should be 0");

        // Executor Config
        bytes memory execConfigBytes = ILayerZeroEndpointV2(sourceEndpoint).getConfig(
            sourceAuthority, sendLib, destinationEndpointId, 1
        );
        // struct ExecutorConfig { uint64 maxMessageSize; address executor; }
        (uint64 maxMessageSize, address executorAddress) = abi.decode(execConfigBytes, (uint64, address));
        assertEq(maxMessageSize,  10_000,         "executor maxMessageSize");
        assertEq(executorAddress, sourceExecutor, "executor address matches config");
    }

    function test_initBaseContracts_forwarderIsUsedToCorrectlyConfigureSender_destination() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationExecutor   = LZForwarder.EXECUTOR_BASE;
        destinationDVNs[0]    = LZForwarder.LAYER_ZERO_DVN_BASE;
        destinationDVNs[1]    = LZForwarder.NETHERMIND_DVN_BASE;

        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        // ULN configType = 2, Executor configType = 1
        address sendLib = ILayerZeroEndpointV2(destinationEndpoint).getSendLibrary(destinationAuthority, sourceEndpointId);

        // ULN Config
        bytes memory ulnConfigBytes = ILayerZeroEndpointV2(destinationEndpoint).getConfig(
            destinationAuthority, sendLib, sourceEndpointId, 2
        );
        UlnConfig memory ulnConfig = abi.decode(ulnConfigBytes, (UlnConfig));
        assertEq(ulnConfig.confirmations,        15,                 "uln confirmations should be 15");
        assertEq(ulnConfig.requiredDVNCount,     2,                  "uln requiredDVNCount should be 2");
        assertEq(ulnConfig.optionalDVNCount,     0,                  "uln optionalDVNCount should be 0");
        assertEq(ulnConfig.optionalDVNThreshold, 0,                  "uln optionalDVNThreshold should be 0");
        assertEq(ulnConfig.requiredDVNs.length,  2,                  "uln requiredDVNs length should be 2");
        assertEq(ulnConfig.requiredDVNs[0],      destinationDVNs[0], "uln requiredDVNs[0]");
        assertEq(ulnConfig.requiredDVNs[1],      destinationDVNs[1], "uln requiredDVNs[1]");
        assertEq(ulnConfig.optionalDVNs.length,  0,                  "uln optionalDVNs length should be 0");

        // Executor Config
        bytes memory execConfigBytes = ILayerZeroEndpointV2(destinationEndpoint).getConfig(
            destinationAuthority, sendLib, sourceEndpointId, 1
        );
        (uint64 maxMessageSize, address executorAddress) = abi.decode(execConfigBytes, (uint64, address));
        assertEq(maxMessageSize,  10_000,              "executor maxMessageSize");
        assertEq(executorAddress, destinationExecutor, "executor address matches config");
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

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        // Calculate fee
        MessagingParams memory params = MessagingParams({
            dstEid       : destinationEndpointId,
            receiver     : bytes32(uint256(uint160(destinationReceiver))),
            message      : message,
            options      : options,
            payInLzToken : false
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
            false
        );
    }

    function queueDestinationToSource(bytes memory message) internal override {
        destination.selectFork();

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
