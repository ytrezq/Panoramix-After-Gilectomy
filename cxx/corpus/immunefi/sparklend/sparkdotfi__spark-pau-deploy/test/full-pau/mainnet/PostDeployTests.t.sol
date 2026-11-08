// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { stdJson }  from "../../../lib/forge-std/src/StdJson.sol";

import { VmSafe } from "../../../lib/forge-std/src/Vm.sol";

import { IAccessControl } from "../../../lib/diamond-pau/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IEnumerableIntegrations as IEI } from "../../../lib/diamond-pau/src/interfaces/IEnumerableIntegrations.sol";

import { IAdministeredAgent } from "../../../lib/pau-administered-agent/src/interfaces/IAdministeredAgent.sol";

import { Ethereum } from "../../../lib/spark-address-registry/src/Ethereum.sol";

import { PostDeployTestBaseFull } from "../PostDeployTestBaseFull.t.sol";

interface IERC4626Like {

    function convertToShares(uint256 assets) external view returns (uint256 shares);

}

abstract contract MainnetPostDeployTestsBase is PostDeployTestBaseFull {

    bytes32 internal constant CCTP_FACET_ID    = "CCTP_FACET";
    bytes32 internal constant ERC4626_FACET_ID = "ERC4626_FACET";

    uint32 internal constant XLAYER_CCTP_DOMAIN = 37;

    address internal XLAYER_CCTP_MINT_RECIPIENT;

    uint32  internal CCTP_MIN_FEE_CAP_RATE;
    uint32  internal CCTP_MAX_FEE_CAP_RATE;

    uint256 internal CCTP_TO_CCTP_USDC_MAX_AMOUNT;
    uint256 internal CCTP_TO_CCTP_USDC_SLOPE;

    uint256 internal CCTP_TO_DOMAIN_USDC_MAX_AMOUNT;
    uint256 internal CCTP_TO_DOMAIN_USDC_SLOPE;

    uint256 internal ERC4626_USDC_MAX_AMOUNT;
    uint256 internal ERC4626_USDC_SLOPE;

    function setUp() public virtual override {
        super.setUp();

        vm.createSelectFork(getChain("mainnet").rpcUrl, _getBlock());
    }

    function _getBlock() internal virtual pure returns (uint256) {
        return 0;
    }

    /**********************************************************************************************/
    /*** Event assertions helpers                                                               ***/
    /**********************************************************************************************/

    function _assertAccessControlsEvents() internal {
        VmSafe.EthGetLogs[] memory logs = _getEvents(block.chainid, address(accessControls), "");

        assertEq(logs.length, 6);

        // Grant assembler DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[0],
            role    : DEFAULT_ADMIN_ROLE,
            account : address(assembler),
            sender  : address(pauFactory)
        });

        // Grant deployer DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[1],
            role    : DEFAULT_ADMIN_ROLE,
            account : deployer,
            sender  : address(assembler)
        });

        // Grant administeredAgent ALLOCATOR_ROLE
        _assertRoleGrantedEvent({
            log     : logs[2],
            role    : ALLOCATOR_ROLE,
            account : address(administeredAgent),
            sender  : address(assembler)
        });

        // Revoke assembler DEFAULT_ADMIN_ROLE
        _assertRoleRevokedEvent({
            log     : logs[3],
            role    : DEFAULT_ADMIN_ROLE,
            account : address(assembler),
            sender  : address(assembler)
        });

        // Grant admin DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[4],
            role    : DEFAULT_ADMIN_ROLE,
            account : admin,
            sender  : deployer
        });

        // Revoke deployer DEFAULT_ADMIN_ROLE
        _assertRoleRevokedEvent({
            log     : logs[5],
            role    : DEFAULT_ADMIN_ROLE,
            account : deployer,
            sender  : deployer
        });
    }

    function _assertALMProxyEvents() internal {
        VmSafe.EthGetLogs[] memory logs = _getEvents(block.chainid, address(almProxy), "");

        assertEq(logs.length, 6);

        // Grant assembler DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[0],
            role    : DEFAULT_ADMIN_ROLE,
            account : address(assembler),
            sender  : address(pauFactory)
        });

        // Grant deployer DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[1],
            role    : DEFAULT_ADMIN_ROLE,
            account : deployer,
            sender  : address(assembler)
        });

        // Grant controller CONTROLLER_ROLE
        _assertRoleGrantedEvent({
            log     : logs[2],
            role    : CONTROLLER_ROLE,
            account : address(controller),
            sender  : address(assembler)
        });

        // Revoke assembler DEFAULT_ADMIN_ROLE
        _assertRoleRevokedEvent({
            log     : logs[3],
            role    : DEFAULT_ADMIN_ROLE,
            account : address(assembler),
            sender  : address(assembler)
        });

        // Grant admin DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[4],
            role    : DEFAULT_ADMIN_ROLE,
            account : admin,
            sender  : deployer
        });

        // Revoke deployer DEFAULT_ADMIN_ROLE
        _assertRoleRevokedEvent({
            log     : logs[5],
            role    : DEFAULT_ADMIN_ROLE,
            account : deployer,
            sender  : deployer
        });
    }

    function _assertAdministeredAgentEvents() internal virtual {
        VmSafe.EthGetLogs[] memory logs = _getEvents(block.chainid, address(administeredAgent), "");

        assertEq(logs.length, 8);

        // Add assembler as admin
        _assertAdminAddedEvent({
            log     : logs[0],
            account : address(assembler),
            caller  : address(agentFactory)
        });

        // Add deployer as admin
        _assertAdminAddedEvent({
            log     : logs[1],
            account : deployer,
            caller  : address(assembler)
        });

        // Add relayer as actor
        _assertActorAddedEvent({
            log     : logs[2],
            account : relayer,
            caller  : address(assembler)
        });

        // Add grantor
        _assertGrantorAddedEvent({
            log     : logs[3],
            account : grantor,
            caller  : address(assembler)
        });

        // Add freezer as revoker
        _assertRevokerAddedEvent({
            log     : logs[4],
            account : freezer,
            caller  : address(assembler)
        });

        // Remove assembler as admin
        _assertAdminRemovedEvent({
            log     : logs[5],
            account : address(assembler),
            caller  : address(assembler)
        });

        // Add admin as admin
        _assertAdminAddedEvent({
            log     : logs[6],
            account : admin,
            caller  : deployer
        });

        // Remove deployer as admin
        _assertAdminRemovedEvent({
            log     : logs[7],
            account : deployer,
            caller  : deployer
        });
    }

    function _assertRateLimitsEvents() internal {
        VmSafe.EthGetLogs[] memory logs = _getEvents(block.chainid, address(rateLimits), "");

        assertEq(logs.length, 10); // 6 role grant/revoke events + 4 rate limit set events.

        // Grant assembler DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[0],
            role    : DEFAULT_ADMIN_ROLE,
            account : address(assembler),
            sender  : address(pauFactory)
        });

        // Grant deployer DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[1],
            role    : DEFAULT_ADMIN_ROLE,
            account : deployer,
            sender  : address(assembler)
        });

        // Grant controller CONTROLLER_ROLE
        _assertRoleGrantedEvent({
            log     : logs[2],
            role    : CONTROLLER_ROLE,
            account : address(controller),
            sender  : address(assembler)
        });

        // Revoke assembler DEFAULT_ADMIN_ROLE
        _assertRoleRevokedEvent({
            log     : logs[3],
            role    : DEFAULT_ADMIN_ROLE,
            account : address(assembler),
            sender  : address(assembler)
        });

        // Assert cctp_toCCTPRateLimitKey rate limit
        _assertRateLimitDataSetEvent({
            log       : logs[4],
            key       : controller.cctp_toCCTPRateLimitKey(),
            maxAmount : CCTP_TO_CCTP_USDC_MAX_AMOUNT,
            slope     : CCTP_TO_CCTP_USDC_SLOPE
        });

        // Assert cctp_getToDomainRateLimitKey rate limit
        _assertRateLimitDataSetEvent({
            log       : logs[5],
            key       : controller.cctp_getToDomainRateLimitKey(XLAYER_CCTP_DOMAIN),
            maxAmount : CCTP_TO_DOMAIN_USDC_MAX_AMOUNT,
            slope     : CCTP_TO_DOMAIN_USDC_SLOPE
        });

        // Assert erc4626_getDepositRateLimitKey(SUSDC, USDC) rate limit
        _assertRateLimitDataSetEvent({
            log       : logs[6],
            key       : controller.erc4626_getDepositRateLimitKey(Ethereum.SUSDC, Ethereum.USDC),
            maxAmount : ERC4626_USDC_MAX_AMOUNT,
            slope     : ERC4626_USDC_SLOPE
        });

        // Assert erc4626_getWithdrawRateLimitKey(SUSDC) rate limit
        _assertRateLimitDataSetEvent({
            log       : logs[7],
            key       : controller.erc4626_getWithdrawRateLimitKey(Ethereum.SUSDC),
            maxAmount : ERC4626_USDC_MAX_AMOUNT,
            slope     : ERC4626_USDC_SLOPE
        });

        // Grant admin DEFAULT_ADMIN_ROLE
        _assertRoleGrantedEvent({
            log     : logs[8],
            role    : DEFAULT_ADMIN_ROLE,
            account : admin,
            sender  : deployer
        });

        // Revoke deployer DEFAULT_ADMIN_ROLE
        _assertRoleRevokedEvent({
            log     : logs[9],
            role    : DEFAULT_ADMIN_ROLE,
            account : deployer,
            sender  : deployer
        });
    }

    function _assertControllerEvents() internal {
        VmSafe.EthGetLogs[] memory logs = _getEvents(block.chainid, address(controller), "");

        assertEq(logs.length, 5);

        // Assert controller Initialized event
        _assertInitializedEvent({
            log: logs[0]
        });

        // Assert CCTP_FACET_ID integration set event
        _assertIntegrationSetEvent({
            log           : logs[1],
            integrationId : CCTP_FACET_ID
        });

        // Assert ERC4626_FACET_ID integration set event
        _assertIntegrationSetEvent({
            log           : logs[2],
            integrationId : ERC4626_FACET_ID
        });

        // Assert CCTPDomainParametersSet event
        _assertCCTPDomainParametersSetEvent({
            log               : logs[3],
            destinationDomain : XLAYER_CCTP_DOMAIN,
            mintRecipient     : XLAYER_CCTP_MINT_RECIPIENT,
            minFeeCapRate     : CCTP_MIN_FEE_CAP_RATE,
            maxFeeCapRate     : CCTP_MAX_FEE_CAP_RATE
        });

        // Assert ERC4626MaxExchangeRateSet event
        _assertERC4626MaxExchangeRateSetEvent({
            log             : logs[4],
            token           : Ethereum.SUSDC,
            maxExchangeRate : 1e25
        });
    }

    /**********************************************************************************************/
    /*** External tests                                                                         ***/
    /**********************************************************************************************/

    function test_administeredAgentStateAndEvents() external {
        _assertAdministeredAgentState();
        _assertAdministeredAgentEvents();
    }

    function test_accessControlsStateAndEvents() external {
        _assertAccessControlsState();
        _assertAccessControlsEvents();
    }

    function test_almProxyStateAndEvents() external {
        _assertALMProxyState();
        _assertALMProxyEvents();
    }

    function test_rateLimitsStateAndEvents() external {
        _assertRateLimitsInitializationState();
        _assertRateLimitsEvents();
    }

    function test_controllerStateAndEvents() external {
        _assertControllerInitializationState();
        _assertControllerEvents();
    }

    function test_rateLimitsAndControllerOnboardingState() external view {
        // 0. Controller Integrations
        IEI.Integration[] memory integrations = controller.integrations();

        assertEq(integrations.length, 2);

        assertEq(integrations[0].id, CCTP_FACET_ID);
        assertEq(integrations[1].id, ERC4626_FACET_ID);

        for (uint256 i = 0; i < integrations.length; i++) {
            _assertIntegration(integrations[i].id);
        }

        // 1. CCTP facet onboarding

        // 1a. Controller state
        (
            bytes32 mintRecipient,
            uint32  minFeeCapRate,
            uint32  maxFeeCapRate
        ) = controller.cctp_getDomainParameters(XLAYER_CCTP_DOMAIN);

        assertEq(mintRecipient, bytes32(uint256(uint160(XLAYER_CCTP_MINT_RECIPIENT))));
        assertEq(minFeeCapRate, CCTP_MIN_FEE_CAP_RATE);
        assertEq(maxFeeCapRate, CCTP_MAX_FEE_CAP_RATE);

        // 1b. Rate limits state

        _assertRateLimitData(controller.cctp_toCCTPRateLimitKey(),                        CCTP_TO_CCTP_USDC_MAX_AMOUNT,   CCTP_TO_CCTP_USDC_SLOPE);
        _assertRateLimitData(controller.cctp_getToDomainRateLimitKey(XLAYER_CCTP_DOMAIN), CCTP_TO_DOMAIN_USDC_MAX_AMOUNT, CCTP_TO_DOMAIN_USDC_SLOPE);

        // 2. ERC4626 facet onboarding

        // 2a. Controller state
        assertEq(controller.erc4626_getMaxExchangeRate(Ethereum.SUSDC), 1e25);

        // 2b. Rate limits state

        _assertRateLimitData(controller.erc4626_getDepositRateLimitKey(Ethereum.SUSDC, Ethereum.USDC), ERC4626_USDC_MAX_AMOUNT, ERC4626_USDC_SLOPE);
        _assertRateLimitData(controller.erc4626_getWithdrawRateLimitKey(Ethereum.SUSDC),               ERC4626_USDC_MAX_AMOUNT, ERC4626_USDC_SLOPE);
    }

}

