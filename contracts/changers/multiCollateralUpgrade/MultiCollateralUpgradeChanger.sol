// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IChangeContract } from "moc-main-latest/contracts/interfaces/IChangeContract.sol";
import { IDataProvider } from "moc-main-latest/contracts/interfaces/IDataProvider.sol";
import { IPriceProvider } from "moc-main-latest/contracts/interfaces/IPriceProvider.sol";
import { IMocSwapper } from "moc-main-latest/contracts/interfaces/IMocSwapper.sol";
import { MocRif } from "../../MocRif.sol";
import { PeggedTokenParams } from "moc-main-latest/contracts/core/MocCommons.sol";
import { MocQueue } from "moc-main-latest/contracts/queue/MocQueue.sol";
import { MocMultiCollateralGuard } from "moc-main-latest/contracts/multiCollateral/MocMultiCollateralGuard.sol";
import { BucketParams } from "moc-main-latest/contracts/multiCollateral/MocMultiCollateralBase.sol";
import { MocRC20 } from "moc-main-latest/contracts/tokens/MocRC20.sol";
import { MocCARC20 } from "moc-main-latest/contracts/collateral/rc20/MocCARC20.sol";
import { MocReverseAuction } from "moc-main-latest/contracts/auxiliary/MocReverseAuction.sol";

interface IGovernedRegistry {
    function pushAddressArrayElement(bytes32 _key, address _addr) external;
    function addressArrayContains(bytes32 _key, address value) external view returns (bool);
    function setAddress(bytes32 _key, address _value) external;
    function getAddress(bytes32 _key) external view returns (address);
}

/**
  @title MultiCollateralUpgradeChanger
  @notice This contract is a ChangeContract intended to be used with Moc Aeropulus 
  governance system.
  @dev 1. Upgrade MocRif to a new implementation with the multicollateral feature
       2. Upgrade USDRif to a new implementation that supports multicollateral
       3. Migrate MocQueueRif. A migration is needed because there are breaking changes
            We are not enforcing that old queue is empty to execute this changer. We are gonna
            manage that off-chain. If for any reason the queue is not empty, those pending operations
            will be handled independently on a new changer.
       4. Migrate time trackers that uses block.number to timestamps
       5. Set the new price provider for USDRif that has the getLastPublicationBlock() function implemented
       6. Add DOC bucket with USDRif pegged token to MocMultiCollateralGuard
 */
