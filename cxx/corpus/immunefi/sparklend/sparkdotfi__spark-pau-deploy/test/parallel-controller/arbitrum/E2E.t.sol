// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IAccessControl } from "../../../lib/diamond-pau/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IERC20 }         from "../../../lib/diamond-pau/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { IAccessControls }                           from "../../../lib/diamond-pau/src/interfaces/IAccessControls.sol";
import { IALMProxy }                                 from "../../../lib/diamond-pau/src/interfaces/IALMProxy.sol";
import { IBeacon }                                   from "../../../lib/diamond-pau/src/interfaces/IBeacon.sol";
import { IController }                               from "../../../lib/diamond-pau/src/interfaces/IController.sol";
import { IPAUFactory }                               from "../../../lib/diamond-pau/src/interfaces/IPAUFactory.sol";
import { IRateLimits }                               from "../../../lib/diamond-pau/src/interfaces/IRateLimits.sol";
import { IMainnetControllerFull as IControllerFull } from "../../../lib/diamond-pau/test/interfaces/IMainnetControllerFull.sol";

import { Beacon }     from "../../../lib/diamond-pau/src/Beacon.sol";
import { PAUFactory } from "../../../lib/diamond-pau/src/PAUFactory.sol";
import { CCTPFacet }  from "../../../lib/diamond-pau/src/facets/cctp/CCTPFacet.sol";

import { AdministeredAgent }         from "../../../lib/pau-administered-agent/src/AdministeredAgent.sol";
import { AdministeredAgentFactory }  from "../../../lib/pau-administered-agent/src/AdministeredAgentFactory.sol";
import { IAdministeredAgent }        from "../../../lib/pau-administered-agent/src/interfaces/IAdministeredAgent.sol";
import { IAdministeredAgentFactory } from "../../../lib/pau-administered-agent/src/interfaces/IAdministeredAgentFactory.sol";

import { Arbitrum } from "../../../lib/spark-address-registry/src/Arbitrum.sol";
import { Ethereum } from "../../../lib/spark-address-registry/src/Ethereum.sol";

import { Ethereum as SkyEthereum } from "../../../lib/sky-pau-registry/src/Ethereum.sol";

import { Bridge, BridgeType }    from "../../../lib/diamond-pau/lib/grove-xchain-helpers/src/testing/Bridge.sol";
import { CCTPv2BridgeTesting }   from "../../../lib/diamond-pau/lib/grove-xchain-helpers/src/testing/bridges/CCTPv2BridgeTesting.sol";
import { CCTPv2Forwarder }       from "../../../lib/diamond-pau/lib/grove-xchain-helpers/src/forwarders/CCTPv2Forwarder.sol";
import { Domain, DomainHelpers } from "../../../lib/diamond-pau/lib/grove-xchain-helpers/src/testing/Domain.sol";

import { BeaconConfig }    from "../../../src/BeaconConfig.sol";
import { InitParallelPAU } from "../../../src/InitParallelPAU.sol";

import { ArbitrumPostDeployTestsBase } from "./PostDeployTests.t.sol";

interface ILegacyController {

    function transferUSDCToCCTP(uint256 usdcAmount, uint32 destinationDomain) external;

}

/**
 * @notice Runs the exact production code path (the two parallel-controller scripts) on an
 *         Arbitrum fork as the deployer, asserts the same end state the post-deploy test
 *         checks, then simulates the governance spell and pushes a real CCTP V2 burn through
 *         the new controller to prove the Arbitrum -> Ethereum route works.
 *
 *         Script 0 (deploy): deploys Beacon (admin-owned), PAUFactory, AgentFactory, CCTPFacet,
 *                            AccessControls, RateLimits, Controller, AdministeredAgent.
 *         Script 1 (configure): wires CCTP on Beacon, calls InitParallelPAU.initParallelPAU,
 *                               then _transferAdminRoles (grants beacon to admin, revokes deployer
 *                               from Beacon/AccessControls/RateLimits/AdministeredAgent).
 */