contract MainnetPostDeployTestsStaging is MainnetPostDeployTestsBase {

    using stdJson for string;

    function setUp() public override {
        super.setUp();

        // CCTP facet onboarding.
        XLAYER_CCTP_MINT_RECIPIENT = 0x9e8741C793D695ED6660f7B2860FE011110D5869;

        CCTP_MIN_FEE_CAP_RATE = 0;
        CCTP_MAX_FEE_CAP_RATE = 100;

        CCTP_TO_CCTP_USDC_MAX_AMOUNT = 10e6;
        CCTP_TO_CCTP_USDC_SLOPE      = uint256(100e6) / 1 hours;

        CCTP_TO_DOMAIN_USDC_MAX_AMOUNT = 10e6;
        CCTP_TO_DOMAIN_USDC_SLOPE      = uint256(100e6) / 1 hours;

        // ERC4626 facet onboarding.
        ERC4626_USDC_MAX_AMOUNT = 10e6;
        ERC4626_USDC_SLOPE      = uint256(100e6) / 1 hours;

        _setUpAddresses(vm.readFile("deployments/full-pau/mainnet-staging.json"));
    }

    function _getBlock() internal override pure returns (uint256) {
        return 25941422;
    }

    // Override to assert grantor count is 0 in staging.
    function _assertAdministeredAgentState() internal override view {
        assertEq(administeredAgent.adminCount(),   1);
        assertEq(administeredAgent.actorCount(),   1);
        assertEq(administeredAgent.grantorCount(), 0);
        assertEq(administeredAgent.revokerCount(), 1);

        assertEq(administeredAgent.getAdmin(0),   admin);
        assertEq(administeredAgent.getActor(0),   relayer);
        assertEq(administeredAgent.getRevoker(0), freezer);

        assertEq(administeredAgent.getIsAdmin(deployer),              false);
        assertEq(administeredAgent.getIsAdmin(address(assembler)),    false);
        assertEq(administeredAgent.getIsAdmin(address(agentFactory)), false);
    }

    // Override to remove grantor event in staging.
    function _assertAdministeredAgentEvents() internal override {
        VmSafe.EthGetLogs[] memory logs = _getEvents(block.chainid, address(administeredAgent), "");

        assertEq(logs.length, 7);

        // Add assembler as admin
        _assertAdminAddedEvent({
            log     : logs[0],
            account : address(assembler),
            caller  : address(agentFactory)
        });

        // Add deployer as admin
        _assertAdminAddedEvent({
            log     : logs[1],
            account : deployer,
            caller  : address(assembler)
        });

        // Add relayer as actor
        _assertActorAddedEvent({
            log     : logs[2],
            account : relayer,
            caller  : address(assembler)
        });

        // Add freezer as revoker
        _assertRevokerAddedEvent({
            log     : logs[3],
            account : freezer,
            caller  : address(assembler)
        });

        // Remove assembler as admin
        _assertAdminRemovedEvent({
            log     : logs[4],
            account : address(assembler),
            caller  : address(assembler)
        });

        // Add admin as admin
        _assertAdminAddedEvent({
            log     : logs[5],
            account : admin,
            caller  : deployer
        });

        // Remove deployer as admin
        _assertAdminRemovedEvent({
            log     : logs[6],
            account : deployer,
            caller  : deployer
        });
    }

}

contract MainnetPostDeployTestsProduction is MainnetPostDeployTestsBase {

    using stdJson for string;

    function setUp() public override {
        super.setUp();

        // CCTP facet onboarding.
        XLAYER_CCTP_MINT_RECIPIENT = 0xe6D5d041Fc5e7fDD0A53C13e78a1cc7e4ffCb667;

        CCTP_MIN_FEE_CAP_RATE = 0;
        CCTP_MAX_FEE_CAP_RATE = 0;

        CCTP_TO_CCTP_USDC_MAX_AMOUNT = type(uint256).max;
        CCTP_TO_CCTP_USDC_SLOPE      = 0;

        CCTP_TO_DOMAIN_USDC_MAX_AMOUNT = 10_000_000e6;
        CCTP_TO_DOMAIN_USDC_SLOPE      = uint256(250_000_000e6) / 1 days;

        // ERC4626 facet onboarding.
        ERC4626_USDC_MAX_AMOUNT = type(uint256).max;
        ERC4626_USDC_SLOPE      = 0;

        _setUpAddresses(vm.readFile("deployments/full-pau/mainnet-production.json"));
    }

    function _getBlock() internal override pure returns (uint256) {
        return 25955579;
    }

}

