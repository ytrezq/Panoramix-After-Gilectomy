// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./IntegrationBase.t.sol";

import { CCTPv2BridgeTesting } from "src/testing/bridges/CCTPv2BridgeTesting.sol";
import { CCTPv2Forwarder }     from "src/forwarders/CCTPv2Forwarder.sol";
import { CCTPv2Receiver }      from "src/receivers/CCTPv2Receiver.sol";

import { RecordedLogs } from "src/testing/utils/RecordedLogs.sol";

contract DummyReceiver {

    bytes public message;

    function handleReceiveFinalizedMessage(
        uint32  /*remoteDomain*/,
        bytes32 /*sender*/,
        uint32  /*finalityThresholdExecuted*/,
        bytes   memory messageBody
    ) external returns (bool) {
        message = messageBody;
        return true;
    }

}

contract CircleCCTPv2IntegrationTest is IntegrationBaseTest {

    using CCTPv2BridgeTesting for *;
    using DomainHelpers       for *;

    uint32 sourceDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM;
    uint32 destinationDomainId;

    Domain destination2;
    Bridge bridge2;

    function _addressToCctpBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    // Use Optimism for failure tests as the code logic is the same

    function test_invalidSender() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_OPTIMISM;
        initBaseContracts(getChain("optimism").createFork());

        destination.selectFork();

        vm.prank(randomAddress);
        vm.expectRevert("CCTPv2Receiver/invalid-sender");
        CCTPv2Receiver(destinationReceiver).handleReceiveFinalizedMessage(
            sourceDomainId,
            _addressToCctpBytes32(sourceAuthority),
            0,
            abi.encodeCall(MessageOrdering.push, (1))
        );
    }

    function test_invalidSourceDomain() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_OPTIMISM;
        initBaseContracts(getChain("optimism").createFork());

        destination.selectFork();

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert("CCTPv2Receiver/invalid-sourceDomain");
        CCTPv2Receiver(destinationReceiver).handleReceiveFinalizedMessage(
            1,
            _addressToCctpBytes32(sourceAuthority),
            0,
            abi.encodeCall(MessageOrdering.push, (1))
        );
    }

    function test_invalidSourceAuthority() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_OPTIMISM;
        initBaseContracts(getChain("optimism").createFork());

        destination.selectFork();

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert("CCTPv2Receiver/invalid-sourceAuthority");
        CCTPv2Receiver(destinationReceiver).handleReceiveFinalizedMessage(
            0,
            _addressToCctpBytes32(randomAddress),
            0,
            abi.encodeCall(MessageOrdering.push, (1))
        );
    }

    function test_avalanche() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_AVALANCHE;
        runCrossChainTests(getChain("avalanche").createFork());
    }

    function test_optimism() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_OPTIMISM;
        runCrossChainTests(getChain("optimism").createFork());
    }

    function test_arbitrum_one() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE;
        runCrossChainTests(getChain("arbitrum_one").createFork());
    }

    function test_base() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE;
        runCrossChainTests(getChain("base").createFork());
    }

    function test_polygon() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_POLYGON_POS;
        runCrossChainTests(getChain("polygon").createFork());
    }

    function test_unichain() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_UNICHAIN;
        runCrossChainTests(getChain("unichain").createFork());
    }

    function test_world_chain() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_WORLDCHAIN;
        runCrossChainTests(getChain("world_chain").createFork());
    }

    function test_monad() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_MONAD;
        runCrossChainTests(getChain("monad").createFork());
    }

    function test_bnb_smart_chain() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BSC;
        runCrossChainTests(getChain("bnb_smart_chain").createFork());
    }

    function test_plume() public {
        destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_PLUME;
        runCrossChainTests(getChain("plume").createFork());
    }

    // These tests use chains not supported by std.chains. Add proper chain configuration and proper tests when needed.

    // function test_linea() public {
    //     destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_LINEA;
    //     runCrossChainTests(getChain("linea").createFork());
    // }

    // function test_codex() public {
    //     destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_CODEX;
    //     runCrossChainTests(getChain("codex").createFork());
    // }

    // function test_sonic() public {
    //     destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_SONIC;
    //     runCrossChainTests(getChain("sonic").createFork());
    // }

    // function test_sei() public {
    //     destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_SEI;
    //     runCrossChainTests(getChain("sei").createFork());
    // }

    // function test_xdc() public {
    //     destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_XDC;
    //     runCrossChainTests(getChain("xdc").createFork());
    // }

    // function test_hyper() public {
    //     destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_HYPEREVM;
    //     runCrossChainTests(getChain("hyper").createFork());
    // }

    // function test_ink() public {
    //     destinationDomainId = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_INK;
    //     runCrossChainTests(getChain("ink").createFork());
    // }

    function test_multiple() public {
        destination  = getChain("base").createFork();
        destination2 = getChain("arbitrum_one").createFork();

        DummyReceiver r0 = new DummyReceiver();
        assertEq(r0.message().length, 0);

        destination.selectFork();
        DummyReceiver r1 = new DummyReceiver();
        assertEq(r1.message().length, 0);

        destination2.selectFork();
        DummyReceiver r2 = new DummyReceiver();
        assertEq(r2.message().length, 0);

        bridge  = CCTPv2BridgeTesting.createCircleBridge(source, destination);
        bridge2 = CCTPv2BridgeTesting.createCircleBridge(source, destination2);

        source.selectFork();

        CCTPv2Forwarder.sendMessage(CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ETHEREUM, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_BASE, address(r1), abi.encode(1));
        CCTPv2Forwarder.sendMessage(CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ETHEREUM, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE, address(r2), abi.encode(2));

        bridge.relayMessagesToDestination(true);
        bridge2.relayMessagesToDestination(true);

        destination.selectFork();
        assertEq(r1.message(), abi.encode(1));

        destination2.selectFork();
        assertEq(r2.message(), abi.encode(2));

        destination.selectFork();
        CCTPv2Forwarder.sendMessage(CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_BASE, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM, address(r0), abi.encode(3));

        destination2.selectFork();
        CCTPv2Forwarder.sendMessage(CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ARBITRUM_ONE, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM, address(r0), abi.encode(4));
        CCTPv2Forwarder.sendMessage(CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ARBITRUM_ONE, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM, address(r0), abi.encode(5));

        assertEq(r0.message(), bytes(""));

        bridge.relayMessagesToDestination(true);
        bridge2.relayMessagesToDestination(true);

        assertEq(r0.message(), bytes(""));

        bridge2.relayMessagesToSource(true);

        assertEq(r0.message(), abi.encode(5));

        bridge.relayMessagesToSource(true);

        assertEq(r0.message(), abi.encode(3));
    }

    function initSourceReceiver() internal override returns (address) {
        return address(new CCTPv2Receiver(bridge.sourceCrossChainMessenger, destinationDomainId, _addressToCctpBytes32(destinationAuthority), address(moSource)));
    }

    function initDestinationReceiver() internal override returns (address) {
        return address(new CCTPv2Receiver(bridge.destinationCrossChainMessenger, sourceDomainId, _addressToCctpBytes32(sourceAuthority), address(moDestination)));
    }

    function initBridgeTesting() internal override returns (Bridge memory) {
        return CCTPv2BridgeTesting.createCircleBridge(source, destination);
    }

    function queueSourceToDestination(bytes memory message) internal override {
        CCTPv2Forwarder.sendMessage(
            bridge.sourceCrossChainMessenger,
            destinationDomainId,
            destinationReceiver,
            message
        );
    }

    function queueDestinationToSource(bytes memory message) internal override {
        CCTPv2Forwarder.sendMessage(
            bridge.destinationCrossChainMessenger,
            sourceDomainId,
            sourceReceiver,
            message
        );
    }

    function relaySourceToDestination() internal override {
        bridge.relayMessagesToDestination(true);
    }

    function relayDestinationToSource() internal override {
        bridge.relayMessagesToSource(true);
    }

}