abstract contract ArbitrumParallelE2ETestsBase is ArbitrumPostDeployTestsBase {

    using DomainHelpers       for *;
    using CCTPv2BridgeTesting for Bridge;

    address internal constant DEPLOYER = 0xC758519Ace14E884fdbA9ccE25F2DbE81b7e136f;

    address internal CCTP_MESSAGE_TRANSMITTER = CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ETHEREUM;

    uint32 internal ETHEREUM_CCTP_DOMAIN = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM;
    uint32 internal ARBITRUM_CCTP_DOMAIN = 3;

    Bridge internal bridge;
    Domain internal mainnet;
    Domain internal arbitrum;

    address internal ethereumAlmProxy;
    uint32  internal ethereumDomainId;

    function setUp() public virtual override {
        super.setUp();

        admin    = Arbitrum.SPARK_EXECUTOR;
        deployer = DEPLOYER;
        relayer  = Arbitrum.ALM_RELAYER_MULTISIG;
        freezer  = Arbitrum.ALM_FREEZER_MULTISIG;
        grantor  = Arbitrum.PAU_GRANTOR_MULTISIG;

        almProxy           = IALMProxy(Arbitrum.ALM_PROXY);
        skyMainnetBeacon   = IBeacon(SkyEthereum.BEACON);
        legacyController   = Arbitrum.ALM_CONTROLLER;
        cctpTokenMessenger = Arbitrum.CCTP_TOKEN_MESSENGER;
        usdc               = Arbitrum.USDC;
        ethereumAlmProxy   = Ethereum.ALM_PROXY;
        ethereumDomainId   = 0;

        mainnet  = getChain("mainnet").createSelectFork(26005798); // September 18, 2026
        arbitrum = Domain({ chain: getChain("arbitrum_one"), forkId: arbitrumFork });

        bridge = CCTPv2BridgeTesting.init(Bridge({
            bridgeType                     : BridgeType.CCTP_V2,
            source                         : arbitrum,
            destination                    : mainnet,
            sourceCrossChainMessenger      : CCTP_MESSAGE_TRANSMITTER,
            destinationCrossChainMessenger : CCTP_MESSAGE_TRANSMITTER,
            lastSourceLogIndex             : 0,
            lastDestinationLogIndex        : 0,
            extraData                      : ""
        }));

        arbitrum.selectFork();
    }

    function _assertFacetConstructors() internal view override {
        assertEq(CCTPFacet(cctpFacet).cctp(), cctpTokenMessenger);
        assertEq(CCTPFacet(cctpFacet).usdc(), usdc);
    }

    /**********************************************************************************************/
    /*** Guard rails                                                                            ***/
    /**********************************************************************************************/

    /// @dev Before the spell the controller can be called but cannot move anything — no
    ///      CONTROLLER role on the proxy and no rate limits. Rate limits fail closed first.
    function test_transferRevertsBeforeSpell() external {
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        administeredAgent.call(
            address(controller),
            abi.encodeCall(controller.cctp_transfer, (1e6, ethereumDomainId, 0))
        );
    }

    /// @dev Only the AdministeredAgent holds ALLOCATOR_ROLE. A relayer calling the controller
    ///      directly is rejected by the onlyRole guard.
    function test_relayerCannotCallControllerDirectly() external {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, relayer, ALLOCATOR_ROLE));
        vm.prank(relayer);
        controller.cctp_transfer(1e6, ethereumDomainId, 0);
    }

    /// @dev The deployer retains no authority anywhere after configure.
    function test_deployerCannotAdministerAfterConfigure() external {
        address someAccount = makeAddr("someAccount");

        vm.startPrank(deployer);

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, deployer, DEFAULT_ADMIN_ROLE));
        beacon.revokeRole(DEFAULT_ADMIN_ROLE, someAccount);

        vm.expectRevert(abi.encodeWithSelector(IAdministeredAgent.NotAdmin.selector));
        administeredAgent.removeAdmin(someAccount);

        vm.expectRevert(abi.encodeWithSelector(IAdministeredAgent.NotGrantor.selector));
        administeredAgent.addActor(someAccount);

        vm.expectRevert(abi.encodeWithSelector(IAdministeredAgent.NotRevoker.selector));
        administeredAgent.removeActor(someAccount);

        vm.expectRevert(abi.encodeWithSelector(IAdministeredAgent.NotActor.selector));
        administeredAgent.call(someAccount, "");

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, deployer, DEFAULT_ADMIN_ROLE));
        accessControls.revokeRole(DEFAULT_ADMIN_ROLE, someAccount);

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, deployer, DEFAULT_ADMIN_ROLE));
        rateLimits.revokeRole(DEFAULT_ADMIN_ROLE, someAccount);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = BeaconConfig.CCTP_INTEGRATION;

        vm.expectRevert(abi.encodeWithSelector(IController.NotAdmin.selector, deployer));
        controller.removeIntegrations(ids);

        vm.stopPrank();
    }

    /**********************************************************************************************/
    /*** Simulated spell + live CCTP V2 burn                                                    ***/
    /**********************************************************************************************/

    /// @dev The spell grants CONTROLLER on the existing ALMProxy and sets the two CCTP rate limits.
    function _runSpell() internal {
        uint256 maxAmount = 10_000_000e6;
        uint256 slope     = uint256(50_000_000e6) / 1 days;

        bytes32 totalKey  = controller.cctp_toCCTPRateLimitKey();
        bytes32 domainKey = controller.cctp_getToDomainRateLimitKey(ethereumDomainId);

        // --- Spell (Spark Executor is admin of the proxy, AccessControls, and the new RateLimits) ---

        vm.startPrank(Arbitrum.SPARK_EXECUTOR);

        // Spell action 1: Grant CONTROLLER on the existing ALMProxy.
        almProxy.grantRole(CONTROLLER_ROLE, address(controller));

        // Spell action 2: Configure Ethereum domain parameters (recipient = Ethereum ALMProxy).
        controller.cctp_setDomainParameters(
            ethereumDomainId,
            bytes32(uint256(uint160(ethereumAlmProxy))),
            0,  // minFeeCapRate: standard finality, fee-free
            0   // maxFeeCapRate: fee-free
        );

        // Spell action 3: Set CCTP rate limits on the new RateLimits contract.
        rateLimits.setRateLimitData(totalKey,  maxAmount, slope);
        rateLimits.setRateLimitData(domainKey, maxAmount, slope);

        vm.stopPrank();
    }

    /// @dev The spell grants CONTROLLER on the existing ALMProxy and sets the two CCTP rate
    ///      limits. After that a relayer can bridge USDC to the Spark Ethereum ALMProxy through
    ///      Circle's TokenMessengerV2, and the legacy controller is unaffected.
    function test_spellThenCCTPTransfer() external {
        _runSpell();

        assertEq(almProxy.hasRole(CONTROLLER_ROLE, legacyController),    true);
        assertEq(almProxy.hasRole(CONTROLLER_ROLE, address(controller)), true);

        bytes32 totalKey  = controller.cctp_toCCTPRateLimitKey();
        bytes32 domainKey = controller.cctp_getToDomainRateLimitKey(ethereumDomainId);

        uint256 startingTotalAmount  = rateLimits.getCurrentRateLimit(totalKey);
        uint256 startingDomainAmount = rateLimits.getCurrentRateLimit(domainKey);

        // --- Fund the proxy with idle USDC ---

        uint256 amount = 1_000_000e6;

        deal(usdc, address(almProxy), amount);

        uint256 usdcSupplyBefore = IERC20(usdc).totalSupply();

        // --- Relayer bridges through the AdministeredAgent ---

        vm.prank(relayer);
        administeredAgent.call(
            address(controller),
            abi.encodeCall(controller.cctp_transfer, (amount, ethereumDomainId, 0))
        );

        // USDC burned from the proxy, no leftover allowance, both limits consumed.
        assertEq(IERC20(usdc).balanceOf(address(almProxy)),                      0);
        assertEq(IERC20(usdc).allowance(address(almProxy), cctpTokenMessenger),  0);
        assertEq(IERC20(usdc).totalSupply(),                                     usdcSupplyBefore - amount);

        assertEq(rateLimits.getCurrentRateLimit(totalKey),  startingTotalAmount - amount);
        assertEq(rateLimits.getCurrentRateLimit(domainKey), startingDomainAmount - amount);

        // --- Relay the message to Ethereum ---

        mainnet.selectFork();

        uint256 mainnetUsdcSupply = IERC20(Ethereum.USDC).totalSupply();

        assertEq(IERC20(Ethereum.USDC).balanceOf(ethereumAlmProxy), 0);

        bridge.relayMessagesToDestination(true);

        assertEq(IERC20(Ethereum.USDC).balanceOf(ethereumAlmProxy), amount);
        assertEq(IERC20(Ethereum.USDC).totalSupply(),               mainnetUsdcSupply + amount);

        arbitrum.selectFork();

        // Over the remaining limit fails closed.
        deal(usdc, address(almProxy), startingTotalAmount);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        administeredAgent.call(
            address(controller),
            abi.encodeCall(controller.cctp_transfer, (startingTotalAmount, ethereumDomainId, 0))
        );

        // An unconfigured destination domain fails before hitting the proxy.
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        administeredAgent.call(
            address(controller),
            abi.encodeCall(controller.cctp_transfer, (1e6, 6, 0))
        );
    }

    /// @dev Kill switch: one admin transaction makes the CCTP facet unreachable; legacy
    ///      controller is untouched.
    function test_removeIntegrationIsKillSwitch() external {
        _runSpell();

        // Can call cctp_transfer on pau controller
        vm.prank(relayer);
        administeredAgent.call(
            address(controller),
            abi.encodeCall(controller.cctp_transfer, (1e6, ethereumDomainId, 0))
        );

        // Remove cctp integration
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = BeaconConfig.CCTP_INTEGRATION;

        vm.prank(admin);
        controller.removeIntegrations(ids);

        assertEq(controller.integrations().length, 0);

        // Cannot call cctp_transfer on pau controller
        vm.expectRevert(abi.encodeWithSelector(IController.CallSelectorNotWired.selector, controller.cctp_transfer.selector));
        vm.prank(relayer);
        administeredAgent.call(
            address(controller),
            abi.encodeCall(controller.cctp_transfer, (1e6, ethereumDomainId, 0))
        );

        // Can still call cctp_transfer on legacy controller
        vm.prank(relayer);
        ILegacyController(legacyController).transferUSDCToCCTP(1e6, ethereumDomainId);
    }

}

