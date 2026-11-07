// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { stdJson } from "../lib/forge-std/src/StdJson.sol";
import { Test }    from "../lib/forge-std/src/Test.sol";
import { VmSafe }  from "../lib/forge-std/src/Vm.sol";

import { IAccessControl }                            from "../lib/diamond-pau/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IAccessControls }                           from "../lib/diamond-pau/src/interfaces/IAccessControls.sol";
import { IALMProxy }                                 from "../lib/diamond-pau/src/interfaces/IALMProxy.sol";
import { IPAUFactory }                               from "../lib/diamond-pau/src/interfaces/IPAUFactory.sol";
import { IBeacon }                                   from "../lib/diamond-pau/src/interfaces/IBeacon.sol";
import { ICCTPFacet }                                from "../lib/diamond-pau/src/facets/cctp/ICCTPFacet.sol";
import { Initializable }                             from "../lib/diamond-pau/lib/oz-upgradeable/contracts/proxy/utils/Initializable.sol";
import { IEnumerableIntegrations as IEI }            from "../lib/diamond-pau/src/interfaces/IEnumerableIntegrations.sol";
import { IMainnetControllerFull as IControllerFull } from "../lib/diamond-pau/test/interfaces/IMainnetControllerFull.sol";
import { IRateLimits }                               from "../lib/diamond-pau/src/interfaces/IRateLimits.sol";

import { IERC4626Facet } from "../lib/diamond-pau/src/facets/erc4626/IERC4626Facet.sol";

import { IAdministeredAgent }        from "../lib/pau-administered-agent/src/interfaces/IAdministeredAgent.sol";
import { IAdministeredAgentFactory } from "../lib/pau-administered-agent/src/interfaces/IAdministeredAgentFactory.sol";

