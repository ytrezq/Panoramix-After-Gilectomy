// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { stdJson }  from "../../../lib/forge-std/src/StdJson.sol";

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IERC20 }   from "../../lib/forge-std/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../lib/forge-std/src/interfaces/IERC4626.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";
import { XLayer }   from "../../lib/spark-address-registry/src/XLayer.sol";

import { Bridge, BridgeType }    from "../../lib/diamond-pau/lib/grove-xchain-helpers/src/testing/Bridge.sol";
import { CCTPv2BridgeTesting }   from "../../lib/diamond-pau/lib/grove-xchain-helpers/src/testing/bridges/CCTPv2BridgeTesting.sol";
import { CCTPv2Forwarder }       from "../../lib/diamond-pau/lib/grove-xchain-helpers/src/forwarders/CCTPv2Forwarder.sol";
import { Domain, DomainHelpers } from "../../lib/diamond-pau/lib/grove-xchain-helpers/src/testing/Domain.sol";

import { IRateLimits } from "../../lib/diamond-pau/src/interfaces/IRateLimits.sol";

import { IForeignControllerFull } from "../../lib/diamond-pau/test/interfaces/IForeignControllerFull.sol";
import { IMainnetControllerFull } from "../../lib/diamond-pau/test/interfaces/IMainnetControllerFull.sol";

import { IAdministeredAgent } from "../../lib/pau-administered-agent/src/interfaces/IAdministeredAgent.sol";

interface ISparkVaultLike is IERC4626 {

    function TAKER_ROLE() external view returns (bytes32);

    function SETTER_ROLE() external view returns (bytes32);

    function depositCap() external view returns (uint256);

    function grantRole(bytes32 role, address account) external;

    function hasRole(bytes32 role, address account) external view returns (bool);

    function setDepositCap(uint256 newCap) external;

    function setVsrBounds(uint256 minVsr, uint256 maxVsr) external;

    function setVsr(uint256 vsr) external;

}

abstract contract CrossChainE2ETestBase is Test {

    using DomainHelpers       for *;
    using CCTPv2BridgeTesting for Bridge;

    uint256 internal DEPOSIT_AMOUNT;
    uint256 internal TAKE_RATE_LIMIT_MAX_AMOUNT;
    uint256 internal CCTP_RATE_LIMIT_MAX_AMOUNT;
    uint256 internal CCTP_DOMAIN_RATE_LIMIT_MAX_AMOUNT;
    uint256 internal TRANSFER_RATE_LIMIT_MAX_AMOUNT;
    uint256 internal DEPOSIT_RATE_LIMIT_MAX_AMOUNT;
    uint256 internal WITHDRAW_RATE_LIMIT_MAX_AMOUNT;

    uint32 internal ETHEREUM_CCTP_DOMAIN;
    uint32 internal XLAYER_CCTP_DOMAIN;

    address internal ADMIN;
    address internal CCTP_MESSAGE_TRANSMITTER;
    address internal XLAYER_RELAYER;
    address internal XLAYER_ALM_PROXY;
    address internal MAINNET_RELAYER;
    address internal MAINNET_ALM_PROXY;

    Bridge internal bridge;
    Domain internal mainnet;
    Domain internal xlayer;

    IAdministeredAgent     internal xlayerAgent;
    IForeignControllerFull internal xlayerController;
    IRateLimits            internal xlayerRateLimits;
    ISparkVaultLike        internal spusdc;
    IERC20                 internal xlayerUsdc;

    IAdministeredAgent     internal mainnetAgent;
    IMainnetControllerFull internal mainnetController;
    IRateLimits            internal mainnetRateLimits;
    IERC4626               internal susdc;
    IERC20                 internal usdc;

    address internal user = makeAddr("user");

    function setUp() public virtual {
        setChain("xlayer", ChainData({
            name    : "XLayer",
            rpcUrl  : "https://rpc.xlayer.tech",
            chainId : 196
        }));
    }

}

