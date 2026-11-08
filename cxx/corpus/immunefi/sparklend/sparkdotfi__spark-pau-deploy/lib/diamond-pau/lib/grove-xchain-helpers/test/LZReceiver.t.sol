// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import { TargetContractMock } from "test/mocks/TargetContractMock.sol";

import { LZForwarder }        from "src/forwarders/LZForwarder.sol";
import { LZReceiver, Origin } from "src/receivers/LZReceiver.sol";

import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig }      from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

interface ILayerZeroEndpointV2 {
    function delegates(address sender) external view returns (address);
    function getReceiveLibrary(address _receiver, uint32 _srcEid) external view returns (address lib, bool isDefault);
    function getConfig(address _oapp, address _lib, uint32 _eid, uint32 _configType) external view returns (bytes memory config);
}

contract LZReceiverTest is Test {

    TargetContractMock target;

    LZReceiver receiver;

    address destinationEndpoint = LZForwarder.ENDPOINT_BNB;
    address randomAddress       = makeAddr("randomAddress");
    address sourceAuthority     = makeAddr("sourceAuthority");
    address delegate            = makeAddr("delegate");
    address owner               = makeAddr("owner");
    address firstDVN            = LZForwarder.NETHERMIND_DVN_BNB;
    address secondDVN           = LZForwarder.LAYER_ZERO_DVN_BNB;
    address[] requiredDVNs      = [firstDVN, secondDVN];

    uint32 srcEid = LZForwarder.ENDPOINT_ID_ETHEREUM;

    error NoPeer(uint32 eid);
    error OnlyEndpoint(address addr);
    error OnlyPeer(uint32 eid, bytes32 sender);

    function setUp() public {
        vm.createSelectFork(getChain("bnb_smart_chain").rpcUrl);

        target = new TargetContractMock();

        LZReceiver.UlConfigParams memory ulnConfigParams
            = LZReceiver.UlConfigParams({
                confirmations        : 15,
                requiredDVNs         : requiredDVNs,
                optionalDVNs         : new address[](0),
                optionalDVNThreshold : 0
            });

        receiver = new LZReceiver(
            destinationEndpoint,
            srcEid,
            bytes32(uint256(uint160(sourceAuthority))),
            address(target),
            delegate,
            owner,
            ulnConfigParams
        );
    }

    function test_constructor() public view {
        assertEq(receiver.srcEid(),          srcEid);
        assertEq(receiver.sourceAuthority(), bytes32(uint256(uint160(sourceAuthority))));
        assertEq(receiver.target(),          address(target));
        assertEq(receiver.owner(),           owner);
        assertEq(receiver.peers(srcEid),     bytes32(uint256(uint160(sourceAuthority))));

        assertEq(
            ILayerZeroEndpointV2(address(receiver.endpoint())).delegates(address(receiver)),
            delegate
        );
    }

    function test_constructor_setsConfig() public view {
        // Get the receive library to query the config
        (address receiveLib, ) = ILayerZeroEndpointV2(destinationEndpoint).getReceiveLibrary(
            address(receiver),
            srcEid
        );

        // Get the UlnConfig that was set via endpoint
        bytes memory configBytes = ILayerZeroEndpointV2(destinationEndpoint).getConfig(
            address(receiver),
            receiveLib,
            srcEid,
            2  // configType 2 is for UlnConfig
        );
        UlnConfig memory config = abi.decode(configBytes, (UlnConfig));

        // Verify the config was set correctly
        assertEq(config.confirmations,        15,        "confirmations should be 15");
        assertEq(config.requiredDVNCount,     2,         "requiredDVNCount should be 2");
        assertEq(config.optionalDVNCount,     0,         "optionalDVNCount should be 0");
        assertEq(config.optionalDVNThreshold, 0,         "optionalDVNThreshold should be 0");
        assertEq(config.requiredDVNs.length,  2,         "requiredDVNs length should be 2");
        assertEq(config.requiredDVNs[0],      firstDVN,  "first DVN should be Nethermind");
        assertEq(config.requiredDVNs[1],      secondDVN, "second DVN should be LayerZero");
        assertEq(config.optionalDVNs.length,  0,         "optionalDVNs length should be 0");
    }

    function test_constructor_setsConfig_withSingleDVN() public {
        address[] memory singleDVN = new address[](1);
        singleDVN[0] = LZForwarder.NETHERMIND_DVN_BNB;

        LZReceiver.UlConfigParams memory ulnConfigParams
            = LZReceiver.UlConfigParams({
                confirmations        : 15,
                requiredDVNs         : singleDVN,
                optionalDVNs         : new address[](0),
                optionalDVNThreshold : 0
            });

        LZReceiver receiverWithSingleDVN = new LZReceiver(
            destinationEndpoint,
            srcEid,
            bytes32(uint256(uint160(sourceAuthority))),
            address(target),
            delegate,
            owner,
            ulnConfigParams
        );

        (address receiveLib, ) = ILayerZeroEndpointV2(destinationEndpoint).getReceiveLibrary(
            address(receiverWithSingleDVN),
            srcEid
        );

        bytes memory configBytes = ILayerZeroEndpointV2(destinationEndpoint).getConfig(
            address(receiverWithSingleDVN),
            receiveLib,
            srcEid,
            2  // configType 2 is for UlnConfig
        );
        UlnConfig memory config = abi.decode(configBytes, (UlnConfig));

        assertEq(config.requiredDVNCount,    1,        "requiredDVNCount should be 1");
        assertEq(config.requiredDVNs.length, 1,        "requiredDVNs length should be 1");
        assertEq(config.requiredDVNs[0],     firstDVN, "DVN should be Nethermind");
    }

    function test_constructor_setsConfig_withMultipleDVNs() public {
        // DVNs must be sorted in ascending order for LayerZero
        address thirdDVN = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

        address[] memory multipleDVNs = new address[](3);
        multipleDVNs[0] = LZForwarder.NETHERMIND_DVN_BNB;
        multipleDVNs[1] = LZForwarder.LAYER_ZERO_DVN_BNB;
        multipleDVNs[2] = thirdDVN;  // Using a high address to ensure proper sorting

        LZReceiver.UlConfigParams memory ulnConfigParams
            = LZReceiver.UlConfigParams({
                confirmations        : 15,
                requiredDVNs         : multipleDVNs,
                optionalDVNs         : new address[](0),
                optionalDVNThreshold : 0
            });

        LZReceiver receiverWithMultipleDVNs = new LZReceiver(
            destinationEndpoint,
            srcEid,
            bytes32(uint256(uint160(sourceAuthority))),
            address(target),
            delegate,
            owner,
            ulnConfigParams
        );

        (address receiveLib, ) = ILayerZeroEndpointV2(destinationEndpoint).getReceiveLibrary(
            address(receiverWithMultipleDVNs),
            srcEid
        );

        bytes memory configBytes = ILayerZeroEndpointV2(destinationEndpoint).getConfig(
            address(receiverWithMultipleDVNs),
            receiveLib,
            srcEid,
            2  // configType 2 is for UlnConfig
        );
        UlnConfig memory config = abi.decode(configBytes, (UlnConfig));

        assertEq(config.requiredDVNCount,    3,         "requiredDVNCount should be 3");
        assertEq(config.requiredDVNs.length, 3,         "requiredDVNs length should be 3");
        assertEq(config.requiredDVNs[0],     firstDVN,  "first DVN should be Nethermind");
        assertEq(config.requiredDVNs[1],     secondDVN, "second DVN should be LayerZero");
        assertEq(config.requiredDVNs[2],     thirdDVN,  "third DVN should be thirdDVN");
    }

    function test_invalidEndpoint() public {
        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(OnlyEndpoint.selector, randomAddress));
        receiver.lzReceive(
            Origin({
                srcEid: srcEid,
                sender: bytes32(uint256(uint160(randomAddress))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );
    }

    function test_lzReceive_revertsNoPeer() public {
        vm.prank(destinationEndpoint);
        vm.expectRevert(abi.encodeWithSelector(NoPeer.selector, 0));
        receiver.lzReceive(
            Origin({
                srcEid: 0,
                sender: bytes32(uint256(uint160(randomAddress))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );
    }

    function test_lzReceive_revertsOnlyPeer() public {
        vm.prank(destinationEndpoint);
        vm.expectRevert(abi.encodeWithSelector(OnlyPeer.selector, srcEid, bytes32(uint256(uint160(randomAddress)))));
        receiver.lzReceive(
            Origin({
                srcEid: srcEid,
                sender: bytes32(uint256(uint160(randomAddress))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );
    }

    function test_lzReceive_invalidSrcEid() public {
        // NOTE: To pass initial check, we set the peer.
        vm.prank(owner);
        receiver.setPeer(srcEid + 1, bytes32(uint256(uint160(sourceAuthority))));

        vm.prank(destinationEndpoint);
        vm.expectRevert("LZReceiver/invalid-srcEid");
        receiver.lzReceive(
            Origin({
                srcEid: srcEid + 1,
                sender: bytes32(uint256(uint160(sourceAuthority))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );
    }

    function test_lzReceive_invalidSourceAuthority() public {
        // NOTE: To pass initial check, we set the peer.
        vm.prank(owner);
        receiver.setPeer(srcEid, bytes32(uint256(uint160(randomAddress))));

        vm.prank(destinationEndpoint);
        vm.expectRevert("LZReceiver/invalid-sourceAuthority");
        receiver.lzReceive(
            Origin({
                srcEid: srcEid,
                sender: bytes32(uint256(uint160(randomAddress))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );
    }

    function test_lzReceive_success() public {
        assertEq(target.count(), 0);
        vm.prank(destinationEndpoint);
        receiver.lzReceive(
            Origin({
                srcEid: srcEid,
                sender: bytes32(uint256(uint160(sourceAuthority))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(TargetContractMock.increment, ()),
            address(0),
            ""
        );
        assertEq(target.count(), 1);
    }

    function test_allowInitializePath() public {
        // Should return true when origin.srcEid == srcEid, origin.sender == sourceAuthority and peers[origin.srcEid] == origin.sender
        assertTrue(receiver.allowInitializePath(Origin({
            srcEid: srcEid,
            sender: bytes32(uint256(uint160(sourceAuthority))),
            nonce:  1
        })));

        // Should return false when peers[origin.srcEid] != origin.sender

        assertFalse(receiver.allowInitializePath(Origin({
            srcEid: srcEid,
            sender: bytes32(uint256(uint160(randomAddress))),
            nonce:  1
        })));

        // Should return false when origin.srcEid != srcEid

        // NOTE: Setting peer to make `super.allowInitializePath(origin)` return true
        vm.prank(owner);
        receiver.setPeer(srcEid + 1, bytes32(uint256(uint160(sourceAuthority))));

        assertFalse(receiver.allowInitializePath(Origin({
            srcEid: srcEid + 1,
            sender: bytes32(uint256(uint160(sourceAuthority))),
            nonce:  1
        })));

        // Should return false when origin.sender != sourceAuthority

        // NOTE: Setting peer to make `super.allowInitializePath(origin)` return true
        vm.prank(owner);
        receiver.setPeer(srcEid, bytes32(uint256(uint160(randomAddress))));

        assertFalse(receiver.allowInitializePath(Origin({
            srcEid: srcEid,
            sender: bytes32(uint256(uint160(randomAddress))),
            nonce:  1
        })));
    }

}
