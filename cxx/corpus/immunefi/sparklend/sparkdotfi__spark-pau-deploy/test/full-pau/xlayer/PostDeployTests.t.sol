// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { stdJson }  from "../../../lib/forge-std/src/StdJson.sol";

import { XLayer } from "../../../lib/spark-address-registry/src/XLayer.sol";

import { IEnumerableIntegrations as IEI } from "../../../lib/diamond-pau/src/interfaces/IEnumerableIntegrations.sol";

import { PostDeployTestBaseFull } from "../PostDeployTestBaseFull.t.sol";

interface ISparkVaultLike {

    function TAKER_ROLE() external view returns (bytes32);

    function hasRole(bytes32 role, address account) external view returns (bool);

}

abstract contract XLayerPostDeployTestsBase is PostDeployTestBaseFull {

    bytes32 internal constant CCTP_FACET_ID           = "CCTP_FACET";
    bytes32 internal constant TRANSFER_ASSET_FACET_ID = "TRANSFER_ASSET_FACET";
    bytes32 internal constant SPARK_VAULT_FACET_ID    = "SPARK_VAULT_FACET";

    uint32 internal constant ETHEREUM_CCTP_DOMAIN = 0;

    address internal constant USDC = XLayer.USDC;

    address internal ETHEREUM_CCTP_MINT_RECIPIENT;

    uint32  internal CCTP_MIN_FEE_CAP_RATE;
    uint32  internal CCTP_MAX_FEE_CAP_RATE;

    uint256 internal CCTP_TO_CCTP_USDC_MAX_AMOUNT;
    uint256 internal CCTP_TO_CCTP_USDC_SLOPE;

    uint256 internal CCTP_TO_DOMAIN_USDC_MAX_AMOUNT;
    uint256 internal CCTP_TO_DOMAIN_USDC_SLOPE;

    uint256 internal TRANSFER_ASSET_USDC_MAX_AMOUNT;
    uint256 internal TRANSFER_ASSET_USDC_SLOPE;

    address internal SPUSDC;

    uint256 internal SPARK_VAULT_USDC_MAX_AMOUNT;
    uint256 internal SPARK_VAULT_USDC_SLOPE;

    function setUp() public virtual override {
        super.setUp();

        vm.createSelectFork(getChain("xlayer").rpcUrl, _getBlock());
    }

    function _getBlock() internal virtual pure returns (uint256) {
        return 0;
    }

    function test_administeredAgentState() external view {
        _assertAdministeredAgentState();
    }

    function test_accessControlsState() external view {
        _assertAccessControlsState();
    }

    function test_almProxyState() external view {
        _assertALMProxyState();
    }

    function test_rateLimitsState() external view {
        _assertRateLimitsInitializationState();
    }

    function test_controllerState() external view {
        _assertControllerInitializationState();
    }

    function test_rateLimitsAndControllerOnboardingState() external view {
        // 0. Controller Integrations
        IEI.Integration[] memory integrations = controller.integrations();

        assertEq(integrations.length, 3);

        assertEq(integrations[0].id, CCTP_FACET_ID);
        assertEq(integrations[1].id, TRANSFER_ASSET_FACET_ID);
        assertEq(integrations[2].id, SPARK_VAULT_FACET_ID);

        for (uint256 i = 0; i < integrations.length; i++) {
            _assertIntegration(integrations[i].id);
        }

        // 1. CCTP facet onboarding

        // 1a. Controller state
        (
            bytes32 mintRecipient,
            uint32  minFeeCapRate,
            uint32  maxFeeCapRate
        ) = controller.cctp_getDomainParameters(ETHEREUM_CCTP_DOMAIN);

        assertEq(mintRecipient, bytes32(uint256(uint160(ETHEREUM_CCTP_MINT_RECIPIENT))));
        assertEq(minFeeCapRate, CCTP_MIN_FEE_CAP_RATE);
        assertEq(maxFeeCapRate, CCTP_MAX_FEE_CAP_RATE);

        // 1b. Rate limits state

        _assertRateLimitData(controller.cctp_toCCTPRateLimitKey(),                          CCTP_TO_CCTP_USDC_MAX_AMOUNT,   CCTP_TO_CCTP_USDC_SLOPE);
        _assertRateLimitData(controller.cctp_getToDomainRateLimitKey(ETHEREUM_CCTP_DOMAIN), CCTP_TO_DOMAIN_USDC_MAX_AMOUNT, CCTP_TO_DOMAIN_USDC_SLOPE);

        // 2. TransferAsset facet onboarding

        // 2a. Controller state (No controller state changes to assert, the transferred asset is
        //     the USDC that the CCTP facet mints on this chain)
        assertEq(controller.cctp_usdc(), USDC);

        // 2b. Rate limits state

        _assertRateLimitData(controller.transferAsset_getTransferRateLimitKey(USDC, SPUSDC), TRANSFER_ASSET_USDC_MAX_AMOUNT, TRANSFER_ASSET_USDC_SLOPE);

        // 3. SparkVault facet onboarding

        // 3a. Spark vault state
        assertEq(ISparkVaultLike(SPUSDC).hasRole(ISparkVaultLike(SPUSDC).TAKER_ROLE(), address(almProxy)), true);

        // 3b. Rate limits state

        _assertRateLimitData(controller.sparkVault_getTakeRateLimitKey(SPUSDC), SPARK_VAULT_USDC_MAX_AMOUNT, SPARK_VAULT_USDC_SLOPE);
    }

}

