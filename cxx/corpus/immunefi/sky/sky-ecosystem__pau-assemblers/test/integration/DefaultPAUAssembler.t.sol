// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test, console } from "../../lib/forge-std/src/Test.sol";

import { IDefaultPAUAssembler } from "../../src/interfaces/IDefaultPAUAssembler.sol";

import { DefaultPAUAssembler } from "../../src/DefaultPAUAssembler.sol";

interface IAdministeredAgentLike {

    function actorCount() external view returns (uint256);

    function adminCount() external view returns (uint256);

    function getIsActor(address account) external view returns (bool);

    function getIsAdmin(address account) external view returns (bool);

    function getIsGrantor(address account) external view returns (bool);

    function getIsRevoker(address account) external view returns (bool);

    function grantorCount() external view returns (uint256);

    function revokerCount() external view returns (uint256);

}

interface IAccessControlLike {

    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    function hasRole(bytes32 role, address account) external view returns (bool);

}

interface IALMProxyLike {

    function CONTROLLER() external view returns (bytes32);

}

interface IControllerLike {

    struct Config {
        address facet;
        Wire[]  wires;
    }

    struct Integration {
        bytes32 id;
        Config  config;
    }

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    function accessControls() external view returns (address);

    function beacon() external view returns (address);

    function integrations() external view returns (Integration[] memory);

    function proxy() external view returns (address);

    function rateLimits() external view returns (address);

}

interface IRateLimitsLike {

    function CONTROLLER() external view returns (bytes32);

}

interface IPAUFactoryLike {

    function beacon() external view returns (address);

}

/**
 * @notice Integration coverage against the *canonical* diamond-pau PAUFactory and the real
 *         AdministeredAgentFactory (no mocks). Exercises the adapter against the real bytecode.
 */