contract MultiCollateralUpgradeChanger is IChangeContract {
    // ------- Custom Errors -------
    error InvalidSetting();

    // ------- Constants -------
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 private constant BURNER_ROLE = keccak256("BURNER_ROLE");
    // keccak256("MOC_FLOW\1\REVERSE_AUCTIONS")
    bytes32 private constant MOC_FLOW_REVERSE_AUCTIONS =
        0x0428ec087e0cce276a71d1caf1afe4da32a2d48b3ebe579040612b5bd262ff73;
    // keccak256("moc.multi-collateral-guard")
    bytes32 private constant MOC_MULTI_COLLATERAL_GUARD =
        0xe703515d757b84b6a6bd1314e6613eb3ea7ece4815e828061398853f8b3d6b1a;
    // MOC_FLOW_BUFFERS = keccak256(MOC_FLOW\1\BUFFERS)
    bytes32 public constant MOC_FLOW_BUFFERS = 0x4cb845794d5472a713e41e8e4ddc566dab8d695f1dc6c8edd43dad9d55112a22;

    // ------- Storage -------
    // USDRIF proxy contract to be upgraded
    MocRC20 public immutable usdRifProxy;
    // address of the USDRIF implementation contract the proxy will delegate to
    address public immutable usdRifNewImplementation;
    // MocRif proxy contract to be upgraded
    MocRif public immutable rifBucket;
    // address of the MocRif implementation contract the proxy will delegate to
    address public immutable mocRifImplementation;
    // address of the new MocCoreExpansion contract implementation
    address public immutable mocMocCoreExpansionImplementation;
    // new MocQueueRif proxy contract
    MocQueue public immutable newMocQueueRifProxy;
    // MocMultiCollateralGuardProxy proxy contract
    MocMultiCollateralGuard public immutable mocMultiCollateralGuardProxy;
    // new rif/usd price provider
    address public immutable newPriceProvider;
    // block span in seconds
    uint256 public blockSpan;
    // DOC bucket (MocCARC20) to be added to MocMultiCollateralGuard
    MocCARC20 public immutable docBucket;
    // Rebalance params for RIF bucket
    BucketParams public rifBucketParams;
    // Rebalance params for DOC bucket
    BucketParams public docBucketParams;
    // MocSwapper for RIF/DOC pair (only one swapper needed for 2 buckets)
    IMocSwapper public immutable rifDocMocSwapper;
    // New protected threshold for RIF bucket
    uint256 public immutable rifNewProtectedThrld;
    // usdRif params for DOC bucket
    PeggedTokenParams public usdRifParamsForDocBucket;
    // Moc shared governed registry
    IGovernedRegistry public immutable governedRegistry;
    // reverse auction DOC -> MOC
    address public immutable reverseAuctionDOCtoMOC;
    // reverse auction MOC -> DOC
    address public immutable reverseAuctionMOCtoDOC;
    // ROCR rewards buffer
    address public immutable rocrRewardsBuffer;

    /** 
      @notice Constructor
      @param rifBucket_ address of the proxy to be upgraded
      @param mocRifImplementation_ address of the contract the proxy will delegate to
      @param usdRifNewImplementation_ address of the TP contract the proxy will delegate to
      @param mocMocCoreExpansionImplementation_ Address of the new MocCoreExpansion implementation
      @param newMocQueueRifProxy_ address of the new MocQueue proxy
      @param newPriceProvider_ address of the new price provider
      @param blockSpan_ block span in seconds
      @param docBucket_ address of the DOC bucket (MocCARC20) to be added to MocMultiCollateralGuard
      @param rifBucketParams_ rebalance params for RIF bucket
      @param docBucketParams_ rebalance params for DOC bucket
      @param rifDocMocSwapper_ MocSwapper for RIF/DOC pair
      @param rifNewProtectedThrld_ new protected threshold for RIF bucket [PREC]
      @param usdRifParamsForDocBucket_ usdRif params for DOC bucket
      @param governedRegistry_ moc/shared governed registry
      @param reverseAuctionDOCtoMOC_ reverse auction to register under MOC_FLOW_REVERSE_AUCTIONS
      @param reverseAuctionMOCtoDOC_ reverse auction whose output account is updated to docBucket
      @param rocrRewardsBuffer_ ROCR rewards buffer to register in governed registry
    */
    constructor(
        MocRif rifBucket_,
        address mocRifImplementation_,
        address usdRifNewImplementation_,
        address mocMocCoreExpansionImplementation_,
        MocQueue newMocQueueRifProxy_,
        address newPriceProvider_,
        uint256 blockSpan_,
        MocCARC20 docBucket_,
        BucketParams memory rifBucketParams_,
        BucketParams memory docBucketParams_,
        IMocSwapper rifDocMocSwapper_,
        uint256 rifNewProtectedThrld_,
        PeggedTokenParams memory usdRifParamsForDocBucket_,
        IGovernedRegistry governedRegistry_,
        address reverseAuctionDOCtoMOC_,
        address reverseAuctionMOCtoDOC_,
        address rocrRewardsBuffer_
    ) {
        rifBucket = rifBucket_;
        mocRifImplementation = mocRifImplementation_;
        usdRifNewImplementation = usdRifNewImplementation_;
        mocMocCoreExpansionImplementation = mocMocCoreExpansionImplementation_;
        newMocQueueRifProxy = newMocQueueRifProxy_;
        mocMultiCollateralGuardProxy = newMocQueueRifProxy.mocMultiCollateralGuard();
        usdRifProxy = MocRC20(address(rifBucket.tpTokens(0)));
        newPriceProvider = newPriceProvider_;
        blockSpan = blockSpan_;
        docBucket = docBucket_;
        rifBucketParams = rifBucketParams_;
        docBucketParams = docBucketParams_;
        rifDocMocSwapper = rifDocMocSwapper_;
        rifNewProtectedThrld = rifNewProtectedThrld_;
        usdRifParamsForDocBucket = usdRifParamsForDocBucket_;
        governedRegistry = governedRegistry_;
        reverseAuctionDOCtoMOC = reverseAuctionDOCtoMOC_;
        reverseAuctionMOCtoDOC = reverseAuctionMOCtoDOC_;
        rocrRewardsBuffer = rocrRewardsBuffer_;

        // reverts if some parameter is wrong
        verifySettings();
    }

    /**
      @notice Execute the changes.
      @dev Should be called by the governor, but this contract does not check that explicitly
      because it is not its responsibility in the current architecture
      IMPORTANT: This function should not be overridden, you should only redefine
      _beforeUpgrade and _afterUpgrade methods to use this template
    */
    function execute() external {
        _beforeUpgrade();
        _upgrade();
        _afterUpgrade();
    }

    /**
      @notice Upgrade the proxy to the newImplementation
      @dev IMPORTANT: This function should not be overridden
    */
    function _upgrade() internal {
        rifBucket.upgradeTo(mocRifImplementation);
        usdRifProxy.upgradeTo(usdRifNewImplementation);
    }

    /**
      @notice Intended to prepare the system for the upgrade
    */
    function _beforeUpgrade() internal {
        // Initialize new Rif MocQueue OperationId with current values, to maintain continuity
        MocQueue legacyMocQueueRifProxy = MocQueue(rifBucket.mocQueue());
        uint256 currentOperIdCount = legacyMocQueueRifProxy.operIdCount();
        newMocQueueRifProxy.initOperId(currentOperIdCount, currentOperIdCount);
    }

    /**
      @notice Intended to do the final tweaks after the upgrade, for example initialize the contract
    */
    function _afterUpgrade() internal {
        //set new MocQueue to MocCore
        rifBucket.setMocQueue(payable(address(newMocQueueRifProxy)));
        // set new MocCoreExpansion to MocCore
        rifBucket.setMocCoreExpansion(mocMocCoreExpansionImplementation);
        // register MocCore on MocQueue
        newMocQueueRifProxy.registerBucket(rifBucket);

        // register RIF bucket (base bucket) on MocMultiCollateralGuard with empty swappers
        IMocSwapper[] memory emptySwappers;
        mocMultiCollateralGuardProxy.addBucket(rifBucket, rifBucketParams, emptySwappers);

        // migrate block numbers to timestamps
        uint256 nextEmaCalculation = convertNextBlockToTimestamp(rifBucket.nextEmaCalculation());
        uint256 nextTCInterestPayment = convertNextBlockToTimestamp(rifBucket.nextTCInterestPayment());
        uint256 nextSettlementTime = convertNextBlockToTimestamp(rifBucket.nextSettlementTime());
        uint256 lastOperationTimeStamp = block.timestamp; // simplify the logic setting current timestamp

        rifBucket.migrateTimestamps(
            nextEmaCalculation,
            nextTCInterestPayment,
            nextSettlementTime,
            lastOperationTimeStamp
        );
        rifBucket.setFluxCapacitorParams(
            address(rifBucket.maxAbsoluteOpProvider()),
            address(rifBucket.maxOpDiffProvider()),
            rifBucket.decayTimeSpan() * blockSpan
        );
        rifBucket.setEmaCalculationTimeSpan(rifBucket.emaCalculationTimeSpan() * blockSpan);
        rifBucket.setTCInterestParams(
            rifBucket.tcInterestCollectorAddress(),
            rifBucket.tcInterestRate(),
            rifBucket.tcInterestPaymentTimeSpan() * blockSpan
        );
        rifBucket.setSettlementTimeSpan(rifBucket.settlementTimeSpan() * blockSpan);
        rifBucket.setCoverageThresholds(rifNewProtectedThrld, rifBucket.liqThrld());

        // edit USDRif pegged token to set the new price provider
        (, uint256 emaSf) = rifBucket.tpEma(0);
        PeggedTokenParams memory peggedTokenParams = PeggedTokenParams({
            priceProviderAddress: newPriceProvider,
            tpCtarg: rifBucket.tpCtarg(0),
            tpMintFee: rifBucket.tpMintFees(address(usdRifProxy)),
            tpRedeemFee: rifBucket.tpRedeemFees(address(usdRifProxy)),
            tpEma: 0, // Emma is not editable, only initialized
            tpEmaSf: emaSf
        });
        rifBucket.editPeggedToken(usdRifProxy, peggedTokenParams);

        ///////////////////////////////////////////////////////////////
        /////// BEGIN Add DOC bucket to MocMultiCollateralGuard ///////
        ///////////////////////////////////////////////////////////////

        // Doc bucket is deployed with no MocMultiCollateralGuard, set it
        MocQueue(docBucket.mocQueue()).setMocMultiCollateralGuard(mocMultiCollateralGuardProxy);
        // Doc bucket is deployed with no registered bucket, register it
        MocQueue(docBucket.mocQueue()).registerBucket(docBucket);

        // Add DOC bucket with USDRif pegged token to MocMultiCollateralGuard
        docBucket.addPeggedToken(usdRifProxy, usdRifParamsForDocBucket);
        // Grant MINTER and BURNER roles to the DOC bucket so it can mint/burn USDRif
        usdRifProxy.grantRole(MINTER_ROLE, address(docBucket));
        usdRifProxy.grantRole(BURNER_ROLE, address(docBucket));

        // Register DOC bucket on MocMultiCollateralGuard with the RIF/DOC swapper
        IMocSwapper[] memory docSwappers = new IMocSwapper[](1);
        docSwappers[0] = rifDocMocSwapper;
        mocMultiCollateralGuardProxy.addBucket(docBucket, docBucketParams, docSwappers);

        // Update MOC->DOC reverse auction output account to the deployed DOC bucket
        MocReverseAuction(payable(reverseAuctionMOCtoDOC)).setOutputAccount(address(docBucket));

        // Set MocMultiCollateralGuard and new reverse auction to the governed registry
        governedRegistry.setAddress(MOC_MULTI_COLLATERAL_GUARD, address(mocMultiCollateralGuardProxy));
        governedRegistry.pushAddressArrayElement(MOC_FLOW_REVERSE_AUCTIONS, reverseAuctionDOCtoMOC);
        governedRegistry.pushAddressArrayElement(MOC_FLOW_REVERSE_AUCTIONS, reverseAuctionMOCtoDOC);
        governedRegistry.pushAddressArrayElement(MOC_FLOW_BUFFERS, rocrRewardsBuffer);

        // reverts if some parameter is wrong
        verifySettings();
    }

    /** 
    @notice convert next block to next timestamp
    @param nextBlock_ next block to convert
    @return nextTimestamp_ next timestamp
  */
    function convertNextBlockToTimestamp(uint256 nextBlock_) public view returns (uint256 nextTimestamp_) {
        if (block.number >= nextBlock_) return block.timestamp;
        uint256 remainingBlocks = nextBlock_ - block.number;
        return block.timestamp + (remainingBlocks * blockSpan);
    }

    /**
      @notice verifies the most importat the configuration params. Reverts if somethings is wrong
    */
    function verifySettings() public view {
        address governor = address(rifBucket.governor());
        address pauser = rifBucket.pauser();
        // verify governor
        if (governor != address(newMocQueueRifProxy.governor())) revert InvalidSetting();
        if (governor != address(mocMultiCollateralGuardProxy.governor())) revert InvalidSetting();
        if (governor != address(docBucket.governor())) revert InvalidSetting();
        if (governor != address(MocQueue(docBucket.mocQueue()).governor())) revert InvalidSetting();

        // verify pauser
        if (pauser != newMocQueueRifProxy.pauser()) revert InvalidSetting();
        if (pauser != mocMultiCollateralGuardProxy.pauser()) revert InvalidSetting();
        if (pauser != docBucket.pauser()) revert InvalidSetting();
        if (pauser != MocQueue(docBucket.mocQueue()).pauser()) revert InvalidSetting();

        // verify new price provider implements getLastPublicationBlock()
        IPriceProvider(newPriceProvider).getLastPublicationBlock();
    }
}