abstract contract PostDeployTestBase is Test {

    using stdJson for string;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant ALLOCATOR_ROLE     = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant CONTROLLER_ROLE    = keccak256("CONTROLLER");

    IAdministeredAgentFactory internal agentFactory;
    IBeacon                   internal beacon;
    IPAUFactory               internal pauFactory;

    IAccessControls    internal accessControls;
    IAdministeredAgent internal administeredAgent;
    IALMProxy          internal almProxy;
    IControllerFull    internal controller;
    IRateLimits        internal rateLimits;

    address internal admin;
    address internal deployer;
    address internal relayer;
    address internal freezer;
    address internal grantor;

    function setUp() public virtual {
        _setUpXLayerAndRobinhoodForks();
    }

    function _setUpAddresses(string memory json) internal virtual {
        agentFactory = IAdministeredAgentFactory(json.readAddress(".agentFactory"));
        beacon       = IBeacon(json.readAddress(".beacon"));
        pauFactory   = IPAUFactory(json.readAddress(".pauFactory"));

        accessControls    = IAccessControls(json.readAddress(".accessControls"));
        administeredAgent = IAdministeredAgent(json.readAddress(".administeredAgent"));
        almProxy          = IALMProxy(json.readAddress(".proxy"));
        controller        = IControllerFull(json.readAddress(".controller"));
        rateLimits        = IRateLimits(json.readAddress(".rateLimits"));

        admin    = json.readAddress(".admin");
        deployer = json.readAddress(".deployer");
        relayer  = json.readAddress(".relayer");
        freezer  = json.readAddress(".freezer");
        grantor  = json.readAddress(".grantor");
    }

    function _setUpXLayerAndRobinhoodForks() internal {
        setChain("xlayer", ChainData({
            name    : "XLayer",
            rpcUrl  : "https://rpc.xlayer.tech",
            chainId : 196
        }));

        setChain("robinhood_chain", ChainData({
            name    : "Robinhood Chain",
            rpcUrl  : vm.envOr("RH_RPC_URL", string("")),
            chainId : 4663
        }));
    }

    /**********************************************************************************************/
    /*** State Assertions                                                                       ***/
    /**********************************************************************************************/

    function _assertControllerInitializationState() internal view {
        assertEq(controller.accessControls(), address(accessControls));
        assertEq(controller.beacon(),         address(beacon));
        assertEq(controller.proxy(),          address(almProxy));
        assertEq(controller.rateLimits(),     address(rateLimits));
    }

    /**********************************************************************************************/
    /*** Get events helpers                                                                     ***/
    /**********************************************************************************************/

    function _getEvents(uint256 chainId, address target, bytes32 topic0)
        internal
        returns (VmSafe.EthGetLogs[] memory logs)
    {
        return _getEvents(chainId, target, topic0, 0);
    }

    function _getEvents(uint256 chainId, address target, bytes32 topic0, uint256 retryCount)
        internal
        returns (VmSafe.EthGetLogs[] memory logs)
    {
        string memory apiKey = vm.envString("ETHERSCAN_API_KEY");

        require(retryCount < 4, "Etherscan API returned non-success status");

        string memory url = string(
            abi.encodePacked(
                "https://api.etherscan.io/v2/api?",
                "chainid=",
                vm.toString(chainId),
                "&module=logs&action=getLogs",
                "&fromBlock=0",
                "&toBlock=latest",
                "&address=",
                vm.toString(target),
                "&page=1",
                "&offset=1000",
                "&apikey=",
                apiKey
            )
        );

        if (topic0 != 0) {
            url = string(abi.encodePacked(url, "&topic0=", vm.toString(topic0)));
        }

        string[] memory inputs = new string[](8);
        inputs[0] = "curl";
        inputs[1] = "-s";
        inputs[2] = "--request";
        inputs[3] = "GET";
        inputs[4] = "--url";
        inputs[5] = url;
        inputs[6] = "--header";
        inputs[7] = "accept: application/json";

        string memory response;

        for (uint256 attempt; attempt < 10; attempt++) {
            response = string(vm.ffi(inputs));

            if (_isEqual(vm.parseJsonString(response, string(abi.encodePacked(".message"))), "NOTOK")) {
                vm.sleep(1000);  // Prevent rate limiting from Etherscan (5 calls/second)
                continue;
            }

            break;
        }

        uint256 i = 0;
        for(; i < 1000; i++) {
            try vm.parseJsonAddress(response, string(abi.encodePacked(".result[", vm.toString(i), "].address"))) {
            } catch {
                logs = new VmSafe.EthGetLogs[](i);
                break;
            }
        }

        for(uint256 j; j < i; ++j) {
            logs[j] = VmSafe.EthGetLogs({
                emitter:          vm.parseJsonAddress(response,      string(abi.encodePacked(".result[", vm.toString(j), "].address"))),
                topics:           vm.parseJsonBytes32Array(response, string(abi.encodePacked(".result[", vm.toString(j), "].topics"))),
                data:             vm.parseJsonBytes(response,        string(abi.encodePacked(".result[", vm.toString(j), "].data"))),
                blockNumber:      uint64(0),
                blockHash:        bytes32(0),
                transactionHash:  bytes32(0),
                transactionIndex: uint64(0),
                logIndex:         uint8(0),
                removed:          false
            });
        }
    }

    function _isEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _toAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }

    function _toBool(bytes32 b) internal pure returns (bool) {
        require(uint256(b) <= 1, "PostDeployTestBase/to-bool-failed");

        return uint256(b) == uint256(1);
    }

    /**********************************************************************************************/
    /*** State test helpers                                                                     ***/
    /**********************************************************************************************/

    function _assertIntegration(bytes32 integrationId) internal view {
        IEI.Config memory beaconConfig     = beacon.getConfig(integrationId);
        IEI.Config memory controllerConfig = controller.getConfig(integrationId);

        assertEq(controllerConfig.facet,        beaconConfig.facet);
        assertEq(controllerConfig.wires.length, beaconConfig.wires.length);

        for (uint256 i = 0; i < controllerConfig.wires.length; ++i) {
            assertEq(controllerConfig.wires[i].callSelector,     beaconConfig.wires[i].callSelector);
            assertEq(controllerConfig.wires[i].delegateSelector, beaconConfig.wires[i].delegateSelector);
        }
    }

    function _assertRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) internal view {
        IRateLimits.RateLimitData memory data = rateLimits.getRateLimitData(key);

        assertEq(data.maxAmount, maxAmount);
        assertEq(data.slope,     slope);
    }

    /**********************************************************************************************/
    /*** Event test helpers                                                                     ***/
    /**********************************************************************************************/

    function _assertInitializedEvent(VmSafe.EthGetLogs memory log) internal pure {
        assertEq(log.topics[0], Initializable.Initialized.selector);
        assertEq(log.data,      abi.encode(1));
    }

    function _assertIntegrationSetEvent(VmSafe.EthGetLogs memory log, bytes32 integrationId) internal view {
        IEI.Config memory controllerConfig = abi.decode(log.data, (IEI.Config));
        IEI.Config memory beaconConfig     = beacon.getConfig(integrationId);

        assertEq(log.topics[0], IEI.IntegrationSet.selector);
        assertEq(log.topics[1], integrationId);

        assertEq(controllerConfig.facet,        beaconConfig.facet);
        assertEq(controllerConfig.wires.length, beaconConfig.wires.length);

        for (uint256 i = 0; i < controllerConfig.wires.length; ++i) {
            assertEq(controllerConfig.wires[i].callSelector,     beaconConfig.wires[i].callSelector);
            assertEq(controllerConfig.wires[i].delegateSelector, beaconConfig.wires[i].delegateSelector);
        }
    }

    function _assertRateLimitDataSetEvent(
        VmSafe.EthGetLogs memory log,
        bytes32                  key,
        uint256                  maxAmount,
        uint256                  slope
    ) internal pure {
        (
            uint256 loggedMaxAmount,
            uint256 loggedSlope,
            uint256 loggedLastAmount,
        ) = abi.decode(log.data, (uint256, uint256, uint256, uint256));

        assertEq(log.topics[0], IRateLimits.RateLimitDataSet.selector);
        assertEq(log.topics[1], key);

        assertEq(loggedMaxAmount,  maxAmount);
        assertEq(loggedSlope,      slope);
        assertEq(loggedLastAmount, maxAmount);
    }

    function _assertRoleGrantedEvent(
        VmSafe.EthGetLogs memory log,
        bytes32                  role,
        address                  account,
        address                  sender
    ) internal pure {
        assertEq(log.topics[0],             IAccessControl.RoleGranted.selector);
        assertEq(log.topics[1],             role);
        assertEq(_toAddress(log.topics[2]), account);
        assertEq(_toAddress(log.topics[3]), sender);
    }

    function _assertRoleRevokedEvent(
        VmSafe.EthGetLogs memory log,
        bytes32                  role,
        address                  account,
        address                  sender
    ) internal pure {
        assertEq(log.topics[0],             IAccessControl.RoleRevoked.selector);
        assertEq(log.topics[1],             role);
        assertEq(_toAddress(log.topics[2]), account);
        assertEq(_toAddress(log.topics[3]), sender);
    }

    function _assertAdminAddedEvent(
        VmSafe.EthGetLogs memory log,
        address                  account,
        address                  caller
    ) internal pure {
        assertEq(log.topics[0],             IAdministeredAgent.AdminAdded.selector);
        assertEq(_toAddress(log.topics[1]), account);
        assertEq(_toAddress(log.topics[2]), caller);
    }

    function _assertAdminRemovedEvent(
        VmSafe.EthGetLogs memory log,
        address                  account,
        address                  caller
    ) internal pure {
        assertEq(log.topics[0],             IAdministeredAgent.AdminRemoved.selector);
        assertEq(_toAddress(log.topics[1]), account);
        assertEq(_toAddress(log.topics[2]), caller);
    }

    function _assertActorAddedEvent(
        VmSafe.EthGetLogs memory log,
        address                  account,
        address                  caller
    ) internal pure {
        assertEq(log.topics[0],             IAdministeredAgent.ActorAdded.selector);
        assertEq(_toAddress(log.topics[1]), account);
        assertEq(_toAddress(log.topics[2]), caller);
    }

    function _assertActorRemovedEvent(
        VmSafe.EthGetLogs memory log,
        address                  account,
        address                  caller
    ) internal pure {
        assertEq(log.topics[0],             IAdministeredAgent.ActorRemoved.selector);
        assertEq(_toAddress(log.topics[1]), account);
        assertEq(_toAddress(log.topics[2]), caller);
    }

    function _assertGrantorAddedEvent(
        VmSafe.EthGetLogs memory log,
        address                  account,
        address                  caller
    ) internal pure {
        assertEq(log.topics[0],             IAdministeredAgent.GrantorAdded.selector);
        assertEq(_toAddress(log.topics[1]), account);
        assertEq(_toAddress(log.topics[2]), caller);
    }

    function _assertGrantorRemovedEvent(
        VmSafe.EthGetLogs memory log,
        address                  account,
        address                  caller
    ) internal pure {
        assertEq(log.topics[0],             IAdministeredAgent.GrantorRemoved.selector);
        assertEq(_toAddress(log.topics[1]), account);
        assertEq(_toAddress(log.topics[2]), caller);
    }

    function _assertRevokerAddedEvent(
        VmSafe.EthGetLogs memory log,
        address                  account,
        address                  caller
    ) internal pure {
        assertEq(log.topics[0],             IAdministeredAgent.RevokerAdded.selector);
        assertEq(_toAddress(log.topics[1]), account);
        assertEq(_toAddress(log.topics[2]), caller);
    }

    function _assertRevokerRemovedEvent(
        VmSafe.EthGetLogs memory log,
        address                  account,
        address                  caller
    ) internal pure {
        assertEq(log.topics[0],             IAdministeredAgent.RevokerRemoved.selector);
        assertEq(_toAddress(log.topics[1]), account);
        assertEq(_toAddress(log.topics[2]), caller);
    }

}