contract CrossChainE2ETestStaging is CrossChainE2ETestBase {

    using DomainHelpers       for *;
    using CCTPv2BridgeTesting for Bridge;
    using stdJson for string;

    /**********************************************************************************************/
    /*** Setup                                                                                  ***/
    /**********************************************************************************************/

    function setUp() public override {
        super.setUp();

        string memory mainnetJson = vm.readFile("deployments/full-pau/mainnet-staging.json");
        string memory xlayerJson  = vm.readFile("deployments/full-pau/xlayer-staging.json");

        DEPOSIT_AMOUNT                    = 5e6;
        TAKE_RATE_LIMIT_MAX_AMOUNT        = 10e6;
        CCTP_RATE_LIMIT_MAX_AMOUNT        = 10e6;
        CCTP_DOMAIN_RATE_LIMIT_MAX_AMOUNT = 10e6;
        TRANSFER_RATE_LIMIT_MAX_AMOUNT    = 10e6;
        DEPOSIT_RATE_LIMIT_MAX_AMOUNT     = 10e6;
        WITHDRAW_RATE_LIMIT_MAX_AMOUNT    = 10e6;

        ADMIN                    = mainnetJson.readAddress(".admin");
        CCTP_MESSAGE_TRANSMITTER = CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ETHEREUM;

        ETHEREUM_CCTP_DOMAIN = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM;
        XLAYER_CCTP_DOMAIN   = 37;

        XLAYER_RELAYER   = xlayerJson.readAddress(".relayer");
        XLAYER_ALM_PROXY = xlayerJson.readAddress(".proxy");

        MAINNET_RELAYER   = mainnetJson.readAddress(".relayer");
        MAINNET_ALM_PROXY = mainnetJson.readAddress(".proxy");

        xlayerAgent      = IAdministeredAgent(xlayerJson.readAddress(".administeredAgent"));
        xlayerController = IForeignControllerFull(xlayerJson.readAddress(".controller"));
        xlayerRateLimits = IRateLimits(xlayerJson.readAddress(".rateLimits"));
        spusdc           = ISparkVaultLike(xlayerJson.readAddress(".spUSDC"));
        xlayerUsdc       = IERC20(XLayer.USDC);

        mainnetAgent      = IAdministeredAgent(mainnetJson.readAddress(".administeredAgent"));
        mainnetController = IMainnetControllerFull(mainnetJson.readAddress(".controller"));
        mainnetRateLimits = IRateLimits(mainnetJson.readAddress(".rateLimits"));
        susdc             = IERC4626(Ethereum.SUSDC);
        usdc              = IERC20(Ethereum.USDC);

        mainnet = getChain("mainnet").createSelectFork(25941444); // September 9, 2026
        xlayer  = getChain("xlayer").createSelectFork(70207535);  // September 9, 2026

        bridge = CCTPv2BridgeTesting.init(Bridge({
            bridgeType                     : BridgeType.CCTP_V2,
            source                         : xlayer,
            destination                    : mainnet,
            sourceCrossChainMessenger      : CCTP_MESSAGE_TRANSMITTER,
            destinationCrossChainMessenger : CCTP_MESSAGE_TRANSMITTER,
            lastSourceLogIndex             : 0,
            lastDestinationLogIndex        : 0,
            extraData                      : ""
        }));

        vm.startPrank(ADMIN);

        // bc -l <<< 'scale=27; e( l(1.06)/(60 * 60 * 24 * 365) )'
        spusdc.setVsrBounds(1e27, 1000000001847694957439350563); // 6% APY

        spusdc.grantRole(spusdc.SETTER_ROLE(), address(xlayerAgent));

        vm.stopPrank();

        // Seed the vault with USDC
        address seeder = makeAddr("seeder");

        deal(address(xlayerUsdc), seeder, 1e6);

        vm.startPrank(seeder);
        xlayerUsdc.approve(address(spusdc), 1e6);
        spusdc.deposit(1e6, seeder);
        vm.stopPrank();
    }

    function test_e2e_roundTrip() external {
        xlayer.selectFork();

        // Step 0: Set VSR on spUSDC.
        vm.prank(XLAYER_RELAYER);
        xlayerAgent.call(
            address(spusdc),
            abi.encodeCall(spusdc.setVsr, (1000000001121484774769253326))
        );

        // Step 1: User deposits USDC into spUSDC on X Layer.

        deal(address(xlayerUsdc), user, DEPOSIT_AMOUNT);

        vm.startPrank(user);
        xlayerUsdc.approve(address(spusdc), DEPOSIT_AMOUNT);
        spusdc.deposit(DEPOSIT_AMOUNT, user);
        vm.stopPrank();

        // Step 2: Relayer takes the USDC out of spUSDC into the ALMProxy on X Layer.

        vm.prank(XLAYER_RELAYER);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.sparkVault_take, (address(spusdc), DEPOSIT_AMOUNT))
        );

        // Step 3: Relayer bridges the USDC to Ethereum with CCTP V2 (burn on X Layer).

        uint256 xlayerUsdcSupply = xlayerUsdc.totalSupply();

        vm.prank(XLAYER_RELAYER);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.cctp_transfer, (DEPOSIT_AMOUNT, ETHEREUM_CCTP_DOMAIN, 0))
        );

        // Step 4: Relay the message to Ethereum.

        mainnet.selectFork();

        bridge.relayMessagesToDestination(true);

        // Step 5: Relayer deposits the USDC into sUSDC.

        uint256 expectedShares = susdc.convertToShares(DEPOSIT_AMOUNT);

        vm.prank(MAINNET_RELAYER);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.erc4626_deposit, (Ethereum.SUSDC, DEPOSIT_AMOUNT, expectedShares))
        );

        // Step 6: Yield accrues in sUSDC.

        skip(1 days);

        xlayer.selectFork();
        skip(1 days);
        mainnet.selectFork();

        uint256 usdcWithYield = susdc.convertToAssets(expectedShares);

        assertEq(usdcWithYield, 5.000484e6);

        // Step 7: Relayer withdraws from sUSDC by redeeming every share.

        vm.prank(MAINNET_RELAYER);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.erc4626_redeem, (Ethereum.SUSDC, expectedShares, usdcWithYield))
        );

        // Step 8: Relayer bridges the USDC back to X Layer with CCTP V2 (burn on Ethereum).

        vm.prank(MAINNET_RELAYER);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.cctp_transfer, (usdcWithYield, XLAYER_CCTP_DOMAIN, 0))
        );

        // Step 9: Relay the message to X Layer.

        xlayer.selectFork();

        bridge.relayMessagesToSource(true);

        // Step 10: Relayer transfers the USDC, yield included, back into spUSDC.

        vm.prank(XLAYER_RELAYER);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.transferAsset_transfer, (address(xlayerUsdc), address(spusdc), usdcWithYield))
        );

        // Step 11: User redeems.
        vm.prank(user);
        spusdc.redeem(DEPOSIT_AMOUNT, user, user);

        assertEq(xlayerUsdc.balanceOf(user),            usdcWithYield);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), 1e6);

        assertEq(spusdc.totalAssets(),   1e6 + 96);
        assertEq(spusdc.totalSupply(),   1e6);
        assertEq(spusdc.balanceOf(user), 0);
    }

}

