// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { stdJson } from "../../../lib/forge-std/src/StdJson.sol";
import { VmSafe }  from "../../../lib/forge-std/src/Vm.sol";

import { IBeacon }                        from "../../../lib/diamond-pau/src/interfaces/IBeacon.sol";
import { IEnumerableIntegrations as IEI } from "../../../lib/diamond-pau/src/interfaces/IEnumerableIntegrations.sol";

import { ICCTPFacet } from "../../../lib/diamond-pau/src/facets/cctp/ICCTPFacet.sol";

import { BeaconConfig } from "../../../src/BeaconConfig.sol";

import { PostDeployTestBaseParallel } from "../PostDeployTestBaseParallel.t.sol";

abstract contract BasePostDeployTestsBase is PostDeployTestBaseParallel {

     // ControllerSharedStorage.SHARED_CONTROLLER_STORAGE_LOCATION, where `accessControls` is the
    // first field. Used by _hasSelector.
    bytes32 internal constant SHARED_CONTROLLER_STORAGE_LOCATION =
        0x77adf60bdbfedf206f8b8310f3d364080b7f61dcc0e46caac13c29bb1eb5cc00;

    // CCTP_FACET configuration
    bytes32 internal constant CCTP_FACET_ID = BeaconConfig.CCTP_INTEGRATION;

    address internal cctpFacet;
    address internal usdc;
    address internal cctpTokenMessenger;

    uint256 internal baseFork;

    function setUp() public override virtual {
        super.setUp();

        baseFork = vm.createSelectFork(getChain("base").rpcUrl, _getBlock());
    }

    function _getBlock() internal virtual pure returns (uint256) {
        return 0;
    }

    // Deployed factories

    function test_pauFactoryState() external view {
        _assertPauFactoryState();
    }

    // Deployed facets

    function test_facets_constructors() external view {
        _assertFacetConstructors();
    }

    // Deployed beacon

    function test_beaconState() external {
        _assertBeaconState();

        // Exactly one integration: CCTP_FACET.
        IEI.Integration[] memory integrations = beacon.integrations();

        assertEq(integrations.length, 1);
        assertEq(integrations[0].id,  CCTP_FACET_ID);

        // Facet address and wire count match what BeaconConfig.setCCTPIntegration wrote.
        assertEq(integrations[0].config.facet,        cctpFacet);
        assertEq(integrations[0].config.wires.length, 10);

        vm.createSelectFork(getChain("mainnet").rpcUrl, 26005219); // September 18, 2026

        for (uint256 i = 0; i < integrations.length; ++i) {
            IEI.Config memory baseBeaconConfig = integrations[i].config;
            IEI.Config memory skyBeaconConfig  = skyMainnetBeacon.getConfig(integrations[i].id);

            vm.selectFork(baseFork);

            for (uint256 j; j < baseBeaconConfig.wires.length; ++j) {
                IEI.Wire memory baseWire = baseBeaconConfig.wires[j];

                assertTrue(_hasWire(skyBeaconConfig, baseWire));

                _hasSelector(cctpFacet, baseWire.callSelector);
            }
        }
    }

    function _hasWire(IEI.Config memory beaconConfig, IEI.Wire memory wire) internal pure returns (bool) {
        for (uint256 i; i < beaconConfig.wires.length; ++i) {
            if (beaconConfig.wires[i].callSelector == wire.callSelector) {
                return beaconConfig.wires[i].delegateSelector == wire.delegateSelector;
            }
        }
        return false;
    }

    function test_beaconEvents() external virtual {
        _assertBeaconEvents();
    }

    // Deployed PAU stack

    function test_administeredAgentState() external view {
        _assertAdministeredAgentState();
    }

    function test_administeredAgentEvents() external virtual {
        _assertAdministeredAgentEvents();
    }

    function test_accessControlsState() external view {
        _assertAccessControlsState();
    }

    function test_accessControlsEvents() external virtual {
        _assertAccessControlsEvents();
    }

    function test_almProxyState_unchanged() external view {
        _assertALMProxyState_unchanged();
    }

    function test_rateLimitsState() external view {
        _assertRateLimitsInitializationState();
    }

    function test_rateLimitsEvents() external virtual {
        _assertRateLimitsEvents();
    }

    function _hasSelector(address facet, bytes4 selector) internal returns (bool) {
        assertGt(facet.code.length, 0, "facet has no code");

        vm.store(facet, SHARED_CONTROLLER_STORAGE_LOCATION, bytes32(uint256(uint160(address(accessControls)))));

        // Pad so the ABI decoder does not empty-revert on missing arguments.
        bytes memory payload = abi.encodePacked(selector, new bytes(1024));

        ( bool success, bytes memory revertData ) = facet.call(payload);

        return success || revertData.length > 0;
    }

    function test_controllerState() external view {
        _assertControllerInitializationState();

        // Exactly one integration: CCTP_FACET.
        IEI.Integration[] memory integrations = controller.integrations();

        assertEq(integrations.length, 1);
        assertEq(integrations[0].id,  CCTP_FACET_ID);

        // Facet address and wire count match Controller.updateIntegrations result.
        IEI.Config memory config = controller.getConfig(CCTP_FACET_ID);

        assertEq(config.facet,        cctpFacet);
        assertEq(config.wires.length, 10);

        // Check Controller integrations matches Base Beacon

        IEI.Config memory baseBeaconConfig = beacon.getConfig(CCTP_FACET_ID);
        IEI.Config memory controllerConfig = controller.getConfig(CCTP_FACET_ID);

        assertEq(baseBeaconConfig.facet,        controllerConfig.facet);
        assertEq(baseBeaconConfig.wires.length, controllerConfig.wires.length);

        for (uint256 i; i < controllerConfig.wires.length; i++) {
            assertEq(controllerConfig.wires[i].callSelector,     baseBeaconConfig.wires[i].callSelector);
            assertEq(controllerConfig.wires[i].delegateSelector, baseBeaconConfig.wires[i].delegateSelector);
        }
    }

    function test_controllerEvents() external virtual {
        _assertControllerEvents();
    }

    /**********************************************************************************************/
    /*** Event assertions helpers                                                               ***/
    /**********************************************************************************************/

    function _assertBeaconEvents() internal {
        VmSafe.EthGetLogs[] memory logs = _getEvents(block.chainid, address(beacon), "");

        assertEq(logs.length, 4);

        // Grant deployer DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[0],
            role    : DEFAULT_ADMIN_ROLE,
            account : deployer,
            sender  : deployer
        });

        // Assert CCTP_FACET_ID integration set event
        _assertIntegrationSetEvent({
            log           : logs[1],
            integrationId : CCTP_FACET_ID
        });

        // Grant admin DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[2],
            role    : DEFAULT_ADMIN_ROLE,
            account : admin,
            sender  : deployer
        });

        // Revoke deployer DEFAULT_ADMIN_ROLE
        _assertRoleRevokedEvent({
            log     : logs[3],
            role    : DEFAULT_ADMIN_ROLE,
            account : deployer,
            sender  : deployer
        });
    }

    function _assertAccessControlsEvents() internal {
        VmSafe.EthGetLogs[] memory logs = _getEvents(block.chainid, address(accessControls), "");

        assertEq(logs.length, 4);

        // Grant deployer DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[0],
            role    : DEFAULT_ADMIN_ROLE,
            account : deployer,
            sender  : address(pauFactory)
        });

        // Grant admin DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[1],
            role    : DEFAULT_ADMIN_ROLE,
            account : admin,
            sender  : deployer
        });

        // Grant administeredAgent ALLOCATOR_ROLE
        _assertRoleGrantedEvent({
            log     : logs[2],
            role    : ALLOCATOR_ROLE,
            account : address(administeredAgent),
            sender  : deployer
        });

        // Revoke deployer DEFAULT_ADMIN_ROLE
        _assertRoleRevokedEvent({
            log     : logs[3],
            role    : DEFAULT_ADMIN_ROLE,
            account : deployer,
            sender  : deployer
        });
    }

    function _assertAdministeredAgentEvents() internal virtual {
        VmSafe.EthGetLogs[] memory logs = _getEvents(block.chainid, address(administeredAgent), "");

        assertEq(logs.length, 6);

        // Add deployer as admin
        _assertAdminAddedEvent({
            log     : logs[0],
            account : deployer,
            caller  : address(agentFactory)
        });

        // Add admin as admin
        _assertAdminAddedEvent({
            log     : logs[1],
            account : admin,
            caller  : deployer
        });

        // Add relayer as actor
        _assertActorAddedEvent({
            log     : logs[2],
            account : relayer,
            caller  : deployer
        });

        // Add grantor
        _assertGrantorAddedEvent({
            log     : logs[3],
            account : grantor,
            caller  : deployer
        });

        // Add freezer as revoker
        _assertRevokerAddedEvent({
            log     : logs[4],
            account : freezer,
            caller  : deployer
        });

        // Remove deployer as admin
        _assertAdminRemovedEvent({
            log     : logs[5],
            account : deployer,
            caller  : deployer
        });
    }

    function _assertRateLimitsEvents() internal {
        VmSafe.EthGetLogs[] memory logs = _getEvents(block.chainid, address(rateLimits), "");

        assertEq(logs.length, 4);

        // Grant deployer DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[0],
            role    : DEFAULT_ADMIN_ROLE,
            account : deployer,
            sender  : address(pauFactory)
        });

        // Grant admin DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[1],
            role    : DEFAULT_ADMIN_ROLE,
            account : admin,
            sender  : deployer
        });

        // Grant controller CONTROLLER_ROLE
        _assertRoleGrantedEvent({
            log     : logs[2],
            role    : CONTROLLER_ROLE,
            account : address(controller),
            sender  : deployer
        });

        // Revoke deployer DEFAULT_ADMIN_ROLE
        _assertRoleRevokedEvent({
            log     : logs[3],
            role    : DEFAULT_ADMIN_ROLE,
            account : deployer,
            sender  : deployer
        });
    }

    function _assertControllerEvents() internal {
        VmSafe.EthGetLogs[] memory logs = _getEvents(block.chainid, address(controller), "");

        assertEq(logs.length, 2);

        // Assert controller Initialized event
        _assertInitializedEvent({
            log: logs[0]
        });

        // Assert CCTP_FACET_ID integration set event
        _assertIntegrationSetEvent({
            log           : logs[1],
            integrationId : CCTP_FACET_ID
        });
    }

}

contract BasePostDeployTestsProduction is BasePostDeployTestsBase {

    using stdJson for string;

    function setUp() public override {
        super.setUp();

        string memory json = vm.readFile("deployments/parallel-controller/base-production.json");

        _setUpAddresses(json);

        cctpFacet          = json.readAddress(".cctpFacet");
        usdc               = json.readAddress(".usdc");
        cctpTokenMessenger = json.readAddress(".cctpTokenMessenger");
    }

    function _getBlock() internal override pure returns (uint256) {
        return 51607100;
    }

    function _assertFacetConstructors() internal view override {
        assertEq(ICCTPFacet(cctpFacet).cctp(), cctpTokenMessenger);
        assertEq(ICCTPFacet(cctpFacet).usdc(), usdc);
    }

}
