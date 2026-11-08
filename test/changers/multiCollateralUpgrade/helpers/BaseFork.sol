// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IgnitionDeployments } from "./IgnitionDeployments.sol";
import { MocRif } from "../../../../contracts/MocRif.sol";
import { MocQueue } from "moc-main-latest/contracts/queue/MocQueue.sol";
import { MocMultiCollateralGuard } from "moc-main-latest/contracts/multiCollateral/MocMultiCollateralGuard.sol";
import { MultiCollateralUpgradeChanger } from "../../../../contracts/changers/multiCollateralUpgrade/MultiCollateralUpgradeChanger.sol";
import { MocQueueExecFees } from "moc-main-latest/contracts/queue/MocQueueExecFees.sol";
import { MocRC20 } from "moc-main-latest/contracts/tokens/MocRC20.sol";
import { MocCARC20 } from "moc-main-latest/contracts/collateral/rc20/MocCARC20.sol";
import { IChangeContract } from "moc-main-latest/contracts/interfaces/IChangeContract.sol";
import { IGovernor } from "moc-main-latest/contracts/interfaces/IGovernor.sol";
import { IPriceProvider } from "moc-main-latest/contracts/interfaces/IPriceProvider.sol";
import { DataProvider } from "../../../../contracts/providers/DataProvider.sol";
import { CommissionSplitterRC20 } from "moc-main-latest/contracts/auxiliary/CommissionSplitterRC20.sol";
import { MocReverseAuction } from "moc-main-latest/contracts/auxiliary/MocReverseAuction.sol";

