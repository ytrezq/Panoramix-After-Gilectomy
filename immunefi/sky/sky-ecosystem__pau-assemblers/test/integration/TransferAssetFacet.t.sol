// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IDefaultPAUAssembler } from "../../src/interfaces/IDefaultPAUAssembler.sol";

import { DefaultPAUAssembler } from "../../src/DefaultPAUAssembler.sol";

interface IAdministeredAgentLike {

    error NotActor();

    function call(address target, bytes memory data) external payable returns (bytes memory result);

}

interface IControllerLike {

    function transferAsset_transfer(address asset, address destination, uint256 amount) external;

    function transferAsset_getTransferRateLimitKey(address asset, address destination) external view returns (bytes32);

}

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

interface IRateLimitsLike {

    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;

    function getCurrentRateLimit(bytes32 key) external view returns (uint256);

}

/**
 * @notice Full end-to-end integration: the assembler deploys a real PAU stack (real Beacon,
 *         PAUFactory, Controller, ALMProxy, RateLimits) with a real TransferAssetFacet integration
 *         registered, then an actor routes a real ERC20 transfer through
 *         AdministeredAgent -> Controller -> facet -> ALMProxy -> token.
 */
contract DefaultPAUAssembler_TransferAsset_Integration_Tests is Test {

    address internal constant ADMINISTERED_AGENT_FACTORY = 0x2968c3b5478cF93B70aB1e24255d4EDBBd27a089;
    address internal constant PAU_FACTORY                = 0x69A5d548830AC2A4Ba90A44a2C75BDA71f97fc66;
    address internal constant USDC                       = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    bytes32 internal constant TRANSFER_ASSET_INTEGRATION_ID = "TRANSFER_ASSET_FACET";

    address internal admin     = makeAddr("admin");
    address internal allocator = makeAddr("allocator");
    address internal recipient = makeAddr("recipient");

    DefaultPAUAssembler internal assembler;

    address internal accessControls;
    address internal allocatorAgent;
    address internal controller;
    address internal proxy;
    address internal rateLimits;

    bytes32 internal transferRateLimitKey;

    function setUp() external {
        vm.createSelectFork("mainnet", 25270600);

        assembler = new DefaultPAUAssembler(ADMINISTERED_AGENT_FACTORY, PAU_FACTORY);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = TRANSFER_ASSET_INTEGRATION_ID;

        address[] memory admins = new address[](1);
        admins[0] = admin;

        IDefaultPAUAssembler.AdminConfig memory adminConfig = IDefaultPAUAssembler.AdminConfig({
            accessControlAdmins : admins,
            proxyAdmins         : admins,
            rateLimitsAdmins    : admins
        });

        address[] memory allocators = new address[](1);
        allocators[0] = allocator;

        IDefaultPAUAssembler.AdministeredAgentConfig memory administeredAgentConfig = IDefaultPAUAssembler.AdministeredAgentConfig({
            admins   : admins,
            actors   : allocators,
            grantors : new address[](0),
            revokers : new address[](0)
        });

        IDefaultPAUAssembler.AdministeredAgentConfig[] memory administeredAgentConfigs = new IDefaultPAUAssembler.AdministeredAgentConfig[](1);
        administeredAgentConfigs[0] = administeredAgentConfig;

        address[] memory allocatorAgents;

        (
            proxy,
            controller,
            accessControls,
            rateLimits,
            allocatorAgents
        ) = assembler.deploy(integrationIds, adminConfig, administeredAgentConfigs);

        allocatorAgent = allocatorAgents[0];

        // Fund the proxy and set the rate limit for this asset/destination pair.
        deal(USDC, proxy, 1_500_000e6);

        transferRateLimitKey = IControllerLike(controller).transferAsset_getTransferRateLimitKey(USDC, recipient);

        vm.prank(admin);
        IRateLimitsLike(address(rateLimits)).setRateLimitData(transferRateLimitKey, 2_000_000e6, 0);
    }

    function test_endToEnd_transferAsset() external {
        assertEq(IERC20Like(USDC).balanceOf(address(proxy)), 1_500_000e6);
        assertEq(IERC20Like(USDC).balanceOf(recipient),      0);

        assertEq(IRateLimitsLike(address(rateLimits)).getCurrentRateLimit(transferRateLimitKey), 2_000_000e6);

        vm.prank(allocator);
        IAdministeredAgentLike(allocatorAgent).call(
            controller,
            abi.encodeWithSelector(IControllerLike.transferAsset_transfer.selector, USDC, recipient, 1_100_000e6)
        );

        assertEq(IERC20Like(USDC).balanceOf(address(proxy)), 400_000e6);
        assertEq(IERC20Like(USDC).balanceOf(recipient),      1_100_000e6);

        assertEq(IRateLimitsLike(address(rateLimits)).getCurrentRateLimit(transferRateLimitKey), 900_000e6);
    }

    // Sanity: only an actor on the agent can drive the transfer.
    function test_endToEnd_revertsForNonActor() external {
        vm.prank(makeAddr("non-actor"));
        vm.expectRevert(IAdministeredAgentLike.NotActor.selector);
        IAdministeredAgentLike(allocatorAgent).call(
            controller,
            abi.encodeWithSelector(IControllerLike.transferAsset_transfer.selector, USDC, recipient, 1_100_000e6)
        );
    }

}