contract ArbitrumParallelE2ETestLocal is ArbitrumParallelE2ETestsBase {

    function setUp() public override {
        super.setUp();

        vm.startPrank(deployer);
        _runDeployScript();
        _runConfigureScript();
        vm.stopPrank();
    }

    function _getBlock() internal override pure returns (uint256) {
        return 506472875;
    }

    // Not running events tests in Local E2E tests.

    function test_beaconEvents() external override {
        vm.skip(true);
    }

    function test_administeredAgentEvents() external override {
        vm.skip(true);
    }

    function test_accessControlsEvents() external override {
        vm.skip(true);
    }

    function test_rateLimitsEvents() external override {
        vm.skip(true);
    }

    function test_controllerEvents() external override {
        vm.skip(true);
    }

    /**********************************************************************************************/
    /*** Script helpers                                                                         ***/
    /**********************************************************************************************/

    /// @dev Mirrors DeploySparkPAUParallelBase.run() + DeploySparkPAUParallelArbitrum._deployFacets().
    function _runDeployScript() internal {
        // deployer is the temporary initial admin of all four contracts;
        // configure script hands everything over to admin and revokes deployer.
        beacon       = new Beacon(deployer);
        pauFactory   = new PAUFactory(address(beacon));
        agentFactory = new AdministeredAgentFactory();

        cctpFacet = address(new CCTPFacet({
            cctp_ : cctpTokenMessenger,
            usdc_ : usdc
        }));

        accessControls    = IAccessControls(pauFactory.deployAccessControls(deployer));
        rateLimits        = IRateLimits(pauFactory.deployRateLimits(deployer));
        controller        = IControllerFull(pauFactory.deployController(address(accessControls), Arbitrum.ALM_PROXY, address(rateLimits)));
        administeredAgent = IAdministeredAgent(agentFactory.deploy(deployer));
    }

    /// @dev Mirrors ConfigureSparkPAUParallelBase.run() with ArbitrumStaging overrides.
    function _runConfigureScript() internal {
        // Step 1: Wire CCTP on Beacon.
        BeaconConfig.setCCTPIntegration(address(beacon), cctpFacet);

        // Step 2: Build InitParallelPAU params (mirrors _getAdminConfig + _getAgentConfigs).
        address[] memory accessControlAdmins = new address[](1);
        accessControlAdmins[0] = admin;

        address[] memory rateLimitsAdmins = new address[](1);
        rateLimitsAdmins[0] = admin;

        InitParallelPAU.AdminConfig memory adminConfig = InitParallelPAU.AdminConfig({
            accessControlAdmins : accessControlAdmins,
            rateLimitsAdmins    : rateLimitsAdmins
        });

        InitParallelPAU.AdministeredAgentConfig[] memory agentConfigs =
            _buildAgentConfigs();

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = BeaconConfig.CCTP_INTEGRATION;

        InitParallelPAU.initParallelPAU(address(controller), integrationIds, adminConfig, agentConfigs);

        // Step 3: _transferAdminRoles (mirrors ConfigureSparkPAUParallelBase._transferAdminRoles).
        beacon.grantRole(DEFAULT_ADMIN_ROLE, admin);

        beacon.revokeRole(DEFAULT_ADMIN_ROLE,         deployer);
        accessControls.revokeRole(DEFAULT_ADMIN_ROLE, deployer);
        rateLimits.revokeRole(DEFAULT_ADMIN_ROLE,     deployer);

        administeredAgent.removeAdmin(deployer);
    }

    function _buildAgentConfigs()
        internal
        view
        returns (InitParallelPAU.AdministeredAgentConfig[] memory agentConfigs)
    {
        address[] memory agentAdmins   = new address[](1);
        address[] memory agentActors   = new address[](1);
        address[] memory agentGrantors = new address[](1);
        address[] memory agentRevokers = new address[](1);

        agentAdmins[0]   = admin;
        agentActors[0]   = relayer;
        agentGrantors[0] = grantor;
        agentRevokers[0] = freezer;

        agentConfigs = new InitParallelPAU.AdministeredAgentConfig[](1);
        agentConfigs[0] = InitParallelPAU.AdministeredAgentConfig({
            agent    : address(administeredAgent),
            admins   : agentAdmins,
            actors   : agentActors,
            grantors : agentGrantors,
            revokers : agentRevokers
        });
    }

}


contract ArbitrumParallelE2ETestLive is ArbitrumParallelE2ETestsBase {

    function setUp() public override {
        super.setUp();

        beacon       = IBeacon(Arbitrum.SPARK_BEACON);
        pauFactory   = IPAUFactory(Arbitrum.SPARK_PAU_FACTORY);
        agentFactory = IAdministeredAgentFactory(Arbitrum.SPARK_ADMINISTERED_AGENT_FACTORY);

        cctpFacet         = Arbitrum.CCTP_FACET;
        accessControls    = IAccessControls(Arbitrum.PAU_ACCESS_CONTROLS);
        rateLimits        = IRateLimits(Arbitrum.PAU_RATELIMITS);
        controller        = IControllerFull(Arbitrum.PAU_CONTROLLER);
        administeredAgent = IAdministeredAgent(Arbitrum.PAU_ADMINISTERED_AGENT);
    }

    function _getBlock() internal override pure returns (uint256) {
        return 506472875;
    }

}