contract CrossChainE2ETestProduction is CrossChainE2ETestBase {

    using DomainHelpers       for *;
    using CCTPv2BridgeTesting for Bridge;
    using stdJson for string;

    /**********************************************************************************************/
    /*** Setup                                                                                  ***/
    /**********************************************************************************************/

    function setUp() public override {
        super.setUp();

        string memory mainnetJson = vm.readFile("deployments/full-pau/mainnet-production.json");
        string memory xlayerJson  = vm.readFile("deployments/full-pau/xlayer-production.json");

        CCTP_MESSAGE_TRANSMITTER = CCTPv2Forwarder.MESSAGE_TRANSMITTER_CIRCLE_ETHEREUM;

        ETHEREUM_CCTP_DOMAIN = CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM;
        XLAYER_CCTP_DOMAIN   = 37;

        XLAYER_RELAYER   = XLayer.ALM_RELAYER_MULTISIG;
        XLAYER_ALM_PROXY = XLayer.SPUSDC_PAU_ALM_PROXY;

        MAINNET_RELAYER   = Ethereum.ALM_RELAYER_MULTISIG;
        MAINNET_ALM_PROXY = Ethereum.SPUSDC_PAU_ALM_PROXY;

        xlayerAgent      = IAdministeredAgent(XLayer.SPUSDC_PAU_ADMINISTERED_AGENT);
        xlayerController = IForeignControllerFull(XLayer.SPUSDC_PAU_CONTROLLER);
        xlayerRateLimits = IRateLimits(XLayer.SPUSDC_PAU_RATELIMITS);
        spusdc           = ISparkVaultLike(XLayer.SPARK_VAULT_V2_SPUSDC);
        xlayerUsdc       = IERC20(XLayer.USDC);

        mainnetAgent      = IAdministeredAgent(Ethereum.SPUSDC_PAU_ADMINISTERED_AGENT);
        mainnetController = IMainnetControllerFull(Ethereum.SPUSDC_PAU_CONTROLLER);
        mainnetRateLimits = IRateLimits(Ethereum.SPUSDC_PAU_RATELIMITS);
        susdc             = IERC4626(Ethereum.SUSDC);
        usdc              = IERC20(Ethereum.USDC);

        mainnet = getChain("mainnet").createSelectFork(25990651); // September 16, 2026
        xlayer  = getChain("xlayer").createSelectFork(70800026);  // September 16, 2026

        bridge = CCTPv2BridgeTesting.init(Bridge({
            bridgeType                     : BridgeType.CCTP_V2,
            source                         : xlayer,
            destination                    : mainnet,
            sourceCrossChainMessenger      : CCTP_MESSAGE_TRANSMITTER,
            destinationCrossChainMessenger : CCTP_MESSAGE_TRANSMITTER,
            lastSourceLogIndex             : 0,
            lastDestinationLogIndex        : 0,
            extraData                      : ""
        }));
    }

    function test_e2e_roundTrip() external {
        xlayer.selectFork();

        // Step 0: Set VSR on spUSDC.
        vm.prank(XLAYER_RELAYER);
        xlayerAgent.call(
            address(spusdc),
            abi.encodeCall(spusdc.setVsr, (1000000001121484774769253326))
        );

        // Step 1: User deposits USDC into spUSDC on X Layer.

        deal(address(xlayerUsdc), user, 1_000_000e6);

        assertEq(xlayerUsdc.balanceOf(user),            1_000_000e6);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), 1e6);

        assertEq(spusdc.totalAssets(),   1e6);
        assertEq(spusdc.totalSupply(),   1e6);
        assertEq(spusdc.balanceOf(user), 0);

        vm.startPrank(user);
        xlayerUsdc.approve(address(spusdc), 1_000_000e6);
        spusdc.deposit(1_000_000e6, user);
        vm.stopPrank();

        assertEq(xlayerUsdc.balanceOf(user),            0);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), 1_000_000e6 + 1e6);

        assertEq(spusdc.totalAssets(),   1_000_000e6 + 1e6);
        assertEq(spusdc.totalSupply(),   1_000_000e6 + 1e6);
        assertEq(spusdc.balanceOf(user), 1_000_000e6);

        // Step 2: Relayer takes the USDC out of spUSDC into the ALMProxy on X Layer.

        bytes32 takeKey = xlayerController.sparkVault_getTakeRateLimitKey(address(spusdc));

        assertEq(xlayerRateLimits.getCurrentRateLimit(takeKey), type(uint256).max);

        assertEq(xlayerUsdc.balanceOf(XLAYER_ALM_PROXY), 0);

        vm.prank(XLAYER_RELAYER);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.sparkVault_take, (address(spusdc), 1_000_000e6))
        );

        assertEq(xlayerRateLimits.getCurrentRateLimit(takeKey), type(uint256).max);

        assertEq(xlayerUsdc.balanceOf(address(spusdc)),  1e6);
        assertEq(xlayerUsdc.balanceOf(XLAYER_ALM_PROXY), 1_000_000e6);

        // Step 3: Relayer bridges the USDC to Ethereum with CCTP V2 (burn on X Layer).

        bytes32 xlayerCctpKey       = xlayerController.cctp_toCCTPRateLimitKey();
        bytes32 xlayerCctpDomainKey = xlayerController.cctp_getToDomainRateLimitKey(ETHEREUM_CCTP_DOMAIN);

        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerCctpKey),       type(uint256).max);
        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerCctpDomainKey), 10_000_000e6);

        uint256 xlayerUsdcSupply = xlayerUsdc.totalSupply();

        vm.prank(XLAYER_RELAYER);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.cctp_transfer, (1_000_000e6, ETHEREUM_CCTP_DOMAIN, 0))
        );

        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerCctpKey),       type(uint256).max);
        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerCctpDomainKey), 9_000_000e6);

        assertEq(xlayerUsdc.balanceOf(XLAYER_ALM_PROXY), 0);
        assertEq(xlayerUsdc.totalSupply(),               xlayerUsdcSupply - 1_000_000e6);

        // Step 4: Relay the message to Ethereum.

        mainnet.selectFork();

        uint256 mainnetUsdcSupply = usdc.totalSupply();

        assertEq(usdc.balanceOf(MAINNET_ALM_PROXY), 0);

        bridge.relayMessagesToDestination(true);

        assertEq(usdc.balanceOf(MAINNET_ALM_PROXY), 1_000_000e6);
        assertEq(usdc.totalSupply(),                mainnetUsdcSupply + 1_000_000e6);

        // Step 5: Relayer deposits the USDC into sUSDC.

        bytes32 depositKey  = mainnetController.erc4626_getDepositRateLimitKey(Ethereum.SUSDC, Ethereum.USDC);
        bytes32 withdrawKey = mainnetController.erc4626_getWithdrawRateLimitKey(Ethereum.SUSDC);

        assertEq(mainnetRateLimits.getCurrentRateLimit(depositKey),  type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        uint256 expectedShares = susdc.convertToShares(1_000_000e6);

        assertEq(susdc.balanceOf(MAINNET_ALM_PROXY), 0);

        vm.prank(MAINNET_RELAYER);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.erc4626_deposit, (Ethereum.SUSDC, 1_000_000e6, expectedShares))
        );

        assertEq(mainnetRateLimits.getCurrentRateLimit(depositKey),  type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(usdc.balanceOf(MAINNET_ALM_PROXY),  0);
        assertEq(susdc.balanceOf(MAINNET_ALM_PROXY), expectedShares);

        assertApproxEqAbs(susdc.convertToAssets(expectedShares), 1_000_000e6, 1);  // Share rounding

        // Step 6: Yield accrues in sUSDC.

        skip(1 days);

        xlayer.selectFork();
        skip(1 days);
        mainnet.selectFork();

        uint256 usdcWithYield = susdc.convertToAssets(expectedShares);

        assertEq(usdcWithYield, 1_000_096.900979e6);

        // Step 7: Relayer withdraws from sUSDC by redeeming every share.

        vm.prank(MAINNET_RELAYER);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.erc4626_redeem, (Ethereum.SUSDC, expectedShares, usdcWithYield))
        );

        assertEq(mainnetRateLimits.getCurrentRateLimit(depositKey),  type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(susdc.balanceOf(MAINNET_ALM_PROXY), 0);
        assertEq(usdc.balanceOf(MAINNET_ALM_PROXY),  usdcWithYield);

        // Step 8: Relayer bridges the USDC back to X Layer with CCTP V2 (burn on Ethereum).

        bytes32 mainnetCctpKey       = mainnetController.cctp_toCCTPRateLimitKey();
        bytes32 mainnetCctpDomainKey = mainnetController.cctp_getToDomainRateLimitKey(XLAYER_CCTP_DOMAIN);

        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetCctpKey),       type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetCctpDomainKey), 10_000_000e6);

        vm.prank(MAINNET_RELAYER);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.cctp_transfer, (usdcWithYield, XLAYER_CCTP_DOMAIN, 0))
        );

        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetCctpKey),       type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetCctpDomainKey), 10_000_000e6 - usdcWithYield);

        assertEq(usdc.balanceOf(MAINNET_ALM_PROXY), 0);
        assertEq(usdc.totalSupply(),                mainnetUsdcSupply + 1_000_000e6 - usdcWithYield);

        // Step 9: Relay the message to X Layer.

        xlayer.selectFork();

        assertEq(xlayerUsdc.balanceOf(XLAYER_ALM_PROXY), 0);

        bridge.relayMessagesToSource(true);

        assertEq(xlayerUsdc.balanceOf(XLAYER_ALM_PROXY), usdcWithYield);
        assertEq(xlayerUsdc.totalSupply(),               xlayerUsdcSupply - 1_000_000e6 + usdcWithYield);

        // Step 10: Relayer transfers the USDC, yield included, back into spUSDC.

        bytes32 transferKey = xlayerController.transferAsset_getTransferRateLimitKey(address(xlayerUsdc), address(spusdc));

        assertEq(xlayerRateLimits.getCurrentRateLimit(transferKey), type(uint256).max);

        vm.prank(XLAYER_RELAYER);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.transferAsset_transfer, (address(xlayerUsdc), address(spusdc), usdcWithYield))
        );

        assertEq(xlayerRateLimits.getCurrentRateLimit(transferKey), type(uint256).max);

        assertEq(xlayerUsdc.balanceOf(XLAYER_ALM_PROXY), 0);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)),  usdcWithYield + 1e6);

        // Step 11: User redeems.
        assertEq(spusdc.totalAssets(), usdcWithYield + 1e6 + 96);  // 96 atoms accrued from yield on seeded balance

        vm.prank(user);
        spusdc.redeem(1_000_000e6, user, user);

        assertEq(xlayerUsdc.balanceOf(user),            usdcWithYield);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), 1e6);

        assertEq(spusdc.totalAssets(),   1e6 + 96);
        assertEq(spusdc.totalSupply(),   1e6);
        assertEq(spusdc.balanceOf(user), 0);
    }

}