contract DefaultPAUAssembler_Integration_Tests is Test {

    address internal constant AAVE_FACET                 = 0x8CE890A96a193ff2DD4B2eA3C682326F655f6b62;
    address internal constant ADMINISTERED_AGENT_FACTORY = 0x2968c3b5478cF93B70aB1e24255d4EDBBd27a089;
    address internal constant PAU_FACTORY                = 0x69A5d548830AC2A4Ba90A44a2C75BDA71f97fc66;
    address internal constant TRANSFER_ASSET_FACET       = 0x4DA7608C331b8f135df5b985018933780eCd089D;

    bytes32 internal constant AAVE_INTEGRATION_ID           = "AAVE_FACET";
    bytes32 internal constant ALLOCATOR_ROLE                = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE            = 0x00;
    bytes32 internal constant TRANSFER_ASSET_INTEGRATION_ID = "TRANSFER_ASSET_FACET";

    DefaultPAUAssembler internal assembler;

    function setUp() external {
        vm.createSelectFork("mainnet", 25270600);

        assembler = new DefaultPAUAssembler(ADMINISTERED_AGENT_FACTORY, PAU_FACTORY);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroAdministeredAgentFactory() external {
        vm.expectRevert(abi.encodeWithSelector(IDefaultPAUAssembler.ZeroAdministeredAgentFactory.selector));
        new DefaultPAUAssembler(address(0), address(0));
    }

    function test_constructor_zeroPAUFactory() external {
        vm.expectRevert(abi.encodeWithSelector(IDefaultPAUAssembler.ZeroPAUFactory.selector));
        new DefaultPAUAssembler(ADMINISTERED_AGENT_FACTORY, address(0));
    }

    /**********************************************************************************************/
    /*** Initial State Test                                                                    ***/
    /**********************************************************************************************/

    function test_initialState() external view {
        assertEq(assembler.VERSION(),                  "1.0.0");
        assertEq(assembler.administeredAgentFactory(), ADMINISTERED_AGENT_FACTORY);
        assertEq(assembler.pauFactory(),               PAU_FACTORY);
    }

    /**********************************************************************************************/
    /*** deploy Tests                                                                           ***/
    /**********************************************************************************************/

    function test_deploy_noAgentAdmins() external {
        IDefaultPAUAssembler.AdminConfig memory adminConfig = IDefaultPAUAssembler.AdminConfig({
            accessControlAdmins : new address[](0),
            proxyAdmins         : new address[](0),
            rateLimitsAdmins    : new address[](0)
        });

        IDefaultPAUAssembler.AdministeredAgentConfig[] memory administeredAgentConfigs = new IDefaultPAUAssembler.AdministeredAgentConfig[](1);

        administeredAgentConfigs[0] = IDefaultPAUAssembler.AdministeredAgentConfig({
            admins   : new address[](0),
            actors   : new address[](0),
            grantors : new address[](0),
            revokers : new address[](0)
        });

        vm.expectRevert(IDefaultPAUAssembler.NoAgentAdmins.selector);
        assembler.deploy(new bytes32[](0), adminConfig, administeredAgentConfigs);
    }

    function test_deploy_noDefaultAdmins() external {
        IDefaultPAUAssembler.AdministeredAgentConfig[] memory administeredAgentConfigs = new IDefaultPAUAssembler.AdministeredAgentConfig[](0);

        IDefaultPAUAssembler.AdminConfig memory adminConfig = IDefaultPAUAssembler.AdminConfig({
            accessControlAdmins : new address[](0),
            proxyAdmins         : new address[](0),
            rateLimitsAdmins    : new address[](0)
        });

        vm.expectRevert(IDefaultPAUAssembler.NoDefaultAdmins.selector);
        assembler.deploy(new bytes32[](0), adminConfig, administeredAgentConfigs);

        adminConfig = IDefaultPAUAssembler.AdminConfig({
            accessControlAdmins : new address[](1),
            proxyAdmins         : new address[](0),
            rateLimitsAdmins    : new address[](0)
        });

        adminConfig.accessControlAdmins[0] = makeAddr("accessControlAdmin");

        vm.expectRevert(IDefaultPAUAssembler.NoDefaultAdmins.selector);
        assembler.deploy(new bytes32[](0), adminConfig, administeredAgentConfigs);

        adminConfig = IDefaultPAUAssembler.AdminConfig({
            accessControlAdmins : new address[](1),
            proxyAdmins         : new address[](1),
            rateLimitsAdmins    : new address[](0)
        });

        adminConfig.accessControlAdmins[0] = makeAddr("accessControlAdmin");
        adminConfig.proxyAdmins[0]         = makeAddr("proxyAdmin");

        vm.expectRevert(IDefaultPAUAssembler.NoDefaultAdmins.selector);
        assembler.deploy(new bytes32[](0), adminConfig, administeredAgentConfigs);
    }

    function test_deploy_zeroDefaultAdmin() external {
        IDefaultPAUAssembler.AdministeredAgentConfig[] memory administeredAgentConfigs = new IDefaultPAUAssembler.AdministeredAgentConfig[](0);

        IDefaultPAUAssembler.AdminConfig memory adminConfig = IDefaultPAUAssembler.AdminConfig({
            accessControlAdmins : new address[](1),
            proxyAdmins         : new address[](0),
            rateLimitsAdmins    : new address[](0)
        });

        vm.expectRevert(IDefaultPAUAssembler.ZeroDefaultAdmin.selector);
        assembler.deploy(new bytes32[](0), adminConfig, administeredAgentConfigs);

        adminConfig = IDefaultPAUAssembler.AdminConfig({
            accessControlAdmins : new address[](1),
            proxyAdmins         : new address[](1),
            rateLimitsAdmins    : new address[](0)
        });

        adminConfig.accessControlAdmins[0] = makeAddr("accessControlAdmin");

        vm.expectRevert(IDefaultPAUAssembler.ZeroDefaultAdmin.selector);
        assembler.deploy(new bytes32[](0), adminConfig, administeredAgentConfigs);

        adminConfig = IDefaultPAUAssembler.AdminConfig({
            accessControlAdmins : new address[](1),
            proxyAdmins         : new address[](1),
            rateLimitsAdmins    : new address[](1)
        });

        adminConfig.accessControlAdmins[0] = makeAddr("accessControlAdmin");
        adminConfig.proxyAdmins[0]         = makeAddr("proxyAdmin");

        vm.expectRevert(IDefaultPAUAssembler.ZeroDefaultAdmin.selector);
        assembler.deploy(new bytes32[](0), adminConfig, administeredAgentConfigs);
    }

    function test_deploy() external {
        bytes32[] memory integrationIds = new bytes32[](2);
        integrationIds[0] = AAVE_INTEGRATION_ID;
        integrationIds[1] = TRANSFER_ASSET_INTEGRATION_ID;

        IDefaultPAUAssembler.AdminConfig memory adminConfig = IDefaultPAUAssembler.AdminConfig({
            accessControlAdmins : new address[](2),
            proxyAdmins         : new address[](2),
            rateLimitsAdmins    : new address[](2)
        });

        adminConfig.accessControlAdmins[0] = makeAddr("accessControlAdmin1");
        adminConfig.accessControlAdmins[1] = makeAddr("accessControlAdmin2");
        adminConfig.proxyAdmins[0]         = makeAddr("proxyAdmin1");
        adminConfig.proxyAdmins[1]         = makeAddr("proxyAdmin2");
        adminConfig.rateLimitsAdmins[0]    = makeAddr("rateLimitsAdmin1");
        adminConfig.rateLimitsAdmins[1]    = makeAddr("rateLimitsAdmin2");

        IDefaultPAUAssembler.AdministeredAgentConfig[] memory administeredAgentConfigs = new IDefaultPAUAssembler.AdministeredAgentConfig[](2);

        administeredAgentConfigs[0] = IDefaultPAUAssembler.AdministeredAgentConfig({
            admins   : new address[](2),
            actors   : new address[](3),
            grantors : new address[](2),
            revokers : new address[](2)
        });

        administeredAgentConfigs[0].admins[0] = makeAddr("adminA1");
        administeredAgentConfigs[0].admins[1] = makeAddr("adminA2");

        administeredAgentConfigs[0].actors[0] = makeAddr("actorA1");
        administeredAgentConfigs[0].actors[1] = makeAddr("actorA2");
        administeredAgentConfigs[0].actors[2] = makeAddr("actorA3");

        administeredAgentConfigs[0].grantors[0] = makeAddr("granterA1");
        administeredAgentConfigs[0].grantors[1] = makeAddr("granterA2");

        administeredAgentConfigs[0].revokers[0] = makeAddr("revokerA1");
        administeredAgentConfigs[0].revokers[1] = makeAddr("revokerA2");

        administeredAgentConfigs[1] = IDefaultPAUAssembler.AdministeredAgentConfig({
            admins   : new address[](1),
            actors   : new address[](1),
            grantors : new address[](1),
            revokers : new address[](1)
        });

        administeredAgentConfigs[1].admins[0] = makeAddr("adminB1");

        administeredAgentConfigs[1].actors[0] = makeAddr("actorB1");

        administeredAgentConfigs[1].grantors[0] = makeAddr("granterB1");

        administeredAgentConfigs[1].revokers[0] = makeAddr("revokerB1");

        address[] memory expectedAllocatorAgents = new address[](2);
        expectedAllocatorAgents[0] = vm.computeCreateAddress(ADMINISTERED_AGENT_FACTORY, vm.getNonce(ADMINISTERED_AGENT_FACTORY));
        expectedAllocatorAgents[1] = vm.computeCreateAddress(ADMINISTERED_AGENT_FACTORY, vm.getNonce(ADMINISTERED_AGENT_FACTORY) + 1);

        address expectedAccessControls = vm.computeCreateAddress(PAU_FACTORY, vm.getNonce(PAU_FACTORY));
        address expectedProxy          = vm.computeCreateAddress(PAU_FACTORY, vm.getNonce(PAU_FACTORY) + 1);
        address expectedRateLimits     = vm.computeCreateAddress(PAU_FACTORY, vm.getNonce(PAU_FACTORY) + 2);
        address expectedController     = vm.computeCreateAddress(PAU_FACTORY, vm.getNonce(PAU_FACTORY) + 3);

        vm.expectEmit(address(assembler));
        emit IDefaultPAUAssembler.Deployment(
            expectedProxy,
            expectedController,
            expectedAccessControls,
            expectedRateLimits,
            expectedAllocatorAgents,
            integrationIds,
            adminConfig,
            administeredAgentConfigs
        );

        (
            address          proxy,
            address          controller,
            address          accessControls,
            address          rateLimits,
            address[] memory allocatorAgents
        ) = assembler.deploy(integrationIds, adminConfig, administeredAgentConfigs);

        // Assert allocatorAgents state.
        assertEq(allocatorAgents.length, 2);

        // Assert allocator0 state.
        assertEq(allocatorAgents[0], expectedAllocatorAgents[0]);

        IAdministeredAgentLike allocator0 = IAdministeredAgentLike(allocatorAgents[0]);

        assertEq(allocator0.actorCount(),   3);
        assertEq(allocator0.adminCount(),   2);
        assertEq(allocator0.grantorCount(), 2);
        assertEq(allocator0.revokerCount(), 2);

        assertEq(allocator0.getIsActor(makeAddr("actorA1")),     true);
        assertEq(allocator0.getIsActor(makeAddr("actorA2")),     true);
        assertEq(allocator0.getIsActor(makeAddr("actorA3")),     true);
        assertEq(allocator0.getIsAdmin(makeAddr("adminA1")),     true);
        assertEq(allocator0.getIsAdmin(makeAddr("adminA2")),     true);
        assertEq(allocator0.getIsGrantor(makeAddr("granterA1")), true);
        assertEq(allocator0.getIsGrantor(makeAddr("granterA2")), true);
        assertEq(allocator0.getIsRevoker(makeAddr("revokerA1")), true);
        assertEq(allocator0.getIsRevoker(makeAddr("revokerA2")), true);

        // Assert allocator1 state.
        assertEq(allocatorAgents[1], expectedAllocatorAgents[1]);

        IAdministeredAgentLike allocator1 = IAdministeredAgentLike(allocatorAgents[1]);

        assertEq(allocator1.actorCount(),   1);
        assertEq(allocator1.adminCount(),   1);
        assertEq(allocator1.grantorCount(), 1);
        assertEq(allocator1.revokerCount(), 1);

        assertEq(allocator1.getIsActor(makeAddr("actorB1")),     true);
        assertEq(allocator1.getIsAdmin(makeAddr("adminB1")),     true);
        assertEq(allocator1.getIsGrantor(makeAddr("granterB1")), true);
        assertEq(allocator1.getIsRevoker(makeAddr("revokerB1")), true);

        // Assert AccessControls state.
        assertEq(accessControls, expectedAccessControls);

        assertEq(IAccessControlLike(accessControls).getRoleMemberCount(DEFAULT_ADMIN_ROLE), 2);
        assertEq(IAccessControlLike(accessControls).getRoleMemberCount(ALLOCATOR_ROLE),     2);

        assertEq(IAccessControlLike(accessControls).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("accessControlAdmin1")), true);
        assertEq(IAccessControlLike(accessControls).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("accessControlAdmin2")), true);
        assertEq(IAccessControlLike(accessControls).hasRole(DEFAULT_ADMIN_ROLE, address(assembler)),              false);
        assertEq(IAccessControlLike(accessControls).hasRole(ALLOCATOR_ROLE,     allocatorAgents[0]),              true);
        assertEq(IAccessControlLike(accessControls).hasRole(ALLOCATOR_ROLE,     allocatorAgents[1]),              true);

        assertEq(IAccessControlLike(accessControls).getRoleAdmin(ALLOCATOR_ROLE), DEFAULT_ADMIN_ROLE);

        // Assert ALMProxy state.
        assertEq(proxy, expectedProxy);

        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE,                makeAddr("proxyAdmin1")), true);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE,                makeAddr("proxyAdmin2")), true);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE,                address(assembler)),      false);
        assertEq(IAccessControlLike(proxy).hasRole(IALMProxyLike(proxy).CONTROLLER(), controller),              true);

        // Assert Controller state.
        assertEq(controller, expectedController);

        assertEq(IControllerLike(controller).accessControls(), accessControls);
        assertEq(IControllerLike(controller).beacon(),         IPAUFactoryLike(PAU_FACTORY).beacon());
        assertEq(IControllerLike(controller).proxy(),          proxy);
        assertEq(IControllerLike(controller).rateLimits(),     rateLimits);

        assertEq(IControllerLike(controller).integrations().length, 2);

        assertEq(IControllerLike(controller).integrations()[0].id, AAVE_INTEGRATION_ID);
        assertEq(IControllerLike(controller).integrations()[1].id, TRANSFER_ASSET_INTEGRATION_ID);

        assertEq(IControllerLike(controller).integrations()[0].config.facet, AAVE_FACET);
        assertEq(IControllerLike(controller).integrations()[1].config.facet, TRANSFER_ASSET_FACET);

        assertEq(IControllerLike(controller).integrations()[0].config.wires.length, 7);
        assertEq(IControllerLike(controller).integrations()[1].config.wires.length, 3);

        // Assert RateLimits state.
        assertEq(rateLimits, expectedRateLimits);

        assertEq(IAccessControlLike(rateLimits).hasRole(DEFAULT_ADMIN_ROLE,                       makeAddr("rateLimitsAdmin1")), true);
        assertEq(IAccessControlLike(rateLimits).hasRole(DEFAULT_ADMIN_ROLE,                       makeAddr("rateLimitsAdmin2")), true);
        assertEq(IAccessControlLike(rateLimits).hasRole(DEFAULT_ADMIN_ROLE,                       address(assembler)),           false);
        assertEq(IAccessControlLike(rateLimits).hasRole(IRateLimitsLike(rateLimits).CONTROLLER(), controller),                   true);
    }

}
