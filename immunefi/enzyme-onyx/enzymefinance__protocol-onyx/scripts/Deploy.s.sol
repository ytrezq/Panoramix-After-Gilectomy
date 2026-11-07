// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import {Global} from "src/global/Global.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BeaconFactory} from "src/factories/BeaconFactory.sol";
import {ComponentBeaconFactory} from "src/factories/ComponentBeaconFactory.sol";
import {Shares} from "src/shares/Shares.sol";
import {FeeHandler} from "src/components/fees/FeeHandler.sol";
import {
    ContinuousFlatRateManagementFeeTracker
} from "src/components/fees/management-fee-trackers/ContinuousFlatRateManagementFeeTracker.sol";
import {
    ContinuousFlatRatePerformanceFeeTracker
} from "src/components/fees/performance-fee-trackers/ContinuousFlatRatePerformanceFeeTracker.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {LinearCreditDebtTracker} from "src/components/value/position-trackers/LinearCreditDebtTracker.sol";
import {ERC7540LikeDepositQueue} from "src/components/issuance/deposit-handlers/ERC7540LikeDepositQueue.sol";
import {ERC7540LikeRedeemQueue} from "src/components/issuance/redeem-handlers/ERC7540LikeRedeemQueue.sol";
import {AccountERC20Tracker} from "src/components/value/position-trackers/AccountERC20Tracker.sol";
import {LimitedAccessLimitedCallForwarder} from "src/components/roles/LimitedAccessLimitedCallForwarder.sol";
import {CreWorkflowConsumer} from "src/components/automations/chainlink-cre/CreWorkflowConsumer.sol";
import {SharesOwnedAddressList} from "src/components/lists/SharesOwnedAddressList.sol";
import {OwnableAddressList} from "src/infra/lists/address-list/OwnableAddressList.sol";
import {SyncDepositHandler} from "src/components/issuance/deposit-handlers/SyncDepositHandler.sol";
import {SyncRedeemHandler} from "src/components/issuance/redeem-handlers/SyncRedeemHandler.sol";
import {SharesMintHandler} from "src/components/issuance/deposit-handlers/SharesMintHandler.sol";
import {SharesBurnHandler} from "src/components/issuance/redeem-handlers/SharesBurnHandler.sol";
import {
    AddressListsSharesTransferValidator
} from "src/components/shares-transfer-validators/AddressListsSharesTransferValidator.sol";
import {
    ChainlinkAceSharesTransferValidator
} from "src/components/shares-transfer-validators/ChainlinkAceSharesTransferValidator.sol";
import {
    ChainlinkAceSharesTransferExtractor
} from "src/components/shares-transfer-validators/ChainlinkAceSharesTransferExtractor.sol";
import {
    ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator.sol";
import {
    ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator.sol";
import {
    ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator.sol";
import {
    ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator.sol";
import {
    ChainlinkAceSyncDepositHandlerPostDepositValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceSyncDepositHandlerPostDepositValidator.sol";
import {
    ChainlinkAceSyncRedeemHandlerPostRedeemValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceSyncRedeemHandlerPostRedeemValidator.sol";
import {
    ChainlinkAceSharesMintHandlerPreMintValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceSharesMintHandlerPreMintValidator.sol";
import {
    ChainlinkAceSharesBurnHandlerPreBurnValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceSharesBurnHandlerPreBurnValidator.sol";
import {
    ChainlinkAceERC7540LikeDepositQueuePreRequestDepositExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceERC7540LikeDepositQueuePreRequestDepositExtractor.sol";
import {
    ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor.sol";
import {
    ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor.sol";
import {
    ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestExtractor.sol";
import {
    ChainlinkAceSyncDepositHandlerPostDepositExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceSyncDepositHandlerPostDepositExtractor.sol";
import {
    ChainlinkAceSyncRedeemHandlerPostRedeemExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceSyncRedeemHandlerPostRedeemExtractor.sol";
import {
    ChainlinkAceSharesMintHandlerPreMintExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceSharesMintHandlerPreMintExtractor.sol";
import {
    ChainlinkAceSharesBurnHandlerPreBurnExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceSharesBurnHandlerPreBurnExtractor.sol";
import {SharesDeployer} from "src/infra/deployment/SharesDeployer.sol";

/// @notice Deploys core Onyx protocol contracts to a target network
///         and writes their addresses to `deployments/${chainid}.json` for front-end consumption.
contract DeployProtocol is Script {
    address constant ENZYME_DEVELOPERS = address(0xd24bBcD06C54a5a2A6d22f4AaE25AB511190C7b5);

    struct Addrs {
        ERC1967Proxy globalProxy;
        Global global;
        BeaconFactory sharesBeaconFactory;
        BeaconFactory ownableAddressListFactory;
        ComponentBeaconFactory feeHandlerBeaconFactory;
        ComponentBeaconFactory continuousFlatRateManagementFeeTrackerBeaconFactory;
        ComponentBeaconFactory continuousFlatRatePerformanceFeeTrackerBeaconFactory;
        ComponentBeaconFactory valuationHandlerBeaconFactory;
        ComponentBeaconFactory accountERC20TrackerFactory;
        ComponentBeaconFactory linearCreditDebtTrackerBeaconFactory;
        ComponentBeaconFactory erc7540LikeDepositQueueBeaconFactory;
        ComponentBeaconFactory erc7540LikeRedeemQueueBeaconFactory;
        ComponentBeaconFactory limitedAccessLimitedCallForwarderFactory;
        ComponentBeaconFactory creWorkflowConsumerFactory;
        ComponentBeaconFactory sharesOwnedAddressListFactory;
        ComponentBeaconFactory syncDepositHandlerFactory;
        ComponentBeaconFactory syncRedeemHandlerFactory;
        ComponentBeaconFactory sharesMintHandlerFactory;
        ComponentBeaconFactory sharesBurnHandlerFactory;
        ComponentBeaconFactory addressListsSharesTransferValidatorFactory;
        ComponentBeaconFactory chainlinkAceDepositQueuePreRequestValidatorFactory;
        ComponentBeaconFactory chainlinkAceDepositQueuePostExecuteValidatorFactory;
        ComponentBeaconFactory chainlinkAceRedeemQueuePreRequestValidatorFactory;
        ComponentBeaconFactory chainlinkAceRedeemQueuePostExecuteValidatorFactory;
        ComponentBeaconFactory chainlinkAceSyncDepositPostDepositValidatorFactory;
        ComponentBeaconFactory chainlinkAceSyncRedeemPostRedeemValidatorFactory;
        ComponentBeaconFactory chainlinkAceMintPreMintValidatorFactory;
        ComponentBeaconFactory chainlinkAceBurnPreBurnValidatorFactory;
        ComponentBeaconFactory chainlinkAceSharesTransferValidatorFactory;
        Shares shares;
        FeeHandler feeHandler;
        ContinuousFlatRateManagementFeeTracker continuousFlatRateManagementFeeTracker;
        ContinuousFlatRatePerformanceFeeTracker continuousFlatRatePerformanceFeeTracker;
        ValuationHandler valuationHandler;
        AccountERC20Tracker accountERC20Tracker;
        LinearCreditDebtTracker linearCreditDebtTracker;
        ERC7540LikeDepositQueue erc7540LikeDepositQueue;
        ERC7540LikeRedeemQueue erc7540LikeRedeemQueue;
        LimitedAccessLimitedCallForwarder limitedAccessLimitedCallForwarder;
        CreWorkflowConsumer creWorkflowConsumer;
        SharesOwnedAddressList sharesOwnedAddressList;
        OwnableAddressList ownableAddressList;
        SyncDepositHandler syncDepositHandler;
        SyncRedeemHandler syncRedeemHandler;
        SharesMintHandler sharesMintHandler;
        SharesBurnHandler sharesBurnHandler;
        AddressListsSharesTransferValidator addressListsSharesTransferValidator;
        ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator chainlinkAceDepositQueuePreRequestValidator;
        ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator
            chainlinkAceDepositQueuePostExecuteValidator;
        ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator chainlinkAceRedeemQueuePreRequestValidator;
        ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator chainlinkAceRedeemQueuePostExecuteValidator;
        ChainlinkAceSyncDepositHandlerPostDepositValidator chainlinkAceSyncDepositPostDepositValidator;
        ChainlinkAceSyncRedeemHandlerPostRedeemValidator chainlinkAceSyncRedeemPostRedeemValidator;
        ChainlinkAceSharesMintHandlerPreMintValidator chainlinkAceMintPreMintValidator;
        ChainlinkAceSharesBurnHandlerPreBurnValidator chainlinkAceBurnPreBurnValidator;
        ChainlinkAceSharesTransferValidator chainlinkAceSharesTransferValidator;
        ChainlinkAceERC7540LikeDepositQueuePreRequestDepositExtractor chainlinkAceDepositQueuePreRequestExtractor;
        ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor
            chainlinkAceDepositQueuePostExecuteExtractor;
        ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor chainlinkAceRedeemQueuePreRequestExtractor;
        ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestExtractor chainlinkAceRedeemQueuePostExecuteExtractor;
        ChainlinkAceSyncDepositHandlerPostDepositExtractor chainlinkAceSyncDepositPostDepositExtractor;
        ChainlinkAceSyncRedeemHandlerPostRedeemExtractor chainlinkAceSyncRedeemPostRedeemExtractor;
        ChainlinkAceSharesMintHandlerPreMintExtractor chainlinkAceMintPreMintExtractor;
        ChainlinkAceSharesBurnHandlerPreBurnExtractor chainlinkAceBurnPreBurnExtractor;
        ChainlinkAceSharesTransferExtractor chainlinkAceSharesTransferExtractor;
        SharesDeployer sharesDeployer;
    }

    Addrs internal addrs;

    function run() external {
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        /* ---------------------------------------------------------------------
         * Core governance / global contract
         * -------------------------------------------------------------------*/

        // Deploy as proxy
        addrs.global = new Global();
        addrs.globalProxy = new ERC1967Proxy({
            implementation: address(addrs.global), _data: abi.encodeWithSelector(Global.init.selector, deployer)
        });

        /* ---------------------------------------------------------------------
         * Factories (upgrade beacons)
         * -------------------------------------------------------------------*/
        addrs.sharesBeaconFactory = new BeaconFactory(address(addrs.globalProxy));
        addrs.ownableAddressListFactory = new BeaconFactory(address(addrs.globalProxy));
        // Create specialized beacon factories for each component type
        addrs.feeHandlerBeaconFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.continuousFlatRateManagementFeeTrackerBeaconFactory =
            new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.continuousFlatRatePerformanceFeeTrackerBeaconFactory =
            new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.accountERC20TrackerFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.linearCreditDebtTrackerBeaconFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.valuationHandlerBeaconFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.erc7540LikeDepositQueueBeaconFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.erc7540LikeRedeemQueueBeaconFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.limitedAccessLimitedCallForwarderFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        address chainlinkKeystoneForwarder = __getChainlinkKeystoneForwarder();
        bool isChainlinkKeystoneForwarderAvailable = chainlinkKeystoneForwarder != address(0);
        if (isChainlinkKeystoneForwarderAvailable) {
            addrs.creWorkflowConsumerFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        }
        addrs.sharesOwnedAddressListFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.syncDepositHandlerFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.syncRedeemHandlerFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.sharesMintHandlerFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.sharesBurnHandlerFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.addressListsSharesTransferValidatorFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.chainlinkAceDepositQueuePreRequestValidatorFactory =
            new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.chainlinkAceDepositQueuePostExecuteValidatorFactory =
            new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.chainlinkAceRedeemQueuePreRequestValidatorFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.chainlinkAceRedeemQueuePostExecuteValidatorFactory =
            new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.chainlinkAceSyncDepositPostDepositValidatorFactory =
            new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.chainlinkAceSyncRedeemPostRedeemValidatorFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.chainlinkAceMintPreMintValidatorFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.chainlinkAceBurnPreBurnValidatorFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.chainlinkAceSharesTransferValidatorFactory = new ComponentBeaconFactory(address(addrs.globalProxy));

        /* ---------------------------------------------------------------------
         * Implementation contracts
         * -------------------------------------------------------------------*/
        addrs.shares = new Shares();
        addrs.feeHandler = new FeeHandler();
        addrs.continuousFlatRateManagementFeeTracker = new ContinuousFlatRateManagementFeeTracker();
        addrs.continuousFlatRatePerformanceFeeTracker = new ContinuousFlatRatePerformanceFeeTracker();
        addrs.valuationHandler = new ValuationHandler();
        addrs.accountERC20Tracker = new AccountERC20Tracker();
        addrs.linearCreditDebtTracker = new LinearCreditDebtTracker();
        addrs.erc7540LikeDepositQueue = new ERC7540LikeDepositQueue();
        addrs.erc7540LikeRedeemQueue = new ERC7540LikeRedeemQueue();
        addrs.limitedAccessLimitedCallForwarder = new LimitedAccessLimitedCallForwarder();
        if (isChainlinkKeystoneForwarderAvailable) {
            addrs.creWorkflowConsumer = new CreWorkflowConsumer(chainlinkKeystoneForwarder, ENZYME_DEVELOPERS);
        }
        addrs.sharesOwnedAddressList = new SharesOwnedAddressList();
        addrs.ownableAddressList = new OwnableAddressList();
        addrs.syncDepositHandler = new SyncDepositHandler();
        addrs.syncRedeemHandler = new SyncRedeemHandler();
        addrs.sharesMintHandler = new SharesMintHandler();
        addrs.sharesBurnHandler = new SharesBurnHandler();
        addrs.addressListsSharesTransferValidator = new AddressListsSharesTransferValidator();
        addrs.chainlinkAceDepositQueuePreRequestValidator =
            new ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator();
        addrs.chainlinkAceDepositQueuePostExecuteValidator =
            new ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator();
        addrs.chainlinkAceRedeemQueuePreRequestValidator =
            new ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator();
        addrs.chainlinkAceRedeemQueuePostExecuteValidator =
            new ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator();
        addrs.chainlinkAceSyncDepositPostDepositValidator = new ChainlinkAceSyncDepositHandlerPostDepositValidator();
        addrs.chainlinkAceSyncRedeemPostRedeemValidator = new ChainlinkAceSyncRedeemHandlerPostRedeemValidator();
        addrs.chainlinkAceMintPreMintValidator = new ChainlinkAceSharesMintHandlerPreMintValidator();
        addrs.chainlinkAceBurnPreBurnValidator = new ChainlinkAceSharesBurnHandlerPreBurnValidator();
        addrs.chainlinkAceSharesTransferValidator = new ChainlinkAceSharesTransferValidator();

        /* ---------------------------------------------------------------------
         * Chainlink ACE extractors
         * (stateless singletons)
         * -------------------------------------------------------------------*/
        addrs.chainlinkAceDepositQueuePreRequestExtractor =
            new ChainlinkAceERC7540LikeDepositQueuePreRequestDepositExtractor();
        addrs.chainlinkAceDepositQueuePostExecuteExtractor =
            new ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor();
        addrs.chainlinkAceRedeemQueuePreRequestExtractor =
            new ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor();
        addrs.chainlinkAceRedeemQueuePostExecuteExtractor =
            new ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestExtractor();
        addrs.chainlinkAceSyncDepositPostDepositExtractor = new ChainlinkAceSyncDepositHandlerPostDepositExtractor();
        addrs.chainlinkAceSyncRedeemPostRedeemExtractor = new ChainlinkAceSyncRedeemHandlerPostRedeemExtractor();
        addrs.chainlinkAceMintPreMintExtractor = new ChainlinkAceSharesMintHandlerPreMintExtractor();
        addrs.chainlinkAceBurnPreBurnExtractor = new ChainlinkAceSharesBurnHandlerPreBurnExtractor();
        addrs.chainlinkAceSharesTransferExtractor = new ChainlinkAceSharesTransferExtractor();

        /* ---------------------------------------------------------------------
         * Set implementations
         * -------------------------------------------------------------------*/
        // Set implementations for each specialized beacon factory
        addrs.sharesBeaconFactory.setImplementation(address(addrs.shares));
        addrs.feeHandlerBeaconFactory.setImplementation(address(addrs.feeHandler));
        addrs.continuousFlatRateManagementFeeTrackerBeaconFactory
            .setImplementation(address(addrs.continuousFlatRateManagementFeeTracker));
        addrs.continuousFlatRatePerformanceFeeTrackerBeaconFactory
            .setImplementation(address(addrs.continuousFlatRatePerformanceFeeTracker));
        addrs.accountERC20TrackerFactory.setImplementation(address(addrs.accountERC20Tracker));
        addrs.linearCreditDebtTrackerBeaconFactory.setImplementation(address(addrs.linearCreditDebtTracker));
        addrs.valuationHandlerBeaconFactory.setImplementation(address(addrs.valuationHandler));
        addrs.erc7540LikeDepositQueueBeaconFactory.setImplementation(address(addrs.erc7540LikeDepositQueue));
        addrs.erc7540LikeRedeemQueueBeaconFactory.setImplementation(address(addrs.erc7540LikeRedeemQueue));
        addrs.limitedAccessLimitedCallForwarderFactory
            .setImplementation(address(addrs.limitedAccessLimitedCallForwarder));
        if (isChainlinkKeystoneForwarderAvailable) {
            addrs.creWorkflowConsumerFactory.setImplementation(address(addrs.creWorkflowConsumer));
        }
        addrs.sharesOwnedAddressListFactory.setImplementation(address(addrs.sharesOwnedAddressList));
        addrs.ownableAddressListFactory.setImplementation(address(addrs.ownableAddressList));
        addrs.syncDepositHandlerFactory.setImplementation(address(addrs.syncDepositHandler));
        addrs.syncRedeemHandlerFactory.setImplementation(address(addrs.syncRedeemHandler));
        addrs.sharesMintHandlerFactory.setImplementation(address(addrs.sharesMintHandler));
        addrs.sharesBurnHandlerFactory.setImplementation(address(addrs.sharesBurnHandler));
        addrs.addressListsSharesTransferValidatorFactory
            .setImplementation(address(addrs.addressListsSharesTransferValidator));
        addrs.chainlinkAceDepositQueuePreRequestValidatorFactory
            .setImplementation(address(addrs.chainlinkAceDepositQueuePreRequestValidator));
        addrs.chainlinkAceDepositQueuePostExecuteValidatorFactory
            .setImplementation(address(addrs.chainlinkAceDepositQueuePostExecuteValidator));
        addrs.chainlinkAceRedeemQueuePreRequestValidatorFactory
            .setImplementation(address(addrs.chainlinkAceRedeemQueuePreRequestValidator));
        addrs.chainlinkAceRedeemQueuePostExecuteValidatorFactory
            .setImplementation(address(addrs.chainlinkAceRedeemQueuePostExecuteValidator));
        addrs.chainlinkAceSyncDepositPostDepositValidatorFactory
            .setImplementation(address(addrs.chainlinkAceSyncDepositPostDepositValidator));
        addrs.chainlinkAceSyncRedeemPostRedeemValidatorFactory
            .setImplementation(address(addrs.chainlinkAceSyncRedeemPostRedeemValidator));
        addrs.chainlinkAceMintPreMintValidatorFactory.setImplementation(address(addrs.chainlinkAceMintPreMintValidator));
        addrs.chainlinkAceBurnPreBurnValidatorFactory.setImplementation(address(addrs.chainlinkAceBurnPreBurnValidator));
        addrs.chainlinkAceSharesTransferValidatorFactory
            .setImplementation(address(addrs.chainlinkAceSharesTransferValidator));

        /* ---------------------------------------------------------------------
         * Shares deployer
         * -------------------------------------------------------------------*/
        addrs.sharesDeployer = new SharesDeployer(
            SharesDeployer.Factories({
                sharesFactory: address(addrs.sharesBeaconFactory),
                feeHandlerFactory: address(addrs.feeHandlerBeaconFactory),
                valuationHandlerFactory: address(addrs.valuationHandlerBeaconFactory),
                managementFeeTrackerFactory: address(addrs.continuousFlatRateManagementFeeTrackerBeaconFactory),
                performanceFeeTrackerFactory: address(addrs.continuousFlatRatePerformanceFeeTrackerBeaconFactory),
                accountERC20TrackerFactory: address(addrs.accountERC20TrackerFactory),
                linearCreditDebtTrackerFactory: address(addrs.linearCreditDebtTrackerBeaconFactory),
                depositQueueFactory: address(addrs.erc7540LikeDepositQueueBeaconFactory),
                syncDepositHandlerFactory: address(addrs.syncDepositHandlerFactory),
                syncRedeemHandlerFactory: address(addrs.syncRedeemHandlerFactory),
                redeemQueueFactory: address(addrs.erc7540LikeRedeemQueueBeaconFactory),
                sharesOwnedAddressListFactory: address(addrs.sharesOwnedAddressListFactory),
                ownableAddressListFactory: address(addrs.ownableAddressListFactory),
                addressListsSharesTransferValidatorFactory: address(addrs.addressListsSharesTransferValidatorFactory),
                sharesMintHandlerFactory: address(addrs.sharesMintHandlerFactory),
                sharesBurnHandlerFactory: address(addrs.sharesBurnHandlerFactory),
                aceDepositQueuePreRequestValidatorFactory: address(
                    addrs.chainlinkAceDepositQueuePreRequestValidatorFactory
                ),
                aceDepositQueuePostExecuteValidatorFactory: address(
                    addrs.chainlinkAceDepositQueuePostExecuteValidatorFactory
                ),
                aceRedeemQueuePreRequestValidatorFactory: address(
                    addrs.chainlinkAceRedeemQueuePreRequestValidatorFactory
                ),
                aceRedeemQueuePostExecuteValidatorFactory: address(
                    addrs.chainlinkAceRedeemQueuePostExecuteValidatorFactory
                ),
                aceSyncDepositPostDepositValidatorFactory: address(
                    addrs.chainlinkAceSyncDepositPostDepositValidatorFactory
                ),
                aceSyncRedeemPostRedeemValidatorFactory: address(
                    addrs.chainlinkAceSyncRedeemPostRedeemValidatorFactory
                ),
                aceMintPreMintValidatorFactory: address(addrs.chainlinkAceMintPreMintValidatorFactory),
                aceBurnPreBurnValidatorFactory: address(addrs.chainlinkAceBurnPreBurnValidatorFactory),
                aceSharesTransferValidatorFactory: address(addrs.chainlinkAceSharesTransferValidatorFactory),
                limitedAccessLimitedCallForwarderFactory: address(addrs.limitedAccessLimitedCallForwarderFactory),
                creWorkflowConsumerFactory: address(addrs.creWorkflowConsumerFactory)
            })
        );

        vm.stopBroadcast();

        __writeDeploymentArtifacts();
    }

    function __writeDeploymentArtifacts() private {
        string memory key = "deploy";
        vm.serializeAddress(key, "GlobalProxy", address(addrs.globalProxy));
        vm.serializeAddress(key, "Global", address(addrs.global));
        vm.serializeAddress(key, "SharesFactory", address(addrs.sharesBeaconFactory));
        vm.serializeAddress(key, "FeeHandlerFactory", address(addrs.feeHandlerBeaconFactory));
        vm.serializeAddress(
            key,
            "ContinuousFlatRateManagementFeeTrackerFactory",
            address(addrs.continuousFlatRateManagementFeeTrackerBeaconFactory)
        );
        vm.serializeAddress(
            key,
            "ContinuousFlatRatePerformanceFeeTrackerFactory",
            address(addrs.continuousFlatRatePerformanceFeeTrackerBeaconFactory)
        );
        vm.serializeAddress(key, "ValuationHandlerFactory", address(addrs.valuationHandlerBeaconFactory));
        vm.serializeAddress(key, "AccountERC20TrackerFactory", address(addrs.accountERC20TrackerFactory));
        vm.serializeAddress(key, "LinearCreditDebtTrackerFactory", address(addrs.linearCreditDebtTrackerBeaconFactory));
        vm.serializeAddress(key, "ERC7540LikeDepositQueueFactory", address(addrs.erc7540LikeDepositQueueBeaconFactory));
        vm.serializeAddress(key, "ERC7540LikeRedeemQueueFactory", address(addrs.erc7540LikeRedeemQueueBeaconFactory));
        vm.serializeAddress(
            key, "LimitedAccessLimitedCallForwarderFactory", address(addrs.limitedAccessLimitedCallForwarderFactory)
        );
        vm.serializeAddress(key, "SharesOwnedAddressListFactory", address(addrs.sharesOwnedAddressListFactory));
        vm.serializeAddress(key, "OwnableAddressListFactory", address(addrs.ownableAddressListFactory));
        vm.serializeAddress(key, "SyncDepositHandlerFactory", address(addrs.syncDepositHandlerFactory));
        vm.serializeAddress(key, "SyncRedeemHandlerFactory", address(addrs.syncRedeemHandlerFactory));
        vm.serializeAddress(key, "SharesMintHandlerFactory", address(addrs.sharesMintHandlerFactory));
        vm.serializeAddress(key, "SharesBurnHandlerFactory", address(addrs.sharesBurnHandlerFactory));
        vm.serializeAddress(
            key, "AddressListsSharesTransferValidatorFactory", address(addrs.addressListsSharesTransferValidatorFactory)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidatorFactory",
            address(addrs.chainlinkAceDepositQueuePreRequestValidatorFactory)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidatorFactory",
            address(addrs.chainlinkAceDepositQueuePostExecuteValidatorFactory)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidatorFactory",
            address(addrs.chainlinkAceRedeemQueuePreRequestValidatorFactory)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidatorFactory",
            address(addrs.chainlinkAceRedeemQueuePostExecuteValidatorFactory)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceSyncDepositHandlerPostDepositValidatorFactory",
            address(addrs.chainlinkAceSyncDepositPostDepositValidatorFactory)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceSyncRedeemHandlerPostRedeemValidatorFactory",
            address(addrs.chainlinkAceSyncRedeemPostRedeemValidatorFactory)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceSharesMintHandlerPreMintValidatorFactory",
            address(addrs.chainlinkAceMintPreMintValidatorFactory)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceSharesBurnHandlerPreBurnValidatorFactory",
            address(addrs.chainlinkAceBurnPreBurnValidatorFactory)
        );
        vm.serializeAddress(
            key, "ChainlinkAceSharesTransferValidatorFactory", address(addrs.chainlinkAceSharesTransferValidatorFactory)
        );
        vm.serializeAddress(key, "SharesLib", address(addrs.shares));
        vm.serializeAddress(key, "FeeHandlerLib", address(addrs.feeHandler));
        vm.serializeAddress(
            key, "ContinuousFlatRateManagementFeeTrackerLib", address(addrs.continuousFlatRateManagementFeeTracker)
        );
        vm.serializeAddress(
            key, "ContinuousFlatRatePerformanceFeeTrackerLib", address(addrs.continuousFlatRatePerformanceFeeTracker)
        );
        vm.serializeAddress(key, "ValuationHandlerLib", address(addrs.valuationHandler));
        vm.serializeAddress(key, "AccountERC20TrackerLib", address(addrs.accountERC20Tracker));
        vm.serializeAddress(key, "LinearCreditDebtTrackerLib", address(addrs.linearCreditDebtTracker));
        vm.serializeAddress(key, "ERC7540LikeDepositQueueLib", address(addrs.erc7540LikeDepositQueue));
        vm.serializeAddress(key, "ERC7540LikeRedeemQueueLib", address(addrs.erc7540LikeRedeemQueue));
        vm.serializeAddress(
            key, "LimitedAccessLimitedCallForwarderLib", address(addrs.limitedAccessLimitedCallForwarder)
        );
        vm.serializeAddress(key, "SharesOwnedAddressListLib", address(addrs.sharesOwnedAddressList));
        vm.serializeAddress(key, "OwnableAddressListLib", address(addrs.ownableAddressList));
        vm.serializeAddress(key, "SyncDepositHandlerLib", address(addrs.syncDepositHandler));
        vm.serializeAddress(key, "SyncRedeemHandlerLib", address(addrs.syncRedeemHandler));
        vm.serializeAddress(key, "SharesMintHandlerLib", address(addrs.sharesMintHandler));
        vm.serializeAddress(key, "SharesBurnHandlerLib", address(addrs.sharesBurnHandler));
        vm.serializeAddress(
            key, "AddressListsSharesTransferValidatorLib", address(addrs.addressListsSharesTransferValidator)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidatorLib",
            address(addrs.chainlinkAceDepositQueuePreRequestValidator)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidatorLib",
            address(addrs.chainlinkAceDepositQueuePostExecuteValidator)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidatorLib",
            address(addrs.chainlinkAceRedeemQueuePreRequestValidator)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidatorLib",
            address(addrs.chainlinkAceRedeemQueuePostExecuteValidator)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceSyncDepositHandlerPostDepositValidatorLib",
            address(addrs.chainlinkAceSyncDepositPostDepositValidator)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceSyncRedeemHandlerPostRedeemValidatorLib",
            address(addrs.chainlinkAceSyncRedeemPostRedeemValidator)
        );
        vm.serializeAddress(
            key, "ChainlinkAceSharesMintHandlerPreMintValidatorLib", address(addrs.chainlinkAceMintPreMintValidator)
        );
        vm.serializeAddress(
            key, "ChainlinkAceSharesBurnHandlerPreBurnValidatorLib", address(addrs.chainlinkAceBurnPreBurnValidator)
        );
        vm.serializeAddress(
            key, "ChainlinkAceSharesTransferValidatorLib", address(addrs.chainlinkAceSharesTransferValidator)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceERC7540LikeDepositQueuePreRequestDepositExtractor",
            address(addrs.chainlinkAceDepositQueuePreRequestExtractor)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestExtractor",
            address(addrs.chainlinkAceDepositQueuePostExecuteExtractor)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemExtractor",
            address(addrs.chainlinkAceRedeemQueuePreRequestExtractor)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestExtractor",
            address(addrs.chainlinkAceRedeemQueuePostExecuteExtractor)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceSyncDepositHandlerPostDepositExtractor",
            address(addrs.chainlinkAceSyncDepositPostDepositExtractor)
        );
        vm.serializeAddress(
            key,
            "ChainlinkAceSyncRedeemHandlerPostRedeemExtractor",
            address(addrs.chainlinkAceSyncRedeemPostRedeemExtractor)
        );
        vm.serializeAddress(
            key, "ChainlinkAceSharesMintHandlerPreMintExtractor", address(addrs.chainlinkAceMintPreMintExtractor)
        );
        vm.serializeAddress(
            key, "ChainlinkAceSharesBurnHandlerPreBurnExtractor", address(addrs.chainlinkAceBurnPreBurnExtractor)
        );
        vm.serializeAddress(
            key, "ChainlinkAceSharesTransferExtractor", address(addrs.chainlinkAceSharesTransferExtractor)
        );
        vm.serializeAddress(key, "CreWorkflowConsumerFactory", address(addrs.creWorkflowConsumerFactory));
        vm.serializeAddress(key, "CreWorkflowConsumerLib", address(addrs.creWorkflowConsumer));
        string memory json = vm.serializeAddress(key, "SharesDeployer", address(addrs.sharesDeployer));

        vm.createDir("./deploy", true);
        string memory path = string.concat("./deploy/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console2.log("Deployment artifacts written to", path);
    }

    function __getChainlinkKeystoneForwarder() private view returns (address) {
        // Ethereum
        if (block.chainid == 1) {
            return 0x0b93082D9b3C7C97fAcd250082899BAcf3af3885;
        }

        // Arbitrum
        if (block.chainid == 42161) {
            return 0xF8344CFd5c43616a4366C34E3EEE75af79a74482;
        }

        // Base
        if (block.chainid == 8453) {
            return 0xF8344CFd5c43616a4366C34E3EEE75af79a74482;
        }

        // Avalanche
        if (block.chainid == 43114) {
            return 0x76c9cf548b4179F8901cda1f8623568b58215E62;
        }

        // BNB Smart Chain
        if (block.chainid == 56) {
            return 0x76c9cf548b4179F8901cda1f8623568b58215E62;
        }

        // Ethereum Sepolia
        if (block.chainid == 11155111) {
            return 0xF8344CFd5c43616a4366C34E3EEE75af79a74482;
        }

        // MegaETH
        if (block.chainid == 4326) {
            return 0x7BCcaFBD064cB3658476066Cc33ceE3F3414c04c;
        }

        return address(0);
    }
}