contract XLayerPostDeployTestsStaging is XLayerPostDeployTestsBase {

    using stdJson for string;

    function setUp() public override {
        super.setUp();

        string memory json = vm.readFile("deployments/full-pau/xlayer-staging.json");

        // CCTP facet onboarding.
        ETHEREUM_CCTP_MINT_RECIPIENT = 0x5A7e6fF9A4836275b469C7413fA40294661A2017;

        CCTP_MIN_FEE_CAP_RATE = 0;
        CCTP_MAX_FEE_CAP_RATE = 100;

        CCTP_TO_CCTP_USDC_MAX_AMOUNT = 10e6;
        CCTP_TO_CCTP_USDC_SLOPE      = uint256(100e6) / 1 hours;

        CCTP_TO_DOMAIN_USDC_MAX_AMOUNT = 10e6;
        CCTP_TO_DOMAIN_USDC_SLOPE      = uint256(100e6) / 1 hours;

        // TransferAsset facet onboarding.
        TRANSFER_ASSET_USDC_MAX_AMOUNT = 10e6;
        TRANSFER_ASSET_USDC_SLOPE      = uint256(100e6) / 1 hours;

        // SparkVault onboarding.
        SPUSDC = json.readAddress(".spUSDC");

        SPARK_VAULT_USDC_MAX_AMOUNT = 10e6;
        SPARK_VAULT_USDC_SLOPE      = uint256(100e6) / 1 hours;

        _setUpAddresses(json);
    }

    function _getBlock() internal override pure returns (uint256) {
        return 70207296;
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

}

contract XLayerPostDeployTestsProduction is XLayerPostDeployTestsBase {

    using stdJson for string;

    function setUp() public override {
        super.setUp();

        string memory json = vm.readFile("deployments/full-pau/xlayer-production.json");

        // CCTP facet onboarding.
        ETHEREUM_CCTP_MINT_RECIPIENT = 0x8D719A830b00e5571db00D173505CD56c0Ec224a;

        CCTP_MIN_FEE_CAP_RATE = 0;
        CCTP_MAX_FEE_CAP_RATE = 0;

        CCTP_TO_CCTP_USDC_MAX_AMOUNT = type(uint256).max;
        CCTP_TO_CCTP_USDC_SLOPE      = 0;

        CCTP_TO_DOMAIN_USDC_MAX_AMOUNT = 10_000_000e6;
        CCTP_TO_DOMAIN_USDC_SLOPE      = uint256(250_000_000e6) / 1 days;

        // TransferAsset facet onboarding.
        TRANSFER_ASSET_USDC_MAX_AMOUNT = type(uint256).max;
        TRANSFER_ASSET_USDC_SLOPE      = 0;

        // SparkVault onboarding.
        SPUSDC = json.readAddress(".spUSDC");

        SPARK_VAULT_USDC_MAX_AMOUNT = type(uint256).max;
        SPARK_VAULT_USDC_SLOPE      = 0;

        _setUpAddresses(json);
    }

    function _getBlock() internal override pure returns (uint256) {
        return 70378331;
    }

}