/// @title Fork Tests with Ignition Deployed Contracts
/// @notice Fork tests that use contracts deployed by Hardhat Ignition on mainnet
contract BaseFork is IgnitionDeployments {
    // ============ Constants ============
    uint256 constant MAX_UINT = type(uint256).max;
    uint256 constant BLOCK_SPAN = 24;
    uint256 constant BASE_FEE = 1;

    // RSK Mainnet addresses
    address constant GOVERNOR_ADDRESS = 0x3b8853DF65AfBd94853E6D77ee0Ab5590F41bB08;
    address constant GOVERNOR_OWNER = 0x65a5681bE95d212F0c90eAd40170D8277de81169;
    address constant PAUSER_ADDRESS = 0x40662eD57284B4B541A42D347BE2447ABd1b119d;

    // RSK Mainnet holder address (already has RIF and TC tokens)
    address constant HOLDER_ADDRESS = 0xe4822F07C1d988A8f2F53D1817f7e8848897b67A;
    address constant VENDOR = 0xd249E2275A6ed216432f167c3393f6F72e09eF49;

    // RSK Mainnet MocCore (MocRif) proxy address
    address constant MOC_CORE_ADDRESS = 0xA27024Ed70035E46dba712609fc2Afa1c97aA36A;

    // RSK Mainnet RIF Token address (Collateral Asset)
    address constant RIF_TOKEN_ADDRESS = 0x2AcC95758f8b5F583470ba265EB685a8F45fC9D5;

    // ============ State Variables ============
    MocRif public rifBucket;
    MocQueue public rifQueue;
    IMocQueueLegacy public rifQueueOld;
    MocMultiCollateralGuard public mocMultiCollateralGuard;
    MocRC20 public rifToken;
    MocRC20 public rifProToken;
    MocRC20 public usdRifToken;
    MultiCollateralUpgradeChanger public changer;
    MocCARC20 public docBucket;
    MocQueue public docQueue;
    MocRC20 public docToken;
    MocRC20 public docProToken;
    MocRC20 public mocToken;

    CommissionSplitterRC20 public feeFlow;
    MocReverseAuction public reverseAuctionDocToMoc;
    MocReverseAuction public reverseAuctionMocToDoc;
    address public rocrRewardsBuffer;

    IPriceProvider rifPriceProvider;
    IPriceProvider rbtcUsdPriceProvider;
    DataProvider rifToDocMaxAmountProvider;

    // Test account
    address public holder;

    uint256 public executeTimestamp;
    uint256 public executeBlockNumber;

    /// @notice Load contracts deployed by Ignition
    function _loadIgnitionContracts() internal {
        // Get MultiCollateralUpgradeChanger
        address changerAddr = getDeployedAddress("MultiCollateral_MultiCollateralUpgradeChanger");
        require(changerAddr != address(0), "MultiCollateralUpgradeChanger not deployed");
        changer = MultiCollateralUpgradeChanger(changerAddr);

        // Get MocQueue (new)
        address queueAddr = getDeployedAddress("MultiCollateral_MocQueueProxy");
        require(queueAddr != address(0), "MocQueueProxy not deployed");
        rifQueue = MocQueue(payable(queueAddr));

        // Get MocMultiCollateralGuard
        address guardAddr = getDeployedAddress("MultiCollateral_MocMultiCollateralGuardProxy");
        require(guardAddr != address(0), "MocMultiCollateralGuardProxy not deployed");
        mocMultiCollateralGuard = MocMultiCollateralGuard(payable(guardAddr));

        // Get DocBucket
        address docBucketAddr = getDeployedAddress("DocBucket_DocBucketProxy");
        require(docBucketAddr != address(0), "DocBucketProxy not deployed");
        docBucket = MocCARC20(payable(docBucketAddr));

        address reverseAuctionDocToMocAddr = getDeployedAddress("FeeFlow_ReverseAuctionDOCtoMOC");
        require(reverseAuctionDocToMocAddr != address(0), "ReverseAuctionDOCtoMOC not deployed");
        reverseAuctionDocToMoc = MocReverseAuction(payable(reverseAuctionDocToMocAddr));

        address reverseAuctionMocToDocAddr = getDeployedAddress("FeeFlow_ReverseAuctionMOCtoDOC");
        require(reverseAuctionMocToDocAddr != address(0), "ReverseAuctionMOCtoDOC not deployed");
        reverseAuctionMocToDoc = MocReverseAuction(payable(reverseAuctionMocToDocAddr));

        rocrRewardsBuffer = getDeployedAddress("FeeFlow_RocrRewardsBuffer");
        require(rocrRewardsBuffer != address(0), "RocrRewardsBuffer not deployed");

        address rifPriceProviderAddr = getDeployedAddress("MultiCollateral_RifPriceProvider");
        require(rifPriceProviderAddr != address(0), "RifPriceProvider not deployed");
        rifPriceProvider = IPriceProvider(rifPriceProviderAddr);

        address rifToRbtcPriceProviderAddr = getDeployedAddress("MultiCollateral_RifToRbtcPriceProvider");
        require(rifToRbtcPriceProviderAddr != address(0), "RifToRbtcPriceProvider not deployed");
        rbtcUsdPriceProvider = IPriceProvider(
            address(IPriceProviderDiv(rifToRbtcPriceProviderAddr)._priceProviderDivisor())
        );

        address rifToDocMaxAmountProviderAddr = getDeployedAddress("Swappers_RifToDocMaxAmountProvider");
        require(rifToDocMaxAmountProviderAddr != address(0), "RifToDocMaxAmountProvider not deployed");
        rifToDocMaxAmountProvider = DataProvider(rifToDocMaxAmountProviderAddr);
    }

    function setUp() public virtual {
        // Prefer explicit FORK_URL. If not provided, fallback to RSK mainnet RPC.
        string memory defaultMainnetForkUrl = vm.envOr("RSK_MAINNET_RPC_URL", string("https://public-node.rsk.co"));
        string memory forkUrl = vm.envOr("FORK_URL", defaultMainnetForkUrl);
        vm.createSelectFork(forkUrl, 8830500);

        // Load deployed addresses from Ignition
        _loadDeployedAddresses();

        // Check if we have the deployed contracts
        require(
            addressesLoaded,
            "Deployed addresses not loaded. Check ignition/deployments/chain-30/deployed_addresses.json"
        );

        // Initialize the MocRif bucket from mainnet
        rifBucket = MocRif(payable(MOC_CORE_ADDRESS));

        // Get token addresses from the bucket
        rifToken = MocRC20(address(rifBucket.acToken()));
        rifProToken = MocRC20(address(rifBucket.tcToken()));
        usdRifToken = MocRC20(address(rifBucket.tpTokens(0)));

        // Store the current (old) queue reference
        rifQueueOld = IMocQueueLegacy(rifBucket.mocQueue());

        // Get deployed contracts from Ignition
        _loadIgnitionContracts();
        _mockRbtcUsdPriceProvider();

        docToken = MocRC20(address(docBucket.acToken()));
        docProToken = MocRC20(address(docBucket.tcToken()));
        docQueue = MocQueue(payable(docBucket.mocQueue()));

        mocToken = MocRC20(address(rifBucket.feeToken()));
        feeFlow = CommissionSplitterRC20(payable(docBucket.mocFeeFlowAddress()));

        // Use the real mainnet holder
        holder = HOLDER_ADDRESS;
        vm.deal(holder, 100 ether);
        vm.deal(GOVERNOR_OWNER, 100 ether);

        // set base fee
        vm.fee(BASE_FEE);

        // Fund holder with RIF tokens
        _fundHolderWithRIF(holder, 100000 ether);
        // Fund holder with DOC tokens
        _fundHolderWithDOC(holder, 100000 ether);

        vm.startPrank(holder);
        rifToken.approve(address(rifBucket), 100000 ether);
        rifProToken.approve(address(rifBucket), 100000 ether);
        usdRifToken.approve(address(rifBucket), 100000 ether);
        docToken.approve(address(docBucket), 100000 ether);
        docProToken.approve(address(docBucket), 100000 ether);
        usdRifToken.approve(address(docBucket), 100000 ether);
        vm.stopPrank();
    }

    // ============ Helper Functions ============

    /// @notice Execute the changer through governance
    function _executeChanger() internal {
        IGovernor governor = IGovernor(address(rifBucket.governor()));

        vm.prank(GOVERNOR_OWNER);
        governor.executeChange(IChangeContract(address(changer)));

        executeTimestamp = block.timestamp;
        executeBlockNumber = block.number;
    }

    /// @notice Helper to fund a holder with RIF tokens
    function _fundHolderWithRIF(address holderAddr, uint256 amount) internal {
        deal(address(rifToken), holderAddr, amount);
    }

    /// @notice Helper to fund a holder with DOC tokens
    function _fundHolderWithDOC(address holderAddr, uint256 amount) internal {
        deal(address(docToken), holderAddr, amount);
    }

    /// @notice Keep RBTC/USD provider stable across all tests
    function _mockRbtcUsdPriceProvider() internal {
        bytes memory data = abi.encodeWithSelector(IPriceProvider.peek.selector);
        (bytes32 price, ) = rbtcUsdPriceProvider.peek();
        vm.mockCall(address(rbtcUsdPriceProvider), data, abi.encode(price, true));
    }

    /// @notice Helper to get execution cost for an operation type
    function _getExecCost(MocQueue mocQueue, MocQueueExecFees.OperType operType_) internal view returns (uint256) {
        return mocQueue.execCost(operType_) * block.basefee;
    }

    /// @notice Helper to get max of two values
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}

/// @dev Interface for legacy MocCore to access block-based settlement (bns = block number settlement)
interface IMocCoreLegacy {
    function bns() external view returns (uint256);
    function bes() external view returns (uint256);
    function nextEmaCalculation() external view returns (uint256);
    function nextTCInterestPayment() external view returns (uint256);
    function emaCalculationBlockSpan() external view returns (uint256);
    function tcInterestPaymentBlockSpan() external view returns (uint256);
    function decayBlockSpan() external view returns (uint256);
}

/// @dev Interface for legacy MocQueue (single-collateral) that uses execFee instead of execCost
interface IMocQueueLegacy {
    function execFee(MocQueueExecFees.OperType operType_) external view returns (uint256);
    function minOperWaitingBlk() external view returns (uint256);
    function operIdCount() external view returns (uint256);
    function execute(address executionFeeRecipient) external;
}

interface IPriceProviderDiv {
    function _priceProviderDivisor() external view returns (IPriceProvider);
}

struct PegContainerItem {
    // total supply of Pegged Token
    uint256 nTP;
    // PegToken PriceFeed address
    IPriceProvider priceProvider;
}
