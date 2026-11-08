// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BeaconFactory} from "src/factories/BeaconFactory.sol";
import {ComponentBeaconFactory} from "src/factories/ComponentBeaconFactory.sol";
import {CreWorkflowConsumer} from "src/components/automations/chainlink-cre/CreWorkflowConsumer.sol";
import {FeeHandler} from "src/components/fees/FeeHandler.sol";
import {
    ContinuousFlatRateManagementFeeTracker
} from "src/components/fees/management-fee-trackers/ContinuousFlatRateManagementFeeTracker.sol";
import {
    ContinuousFlatRatePerformanceFeeTracker
} from "src/components/fees/performance-fee-trackers/ContinuousFlatRatePerformanceFeeTracker.sol";
import {ERC7540LikeDepositQueue} from "src/components/issuance/deposit-handlers/ERC7540LikeDepositQueue.sol";
import {SharesMintHandler} from "src/components/issuance/deposit-handlers/SharesMintHandler.sol";
import {SyncDepositHandler} from "src/components/issuance/deposit-handlers/SyncDepositHandler.sol";
import {
    ChainlinkAceIssuanceValidatorBase
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceIssuanceValidatorBase.sol";
import {ERC7540LikeRedeemQueue} from "src/components/issuance/redeem-handlers/ERC7540LikeRedeemQueue.sol";
import {SyncRedeemHandler} from "src/components/issuance/redeem-handlers/SyncRedeemHandler.sol";
import {SharesBurnHandler} from "src/components/issuance/redeem-handlers/SharesBurnHandler.sol";
import {LimitedAccessLimitedCallForwarder} from "src/components/roles/LimitedAccessLimitedCallForwarder.sol";
import {
    AddressListsSharesTransferValidator
} from "src/components/shares-transfer-validators/AddressListsSharesTransferValidator.sol";
import {
    ChainlinkAceSharesTransferValidator
} from "src/components/shares-transfer-validators/ChainlinkAceSharesTransferValidator.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {AccountERC20Tracker} from "src/components/value/position-trackers/AccountERC20Tracker.sol";
import {AddressListBase} from "src/infra/lists/address-list/AddressListBase.sol";
import {OwnableAddressList} from "src/infra/lists/address-list/OwnableAddressList.sol";
import {Shares} from "src/shares/Shares.sol";

/// @title SharesDeployer Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Single-transaction deployment of a fully-configured Onyx vault (Shares + components)
/// @dev Stateless after construction; safe to call permissionlessly.
/// `Shares` is initialized with this contract as owner while components are wired. After wiring,
/// `transferOwnership(config.nominatedOwner)` runs (Ownable2Step pending). The nominee must call `Shares.acceptOwnership()` to complete the handover.
///
/// Automations: each `DeployConfig.automations` entry gets its own `CreWorkflowConsumer` and its own
/// `LimitedAccessLimitedCallForwarder`. The forwarder is made a Shares admin, the consumer is its only user, and the
/// configured call permissions are added to it. The consumer's workflow ID is never set here: the automation stays
/// inert until the vault owner (or an admin) authorizes a workflow via `CreWorkflowConsumer.setAllowedWorkflowId()`.
contract SharesDeployer {
    using SafeERC20 for IERC20;

    //==================================================================================================================
    // Types
    //==================================================================================================================

    struct Factories {
        address sharesFactory;
        address feeHandlerFactory;
        address valuationHandlerFactory;
        address managementFeeTrackerFactory;
        address performanceFeeTrackerFactory;
        address accountERC20TrackerFactory;
        address linearCreditDebtTrackerFactory;
        address depositQueueFactory;
        address syncDepositHandlerFactory;
        address syncRedeemHandlerFactory;
        address redeemQueueFactory;
        address sharesOwnedAddressListFactory;
        address ownableAddressListFactory;
        address addressListsSharesTransferValidatorFactory;
        address sharesMintHandlerFactory;
        address sharesBurnHandlerFactory;
        address aceDepositQueuePreRequestValidatorFactory;
        address aceDepositQueuePostExecuteValidatorFactory;
        address aceRedeemQueuePreRequestValidatorFactory;
        address aceRedeemQueuePostExecuteValidatorFactory;
        address aceSyncDepositPostDepositValidatorFactory;
        address aceSyncRedeemPostRedeemValidatorFactory;
        address aceMintPreMintValidatorFactory;
        address aceBurnPreBurnValidatorFactory;
        address aceSharesTransferValidatorFactory;
        address limitedAccessLimitedCallForwarderFactory;
        /// @dev Zero on chains without a Chainlink Keystone forwarder; automations are then unavailable.
        address creWorkflowConsumerFactory;
    }

    /// @dev How the shares transfer validator should be sourced.
    /// `None`: no transfer validator.
    /// `Existing`: use the address provided in the config.
    /// `DeployAddressLists`: deploy a fresh `AddressListsSharesTransferValidator` and configure its lists.
    /// `DeployChainlinkAce`: deploy a fresh `ChainlinkAceSharesTransferValidator` attached to `chainlinkAcePolicyEngine`.
    enum TransferValidatorSource {
        None,
        Existing,
        DeployAddressLists,
        DeployChainlinkAce
    }

    /// @dev How a handler hook slot should be sourced.
    /// `None`: no hook.
    /// `Existing`: use the address provided in the config.
    /// `DeployChainlinkAce`: deploy the slot's Chainlink ACE validator, attached to `policyEngine`.
    enum HookSource {
        None,
        Existing,
        DeployChainlinkAce
    }

    /// @dev Configures one handler hook slot.
    struct HookConfig {
        HookSource source;
        /// @dev Required when `source == Existing`; ignored otherwise.
        address existingHook;
        /// @dev Required when `source == DeployChainlinkAce`; ignored otherwise.
        address policyEngine;
    }

    /// @dev How an external address list should be sourced when restriction/source so requires.
    /// `None`: no external list.
    /// `Existing`: use the address provided in the config.
    /// `SharedAddressList`: use a list from `DeployConfig.sharedAddressLists` at `sharedAddressListIndex`.
    enum ExternalListSource {
        None,
        Existing,
        SharedAddressList
    }

    /// @dev Kind of list deployed for a catalog entry in `DeployConfig.sharedAddressLists`.
    enum SharedAddressListKind {
        SharesOwned,
        Ownable
    }

    /// @dev One list to deploy once; referenced by consumers via `ExternalListSource.SharedAddressList`.
    struct SharedAddressListDefinition {
        SharedAddressListKind kind;
        /// @dev Required when `kind == Ownable`; ignored for `SharesOwned`.
        address ownableListOwner;
        address[] seededAddresses;
    }

    struct SharesConfig {
        string name;
        string symbol;
        bytes32 valueAsset;
    }

    struct FeeHandlerConfig {
        bool deploy;
        address feeAsset;
        uint16 entranceFeeBps;
        address entranceFeeRecipient;
        uint16 exitFeeBps;
        address exitFeeRecipient;
    }

    struct ManagementFeeConfig {
        bool deploy;
        uint16 feeBps;
        address recipient;
    }

    struct PerformanceFeeConfig {
        bool deploy;
        uint16 feeBps;
        int16 hurdleRateBps;
        address recipient;
    }

    struct ValuationHandlerConfig {
        bool deploy;
        ValuationHandler.AssetRateInput[] assetRates;
    }

    struct AccountERC20TrackerConfig {
        bool deploy;
        address[] assets;
    }

    struct LinearCreditDebtTrackerConfig {
        bool deploy;
    }

    struct QueueDepositHandlerConfig {
        address asset;
        uint24 minRequestDuration;
        ERC7540LikeDepositQueue.DepositRestriction restriction;
        ExternalListSource externalListSource;
        address externalListExisting;
        /// @dev Used when `externalListSource == SharedAddressList`; must be `< sharedAddressLists.length`.
        uint256 sharedAddressListIndex;
        /// @dev Seed addresses for `ControllerAllowlistInternal`; must be empty for other restrictions.
        address[] allowedDepositors;
        HookConfig preRequestDepositHook;
        HookConfig postExecuteDepositRequestHook;
    }

    struct SyncDepositHandlerConfig {
        address asset;
        uint24 maxSharePriceStaleness;
        ExternalListSource depositorAllowlistSource;
        address depositorAllowlistExisting;
        /// @dev Used when `depositorAllowlistSource == SharedAddressList`.
        uint256 sharedAddressListIndex;
        HookConfig postDepositHook;
    }

    struct SyncRedeemHandlerConfig {
        address asset;
        uint24 maxSharePriceStaleness;
        HookConfig postRedeemHook;
    }

    struct RedeemHandlerConfig {
        address asset;
        uint24 minRequestDuration;
        HookConfig preRequestRedeemHook;
        HookConfig postExecuteRedeemRequestHook;
    }

    struct SharesMintHandlerConfig {
        bool deploy;
        HookConfig preMintHook;
    }

    struct SharesBurnHandlerConfig {
        bool deploy;
        HookConfig preBurnHook;
    }

    struct AddressListsValidatorListConfig {
        AddressListsSharesTransferValidator.ListType listType;
        ExternalListSource externalListSource;
        address externalListExisting;
        /// @dev Used when `externalListSource == SharedAddressList`.
        uint256 sharedAddressListIndex;
    }

    struct TransferValidatorConfig {
        TransferValidatorSource source;
        address existing;
        AddressListsValidatorListConfig recipientList;
        AddressListsValidatorListConfig senderList;
        /// @dev Required when `source == DeployChainlinkAce`; ignored otherwise.
        address chainlinkAcePolicyEngine;
    }

    /// @dev Contract an automation's forwarder may call.
    /// Indexed handler targets (`QueueDepositHandler`, `SyncDepositHandler`, `SyncRedeemHandler`,
    /// `QueueRedeemHandler`) refer to the handler at `CallPermission.handlerIndex` of the matching
    /// `ComponentsConfig` array (`QueueRedeemHandler` indexes `redeemHandlers`).
    /// `External`: the address in `CallPermission.externalTarget`.
    enum CallTarget {
        Shares,
        ValuationHandler,
        FeeHandler,
        QueueDepositHandler,
        SyncDepositHandler,
        SyncRedeemHandler,
        QueueRedeemHandler,
        SharesMintHandler,
        SharesBurnHandler,
        External
    }

    /// @dev One (target, selector) pair an automation's forwarder may call.
    struct CallPermission {
        CallTarget target;
        /// @dev Used for indexed handler targets; must be < that handler config array's length.
        uint256 handlerIndex;
        /// @dev Required when `target == External`; ignored otherwise.
        address externalTarget;
        bytes4 selector;
    }

    struct AutomationConfig {
        /// @dev The CRE workflow name, as encoded in report metadata
        bytes10 workflowName;
        /// @dev May be empty; call permissions can be added later by the vault owner or an admin
        CallPermission[] calls;
    }

    struct DeployedAutomation {
        address creWorkflowConsumer;
        address limitedAccessLimitedCallForwarder;
    }

    struct PreMintRecipient {
        address to;
        uint256 amount;
    }

    struct PreMintConfig {
        bool enabled;
        int256 untrackedPositionsValue;
        PreMintRecipient[] recipients;
    }

    struct ComponentsConfig {
        FeeHandlerConfig feeHandler;
        ManagementFeeConfig managementFee;
        PerformanceFeeConfig performanceFee;
        ValuationHandlerConfig valuationHandler;
        AccountERC20TrackerConfig accountERC20Tracker;
        LinearCreditDebtTrackerConfig linearCreditDebtTracker;
        QueueDepositHandlerConfig[] queueDepositHandlers;
        SyncDepositHandlerConfig[] syncDepositHandlers;
        SyncRedeemHandlerConfig[] syncRedeemHandlers;
        RedeemHandlerConfig[] redeemHandlers;
        SharesMintHandlerConfig sharesMintHandler;
        SharesBurnHandlerConfig sharesBurnHandler;
    }

    struct DeployConfig {
        SharesConfig shares;
        /// @dev Pending owner after deploy (`transferOwnership`; nominee calls `acceptOwnership()`)
        address nominatedOwner;
        address[] admins;
        TransferValidatorConfig transferValidator;
        ComponentsConfig components;
        PreMintConfig preMint;
        /// @dev Lists deployed once before handlers; consumers use `ExternalListSource.SharedAddressList` + index.
        SharedAddressListDefinition[] sharedAddressLists;
        /// @dev Each entry gets its own consumer + forwarder pair; see contract-level NatSpec.
        AutomationConfig[] automations;
    }

    struct Deployed {
        address shares;
        address feeHandler;
        address valuationHandler;
        address managementFeeTracker;
        address performanceFeeTracker;
        address accountERC20Tracker;
        address linearCreditDebtTracker;
        address[] queueDepositHandlers;
        address[] queueDepositHandlerAllowlists;
        address[] queueDepositHandlerPreRequestHooks;
        address[] queueDepositHandlerPostExecuteHooks;
        address[] syncDepositHandlers;
        address[] syncDepositHandlerAllowlists;
        address[] syncDepositHandlerPostDepositHooks;
        address[] syncRedeemHandlers;
        address[] syncRedeemHandlerPostRedeemHooks;
        address[] redeemHandlers;
        address[] redeemHandlerPreRequestHooks;
        address[] redeemHandlerPostExecuteHooks;
        address sharesMintHandler;
        address sharesMintHandlerPreMintHook;
        address sharesBurnHandler;
        address sharesBurnHandlerPreBurnHook;
        address transferValidator;
        address transferValidatorRecipientList;
        address transferValidatorSenderList;
        /// @dev Addresses of `sharedAddressLists` entries in deployment order.
        address[] sharedAddressLists;
        /// @dev In `DeployConfig.automations` order.
        DeployedAutomation[] automations;
    }

    //==================================================================================================================
    // Immutables
    //==================================================================================================================

    address public immutable SHARES_FACTORY;
    address public immutable FEE_HANDLER_FACTORY;
    address public immutable VALUATION_HANDLER_FACTORY;
    address public immutable MANAGEMENT_FEE_TRACKER_FACTORY;
    address public immutable PERFORMANCE_FEE_TRACKER_FACTORY;
    address public immutable ACCOUNT_ERC20_TRACKER_FACTORY;
    address public immutable LINEAR_CREDIT_DEBT_TRACKER_FACTORY;
    address public immutable DEPOSIT_QUEUE_FACTORY;
    address public immutable SYNC_DEPOSIT_HANDLER_FACTORY;
    address public immutable SYNC_REDEEM_HANDLER_FACTORY;
    address public immutable REDEEM_QUEUE_FACTORY;
    address public immutable SHARES_OWNED_ADDRESS_LIST_FACTORY;
    address public immutable OWNABLE_ADDRESS_LIST_FACTORY;
    address public immutable ADDRESS_LISTS_SHARES_TRANSFER_VALIDATOR_FACTORY;
    address public immutable SHARES_MINT_HANDLER_FACTORY;
    address public immutable SHARES_BURN_HANDLER_FACTORY;
    address public immutable CHAINLINK_ACE_DEPOSIT_QUEUE_PRE_REQUEST_VALIDATOR_FACTORY;
    address public immutable CHAINLINK_ACE_DEPOSIT_QUEUE_POST_EXECUTE_VALIDATOR_FACTORY;
    address public immutable CHAINLINK_ACE_REDEEM_QUEUE_PRE_REQUEST_VALIDATOR_FACTORY;
    address public immutable CHAINLINK_ACE_REDEEM_QUEUE_POST_EXECUTE_VALIDATOR_FACTORY;
    address public immutable CHAINLINK_ACE_SYNC_DEPOSIT_POST_DEPOSIT_VALIDATOR_FACTORY;
    address public immutable CHAINLINK_ACE_SYNC_REDEEM_POST_REDEEM_VALIDATOR_FACTORY;
    address public immutable CHAINLINK_ACE_MINT_PRE_MINT_VALIDATOR_FACTORY;
    address public immutable CHAINLINK_ACE_BURN_PRE_BURN_VALIDATOR_FACTORY;
    address public immutable CHAINLINK_ACE_SHARES_TRANSFER_VALIDATOR_FACTORY;
    address public immutable LIMITED_ACCESS_LIMITED_CALL_FORWARDER_FACTORY;
    address public immutable CRE_WORKFLOW_CONSUMER_FACTORY;

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event VaultDeployed(Deployed deployed, address nominatedOwner);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error SharesDeployer__NominatedOwnerCannotBeZero();
    error SharesDeployer__NominatedOwnerCannotBeDeployer();
    error SharesDeployer__ManagementFeeRequiresFeeHandler();
    error SharesDeployer__PerformanceFeeRequiresFeeHandler();
    error SharesDeployer__AccountERC20TrackerRequiresValuationHandler();
    error SharesDeployer__LinearCreditDebtTrackerRequiresValuationHandler();
    error SharesDeployer__PreMintRequiresValuationHandler();
    error SharesDeployer__ExternalListSourceRequired();
    error SharesDeployer__ExternalListSourceNotAllowed();
    error SharesDeployer__ExternalListExistingCannotBeZero();
    error SharesDeployer__OwnableAddressListOwnerCannotBeZero();
    error SharesDeployer__SeedNotAllowedForExternalList();
    error SharesDeployer__SeedNotAllowedWithoutAllowlist();
    error SharesDeployer__TransferValidatorExistingCannotBeZero();
    error SharesDeployer__SharedAddressListIndexOutOfBounds();
    error SharesDeployer__HookExistingCannotBeZero();
    error SharesDeployer__PolicyEngineCannotBeZero();
    error SharesDeployer__HookNotAllowedWithoutHandler();
    error SharesDeployer__AutomationsUnavailable();
    error SharesDeployer__WorkflowNameCannotBeZero();
    error SharesDeployer__CallTargetNotDeployed();
    error SharesDeployer__CallTargetHandlerIndexOutOfBounds();
    error SharesDeployer__ExternalCallTargetCannotBeZero();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor(Factories memory _factories) {
        SHARES_FACTORY = _factories.sharesFactory;
        FEE_HANDLER_FACTORY = _factories.feeHandlerFactory;
        VALUATION_HANDLER_FACTORY = _factories.valuationHandlerFactory;
        MANAGEMENT_FEE_TRACKER_FACTORY = _factories.managementFeeTrackerFactory;
        PERFORMANCE_FEE_TRACKER_FACTORY = _factories.performanceFeeTrackerFactory;
        ACCOUNT_ERC20_TRACKER_FACTORY = _factories.accountERC20TrackerFactory;
        LINEAR_CREDIT_DEBT_TRACKER_FACTORY = _factories.linearCreditDebtTrackerFactory;
        DEPOSIT_QUEUE_FACTORY = _factories.depositQueueFactory;
        SYNC_DEPOSIT_HANDLER_FACTORY = _factories.syncDepositHandlerFactory;
        SYNC_REDEEM_HANDLER_FACTORY = _factories.syncRedeemHandlerFactory;
        REDEEM_QUEUE_FACTORY = _factories.redeemQueueFactory;
        SHARES_OWNED_ADDRESS_LIST_FACTORY = _factories.sharesOwnedAddressListFactory;
        OWNABLE_ADDRESS_LIST_FACTORY = _factories.ownableAddressListFactory;
        ADDRESS_LISTS_SHARES_TRANSFER_VALIDATOR_FACTORY = _factories.addressListsSharesTransferValidatorFactory;
        SHARES_MINT_HANDLER_FACTORY = _factories.sharesMintHandlerFactory;
        SHARES_BURN_HANDLER_FACTORY = _factories.sharesBurnHandlerFactory;
        CHAINLINK_ACE_DEPOSIT_QUEUE_PRE_REQUEST_VALIDATOR_FACTORY = _factories.aceDepositQueuePreRequestValidatorFactory;
        CHAINLINK_ACE_DEPOSIT_QUEUE_POST_EXECUTE_VALIDATOR_FACTORY =
        _factories.aceDepositQueuePostExecuteValidatorFactory;
        CHAINLINK_ACE_REDEEM_QUEUE_PRE_REQUEST_VALIDATOR_FACTORY = _factories.aceRedeemQueuePreRequestValidatorFactory;
        CHAINLINK_ACE_REDEEM_QUEUE_POST_EXECUTE_VALIDATOR_FACTORY = _factories.aceRedeemQueuePostExecuteValidatorFactory;
        CHAINLINK_ACE_SYNC_DEPOSIT_POST_DEPOSIT_VALIDATOR_FACTORY = _factories.aceSyncDepositPostDepositValidatorFactory;
        CHAINLINK_ACE_SYNC_REDEEM_POST_REDEEM_VALIDATOR_FACTORY = _factories.aceSyncRedeemPostRedeemValidatorFactory;
        CHAINLINK_ACE_MINT_PRE_MINT_VALIDATOR_FACTORY = _factories.aceMintPreMintValidatorFactory;
        CHAINLINK_ACE_BURN_PRE_BURN_VALIDATOR_FACTORY = _factories.aceBurnPreBurnValidatorFactory;
        CHAINLINK_ACE_SHARES_TRANSFER_VALIDATOR_FACTORY = _factories.aceSharesTransferValidatorFactory;
        LIMITED_ACCESS_LIMITED_CALL_FORWARDER_FACTORY = _factories.limitedAccessLimitedCallForwarderFactory;
        CRE_WORKFLOW_CONSUMER_FACTORY = _factories.creWorkflowConsumerFactory;
    }

    //==================================================================================================================
    // Deploy
    //==================================================================================================================

    /// @notice Deploys and wires a complete Onyx vault in a single transaction
    /// @param _cfg The full vault configuration
    /// @return shares_ The address of the deployed Shares proxy
    /// @dev `Shares` owner during deploy is this contract. Pending owner is `_cfg.nominatedOwner` (Ownable2Step);
    /// the nominee must call `acceptOwnership()` to complete the handover.
    function deploy(DeployConfig calldata _cfg) external returns (address shares_) {
        __validate(_cfg);

        Deployed memory d;

        d.shares = BeaconFactory(SHARES_FACTORY)
            .deployProxy(
                abi.encodeCall(
                    Shares.init, (address(this), _cfg.shares.name, _cfg.shares.symbol, _cfg.shares.valueAsset)
                )
            );

        d.sharedAddressLists = __deploySharedAddressLists(d, _cfg);

        __deployValuationStack(d, _cfg);
        __preMint(d, _cfg);
        __deployFeeStack(d, _cfg);
        __deployQueueDepositHandlers(d, _cfg);
        __deploySyncDepositHandlers(d, _cfg);
        __deploySyncRedeemHandlers(d, _cfg);
        __deployRedeemHandlers(d, _cfg);
        __deployMintBurnHandlers(d, _cfg);

        Shares shares = Shares(d.shares);

        __deployTransferValidator(d, _cfg);
        if (d.transferValidator != address(0)) {
            shares.setSharesTransferValidator(d.transferValidator);
        }

        d.automations = __deployAutomations(d, _cfg);

        for (uint256 i; i < _cfg.admins.length; i++) {
            shares.addAdmin(_cfg.admins[i]);
        }

        shares.transferOwnership(_cfg.nominatedOwner);

        emit VaultDeployed({deployed: d, nominatedOwner: _cfg.nominatedOwner});

        return d.shares;
    }

    //==================================================================================================================
    // Internal: validation
    //==================================================================================================================

    function __validate(DeployConfig calldata _cfg) internal view {
        require(_cfg.nominatedOwner != address(0), SharesDeployer__NominatedOwnerCannotBeZero());
        require(_cfg.nominatedOwner != address(this), SharesDeployer__NominatedOwnerCannotBeDeployer());
        require(
            !_cfg.components.managementFee.deploy || _cfg.components.feeHandler.deploy,
            SharesDeployer__ManagementFeeRequiresFeeHandler()
        );
        require(
            !_cfg.components.performanceFee.deploy || _cfg.components.feeHandler.deploy,
            SharesDeployer__PerformanceFeeRequiresFeeHandler()
        );
        require(
            !_cfg.components.accountERC20Tracker.deploy || _cfg.components.valuationHandler.deploy,
            SharesDeployer__AccountERC20TrackerRequiresValuationHandler()
        );
        require(
            !_cfg.components.linearCreditDebtTracker.deploy || _cfg.components.valuationHandler.deploy,
            SharesDeployer__LinearCreditDebtTrackerRequiresValuationHandler()
        );
        require(
            !_cfg.preMint.enabled || _cfg.components.valuationHandler.deploy,
            SharesDeployer__PreMintRequiresValuationHandler()
        );

        __validateSharedAddressListDefinitions(_cfg.sharedAddressLists);

        uint256 sharedListCount = _cfg.sharedAddressLists.length;

        QueueDepositHandlerConfig[] calldata queueDepositHandlers = _cfg.components.queueDepositHandlers;
        for (uint256 i; i < queueDepositHandlers.length; i++) {
            __validateQueueDepositHandler(queueDepositHandlers[i], sharedListCount);
        }

        SyncDepositHandlerConfig[] calldata syncDepositHandlers = _cfg.components.syncDepositHandlers;
        for (uint256 i; i < syncDepositHandlers.length; i++) {
            __validateSyncDepositHandler(syncDepositHandlers[i], sharedListCount);
        }

        SyncRedeemHandlerConfig[] calldata syncRedeemHandlers = _cfg.components.syncRedeemHandlers;
        for (uint256 i; i < syncRedeemHandlers.length; i++) {
            __validateHookConfig(syncRedeemHandlers[i].postRedeemHook);
        }

        RedeemHandlerConfig[] calldata redeemHandlers = _cfg.components.redeemHandlers;
        for (uint256 i; i < redeemHandlers.length; i++) {
            __validateHookConfig(redeemHandlers[i].preRequestRedeemHook);
            __validateHookConfig(redeemHandlers[i].postExecuteRedeemRequestHook);
        }

        __validateMintBurnHandlers(_cfg.components.sharesMintHandler, _cfg.components.sharesBurnHandler);

        __validateTransferValidator(_cfg.transferValidator, sharedListCount);

        __validateAutomations(_cfg);
    }

    function __validateAutomations(DeployConfig calldata _cfg) internal view {
        AutomationConfig[] calldata automations = _cfg.automations;
        if (automations.length == 0) return;

        require(CRE_WORKFLOW_CONSUMER_FACTORY != address(0), SharesDeployer__AutomationsUnavailable());

        for (uint256 i; i < automations.length; i++) {
            require(automations[i].workflowName != bytes10(0), SharesDeployer__WorkflowNameCannotBeZero());

            CallPermission[] calldata calls = automations[i].calls;
            for (uint256 j; j < calls.length; j++) {
                __validateCallPermission(_cfg.components, calls[j]);
            }
        }
    }

    function __validateCallPermission(ComponentsConfig calldata _c, CallPermission calldata _p) internal pure {
        CallTarget t = _p.target;

        if (t == CallTarget.External) {
            require(_p.externalTarget != address(0), SharesDeployer__ExternalCallTargetCannotBeZero());
            return;
        }

        uint256 handlerCount;
        if (t == CallTarget.QueueDepositHandler) {
            handlerCount = _c.queueDepositHandlers.length;
        } else if (t == CallTarget.SyncDepositHandler) {
            handlerCount = _c.syncDepositHandlers.length;
        } else if (t == CallTarget.SyncRedeemHandler) {
            handlerCount = _c.syncRedeemHandlers.length;
        } else if (t == CallTarget.QueueRedeemHandler) {
            handlerCount = _c.redeemHandlers.length;
        } else {
            bool deployed = t == CallTarget.Shares || (t == CallTarget.ValuationHandler && _c.valuationHandler.deploy)
                || (t == CallTarget.FeeHandler && _c.feeHandler.deploy)
                || (t == CallTarget.SharesMintHandler && _c.sharesMintHandler.deploy)
                || (t == CallTarget.SharesBurnHandler && _c.sharesBurnHandler.deploy);
            require(deployed, SharesDeployer__CallTargetNotDeployed());
            return;
        }

        require(_p.handlerIndex < handlerCount, SharesDeployer__CallTargetHandlerIndexOutOfBounds());
    }

    function __validateMintBurnHandlers(SharesMintHandlerConfig calldata _mint, SharesBurnHandlerConfig calldata _burn)
        internal
        pure
    {
        if (_mint.deploy) {
            __validateHookConfig(_mint.preMintHook);
        } else {
            require(_mint.preMintHook.source == HookSource.None, SharesDeployer__HookNotAllowedWithoutHandler());
        }

        if (_burn.deploy) {
            __validateHookConfig(_burn.preBurnHook);
        } else {
            require(_burn.preBurnHook.source == HookSource.None, SharesDeployer__HookNotAllowedWithoutHandler());
        }
    }

    function __validateHookConfig(HookConfig calldata _c) internal pure {
        if (_c.source == HookSource.Existing) {
            require(_c.existingHook != address(0), SharesDeployer__HookExistingCannotBeZero());
        } else if (_c.source == HookSource.DeployChainlinkAce) {
            require(_c.policyEngine != address(0), SharesDeployer__PolicyEngineCannotBeZero());
        }
    }

    function __validateSharedAddressListDefinitions(SharedAddressListDefinition[] calldata _defs) internal pure {
        for (uint256 i; i < _defs.length; i++) {
            SharedAddressListDefinition calldata def = _defs[i];
            if (def.kind == SharedAddressListKind.Ownable) {
                require(def.ownableListOwner != address(0), SharesDeployer__OwnableAddressListOwnerCannotBeZero());
            }
        }
    }

    function __validateTransferValidator(TransferValidatorConfig calldata _c, uint256 _sharedListCount) internal pure {
        if (_c.source == TransferValidatorSource.Existing) {
            require(_c.existing != address(0), SharesDeployer__TransferValidatorExistingCannotBeZero());
        } else if (_c.source == TransferValidatorSource.DeployAddressLists) {
            __validateValidatorListConfig(_c.recipientList, _sharedListCount);
            __validateValidatorListConfig(_c.senderList, _sharedListCount);
        } else if (_c.source == TransferValidatorSource.DeployChainlinkAce) {
            require(_c.chainlinkAcePolicyEngine != address(0), SharesDeployer__PolicyEngineCannotBeZero());
        }
    }

    function __validateValidatorListConfig(AddressListsValidatorListConfig calldata _c, uint256 _sharedListCount)
        internal
        pure
    {
        if (_c.listType == AddressListsSharesTransferValidator.ListType.None) {
            require(_c.externalListSource == ExternalListSource.None, SharesDeployer__ExternalListSourceNotAllowed());
        } else {
            __validateExternalListConfig({
                _source: _c.externalListSource,
                _existing: _c.externalListExisting,
                _sharedIndex: _c.sharedAddressListIndex,
                _sharedDefinitionsLength: _sharedListCount
            });
        }
    }

    function __validateQueueDepositHandler(QueueDepositHandlerConfig calldata _c, uint256 _sharedListCount)
        internal
        pure
    {
        if (_c.restriction == ERC7540LikeDepositQueue.DepositRestriction.None) {
            require(_c.externalListSource == ExternalListSource.None, SharesDeployer__ExternalListSourceNotAllowed());
            require(_c.allowedDepositors.length == 0, SharesDeployer__SeedNotAllowedWithoutAllowlist());
        } else if (_c.restriction == ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal) {
            require(_c.externalListSource == ExternalListSource.None, SharesDeployer__ExternalListSourceNotAllowed());
        } else {
            // ControllerAllowlistExternal
            __validateExternalListConfig({
                _source: _c.externalListSource,
                _existing: _c.externalListExisting,
                _sharedIndex: _c.sharedAddressListIndex,
                _sharedDefinitionsLength: _sharedListCount
            });
            require(_c.allowedDepositors.length == 0, SharesDeployer__SeedNotAllowedForExternalList());
        }

        __validateHookConfig(_c.preRequestDepositHook);
        __validateHookConfig(_c.postExecuteDepositRequestHook);
    }

    function __validateSyncDepositHandler(SyncDepositHandlerConfig calldata _c, uint256 _sharedListCount)
        internal
        pure
    {
        if (_c.depositorAllowlistSource != ExternalListSource.None) {
            __validateExternalListConfig({
                _source: _c.depositorAllowlistSource,
                _existing: _c.depositorAllowlistExisting,
                _sharedIndex: _c.sharedAddressListIndex,
                _sharedDefinitionsLength: _sharedListCount
            });
        }

        __validateHookConfig(_c.postDepositHook);
    }

    function __validateExternalListConfig(
        ExternalListSource _source,
        address _existing,
        uint256 _sharedIndex,
        uint256 _sharedDefinitionsLength
    ) internal pure {
        require(_source != ExternalListSource.None, SharesDeployer__ExternalListSourceRequired());

        if (_source == ExternalListSource.Existing) {
            require(_existing != address(0), SharesDeployer__ExternalListExistingCannotBeZero());
        } else {
            // SharedAddressList
            require(_sharedIndex < _sharedDefinitionsLength, SharesDeployer__SharedAddressListIndexOutOfBounds());
        }
    }

    function __deploySharedAddressLists(Deployed memory _d, DeployConfig calldata _cfg)
        internal
        returns (address[] memory lists_)
    {
        SharedAddressListDefinition[] calldata defs = _cfg.sharedAddressLists;
        lists_ = new address[](defs.length);
        for (uint256 i; i < defs.length; i++) {
            SharedAddressListDefinition calldata def = defs[i];
            if (def.kind == SharedAddressListKind.SharesOwned) {
                lists_[i] = ComponentBeaconFactory(SHARES_OWNED_ADDRESS_LIST_FACTORY).deployProxy(_d.shares, "");
                if (def.seededAddresses.length > 0) {
                    AddressListBase(lists_[i]).addToList(def.seededAddresses);
                }
            } else {
                lists_[i] = BeaconFactory(OWNABLE_ADDRESS_LIST_FACTORY)
                    .deployProxy(abi.encodeCall(OwnableAddressList.init, (address(this))));
                if (def.seededAddresses.length > 0) {
                    AddressListBase(lists_[i]).addToList(def.seededAddresses);
                }
                OwnableAddressList(lists_[i]).transferOwnership(def.ownableListOwner);
            }
        }
        return lists_;
    }

    //==================================================================================================================
    // Internal: valuation stack
    //==================================================================================================================

    function __deployValuationStack(Deployed memory _d, DeployConfig calldata _cfg) internal {
        if (!_cfg.components.valuationHandler.deploy) return;

        ValuationHandler vh =
            ValuationHandler(ComponentBeaconFactory(VALUATION_HANDLER_FACTORY).deployProxy(_d.shares, ""));
        _d.valuationHandler = address(vh);

        if (_cfg.components.accountERC20Tracker.deploy) {
            AccountERC20Tracker tracker = AccountERC20Tracker(
                ComponentBeaconFactory(ACCOUNT_ERC20_TRACKER_FACTORY)
                    .deployProxy(_d.shares, abi.encodeCall(AccountERC20Tracker.init, (_d.shares)))
            );
            address[] calldata assets = _cfg.components.accountERC20Tracker.assets;
            for (uint256 i; i < assets.length; i++) {
                tracker.addAsset(assets[i]);
            }
            vh.addPositionTracker(address(tracker));
            _d.accountERC20Tracker = address(tracker);
        }

        if (_cfg.components.linearCreditDebtTracker.deploy) {
            address lcdt = ComponentBeaconFactory(LINEAR_CREDIT_DEBT_TRACKER_FACTORY).deployProxy(_d.shares, "");
            vh.addPositionTracker(lcdt);
            _d.linearCreditDebtTracker = lcdt;
        }

        ValuationHandler.AssetRateInput[] calldata assetRates = _cfg.components.valuationHandler.assetRates;
        for (uint256 i; i < assetRates.length; i++) {
            vh.setAssetRate(assetRates[i]);
        }

        Shares(_d.shares).setValuationHandler(address(vh));
    }

    //==================================================================================================================
    // Internal: pre-mint
    //==================================================================================================================

    function __preMint(Deployed memory _d, DeployConfig calldata _cfg) internal {
        if (!_cfg.preMint.enabled) return;

        Shares shares = Shares(_d.shares);
        shares.addDepositHandler(address(this));

        PreMintRecipient[] calldata recipients = _cfg.preMint.recipients;
        uint256 total = 0;
        for (uint256 i; i < recipients.length; i++) {
            total += recipients[i].amount;
        }
        shares.mintFor(address(this), total);

        ValuationHandler(_d.valuationHandler).updateShareValue(_cfg.preMint.untrackedPositionsValue);

        for (uint256 i; i < recipients.length; i++) {
            IERC20(address(shares)).safeTransfer(recipients[i].to, recipients[i].amount);
        }

        shares.removeDepositHandler(address(this));
    }

    //==================================================================================================================
    // Internal: fee stack
    //==================================================================================================================

    function __deployFeeStack(Deployed memory _d, DeployConfig calldata _cfg) internal {
        if (!_cfg.components.feeHandler.deploy) return;

        FeeHandler fh = FeeHandler(ComponentBeaconFactory(FEE_HANDLER_FACTORY).deployProxy(_d.shares, ""));
        _d.feeHandler = address(fh);

        FeeHandlerConfig calldata fhCfg = _cfg.components.feeHandler;
        if (fhCfg.feeAsset != address(0)) fh.setFeeAsset(fhCfg.feeAsset);
        if (fhCfg.entranceFeeBps != 0) {
            fh.setEntranceFee(fhCfg.entranceFeeBps, fhCfg.entranceFeeRecipient);
        }
        if (fhCfg.exitFeeBps != 0) {
            fh.setExitFee(fhCfg.exitFeeBps, fhCfg.exitFeeRecipient);
        }

        if (_cfg.components.managementFee.deploy) {
            ContinuousFlatRateManagementFeeTracker mft = ContinuousFlatRateManagementFeeTracker(
                ComponentBeaconFactory(MANAGEMENT_FEE_TRACKER_FACTORY).deployProxy(_d.shares, "")
            );
            mft.setRate(_cfg.components.managementFee.feeBps);
            mft.resetLastSettled();
            fh.setManagementFee(address(mft), _cfg.components.managementFee.recipient);
            _d.managementFeeTracker = address(mft);
        }

        if (_cfg.components.performanceFee.deploy) {
            ContinuousFlatRatePerformanceFeeTracker pft = ContinuousFlatRatePerformanceFeeTracker(
                ComponentBeaconFactory(PERFORMANCE_FEE_TRACKER_FACTORY).deployProxy(_d.shares, "")
            );
            pft.setRate(_cfg.components.performanceFee.feeBps);
            if (_cfg.components.performanceFee.hurdleRateBps != 0) {
                pft.setHurdleRate(_cfg.components.performanceFee.hurdleRateBps);
            }
            fh.setPerformanceFee(address(pft), _cfg.components.performanceFee.recipient);
            _d.performanceFeeTracker = address(pft);
        }

        Shares(_d.shares).setFeeHandler(address(fh));
    }

    //==================================================================================================================
    // Internal: queue deposit handlers
    //==================================================================================================================

    function __deployQueueDepositHandlers(Deployed memory _d, DeployConfig calldata _cfg) internal {
        QueueDepositHandlerConfig[] calldata cfgs = _cfg.components.queueDepositHandlers;
        address[] memory deployed = new address[](cfgs.length);
        address[] memory allowlists = new address[](cfgs.length);
        _d.queueDepositHandlerPreRequestHooks = new address[](cfgs.length);
        _d.queueDepositHandlerPostExecuteHooks = new address[](cfgs.length);
        Shares shares = Shares(_d.shares);
        address[] memory sharedCatalog = _d.sharedAddressLists;

        for (uint256 i; i < cfgs.length; i++) {
            QueueDepositHandlerConfig calldata c = cfgs[i];
            ERC7540LikeDepositQueue q =
                ERC7540LikeDepositQueue(ComponentBeaconFactory(DEPOSIT_QUEUE_FACTORY).deployProxy(_d.shares, ""));
            q.setAsset(c.asset);
            q.setDepositMinRequestDuration(c.minRequestDuration);

            if (c.restriction == ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal) {
                q.setDepositRestriction(c.restriction);
                for (uint256 j; j < c.allowedDepositors.length; j++) {
                    q.addDepositControllerToInternalAllowlist(c.allowedDepositors[j]);
                }
            } else if (c.restriction == ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal) {
                address list = __resolveExternalAllowlist({
                    _source: c.externalListSource,
                    _existing: c.externalListExisting,
                    _sharedCatalog: sharedCatalog,
                    _sharedIndex: c.sharedAddressListIndex
                });
                q.setDepositControllerExternalAllowlist(list);
                q.setDepositRestriction(c.restriction);
                allowlists[i] = list;
            }

            __wireQueueDepositHooks(_d, c, q, i);

            shares.addDepositHandler(address(q));
            deployed[i] = address(q);
        }

        _d.queueDepositHandlers = deployed;
        _d.queueDepositHandlerAllowlists = allowlists;
    }

    /// @dev Hook arrays on `_d` must be pre-allocated to the queue deposit handler count.
    function __wireQueueDepositHooks(
        Deployed memory _d,
        QueueDepositHandlerConfig calldata _c,
        ERC7540LikeDepositQueue _q,
        uint256 _i
    ) internal {
        address preRequestHook = __resolveHook({
            _c: _c.preRequestDepositHook,
            _aceValidatorFactory: CHAINLINK_ACE_DEPOSIT_QUEUE_PRE_REQUEST_VALIDATOR_FACTORY,
            _shares: _d.shares,
            _handler: address(_q)
        });
        if (preRequestHook != address(0)) _q.setPreRequestDepositHook(preRequestHook);
        _d.queueDepositHandlerPreRequestHooks[_i] = preRequestHook;

        address postExecuteHook = __resolveHook({
            _c: _c.postExecuteDepositRequestHook,
            _aceValidatorFactory: CHAINLINK_ACE_DEPOSIT_QUEUE_POST_EXECUTE_VALIDATOR_FACTORY,
            _shares: _d.shares,
            _handler: address(_q)
        });
        if (postExecuteHook != address(0)) _q.setPostExecuteDepositRequestHook(postExecuteHook);
        _d.queueDepositHandlerPostExecuteHooks[_i] = postExecuteHook;
    }

    //==================================================================================================================
    // Internal: sync deposit handlers
    //==================================================================================================================

    function __deploySyncDepositHandlers(Deployed memory _d, DeployConfig calldata _cfg) internal {
        SyncDepositHandlerConfig[] calldata cfgs = _cfg.components.syncDepositHandlers;
        address[] memory deployed = new address[](cfgs.length);
        address[] memory allowlists = new address[](cfgs.length);
        _d.syncDepositHandlerPostDepositHooks = new address[](cfgs.length);
        Shares shares = Shares(_d.shares);
        address[] memory sharedCatalog = _d.sharedAddressLists;

        for (uint256 i; i < cfgs.length; i++) {
            SyncDepositHandlerConfig calldata c = cfgs[i];
            SyncDepositHandler h = SyncDepositHandler(
                ComponentBeaconFactory(SYNC_DEPOSIT_HANDLER_FACTORY)
                    .deployProxy(_d.shares, abi.encodeCall(SyncDepositHandler.init, (c.asset)))
            );

            if (c.depositorAllowlistSource != ExternalListSource.None) {
                address list = __resolveExternalAllowlist({
                    _source: c.depositorAllowlistSource,
                    _existing: c.depositorAllowlistExisting,
                    _sharedCatalog: sharedCatalog,
                    _sharedIndex: c.sharedAddressListIndex
                });
                h.setDepositorAllowlist(list);
                allowlists[i] = list;
            }
            if (c.maxSharePriceStaleness != 0) {
                h.setMaxSharePriceStaleness(c.maxSharePriceStaleness);
            }

            __wireSyncDepositHooks(_d, c, h, i);

            shares.addDepositHandler(address(h));
            deployed[i] = address(h);
        }

        _d.syncDepositHandlers = deployed;
        _d.syncDepositHandlerAllowlists = allowlists;
    }

    /// @dev Hook array on `_d` must be pre-allocated to the sync deposit handler count.
    function __wireSyncDepositHooks(
        Deployed memory _d,
        SyncDepositHandlerConfig calldata _c,
        SyncDepositHandler _h,
        uint256 _i
    ) internal {
        address postDepositHook = __resolveHook({
            _c: _c.postDepositHook,
            _aceValidatorFactory: CHAINLINK_ACE_SYNC_DEPOSIT_POST_DEPOSIT_VALIDATOR_FACTORY,
            _shares: _d.shares,
            _handler: address(_h)
        });
        if (postDepositHook != address(0)) _h.setPostDepositHook(postDepositHook);
        _d.syncDepositHandlerPostDepositHooks[_i] = postDepositHook;
    }

    //==================================================================================================================
    // Internal: sync redeem handlers
    //==================================================================================================================

    function __deploySyncRedeemHandlers(Deployed memory _d, DeployConfig calldata _cfg) internal {
        SyncRedeemHandlerConfig[] calldata cfgs = _cfg.components.syncRedeemHandlers;
        address[] memory deployed = new address[](cfgs.length);
        _d.syncRedeemHandlerPostRedeemHooks = new address[](cfgs.length);
        Shares shares = Shares(_d.shares);

        for (uint256 i; i < cfgs.length; i++) {
            SyncRedeemHandlerConfig calldata c = cfgs[i];
            SyncRedeemHandler h = SyncRedeemHandler(
                ComponentBeaconFactory(SYNC_REDEEM_HANDLER_FACTORY)
                    .deployProxy(_d.shares, abi.encodeCall(SyncRedeemHandler.init, (c.asset)))
            );

            if (c.maxSharePriceStaleness != 0) {
                h.setMaxSharePriceStaleness(c.maxSharePriceStaleness);
            }

            __wireSyncRedeemHooks(_d, c, h, i);

            shares.addRedeemHandler(address(h));
            deployed[i] = address(h);
        }

        _d.syncRedeemHandlers = deployed;
    }

    /// @dev Hook array on `_d` must be pre-allocated to the sync redeem handler count.
    function __wireSyncRedeemHooks(
        Deployed memory _d,
        SyncRedeemHandlerConfig calldata _c,
        SyncRedeemHandler _h,
        uint256 _i
    ) internal {
        address postRedeemHook = __resolveHook({
            _c: _c.postRedeemHook,
            _aceValidatorFactory: CHAINLINK_ACE_SYNC_REDEEM_POST_REDEEM_VALIDATOR_FACTORY,
            _shares: _d.shares,
            _handler: address(_h)
        });
        if (postRedeemHook != address(0)) _h.setPostRedeemHook(postRedeemHook);
        _d.syncRedeemHandlerPostRedeemHooks[_i] = postRedeemHook;
    }

    //==================================================================================================================
    // Internal: external allowlist resolution
    //==================================================================================================================

    /// @dev Resolves an `IAddressList` address based on the given source. For `Existing` returns
    /// the provided address as-is. For `SharedAddressList` returns `_sharedCatalog[_sharedIndex]`.
    /// Caller must have already validated the inputs via `__validateExternalListConfig`.
    function __resolveExternalAllowlist(
        ExternalListSource _source,
        address _existing,
        address[] memory _sharedCatalog,
        uint256 _sharedIndex
    ) internal pure returns (address) {
        if (_source == ExternalListSource.SharedAddressList) {
            return _sharedCatalog[_sharedIndex];
        }
        // ExternalListSource.Existing (None is handled by callers)
        return _existing;
    }

    //==================================================================================================================
    // Internal: transfer validator
    //==================================================================================================================

    function __deployTransferValidator(Deployed memory _d, DeployConfig calldata _cfg) internal {
        TransferValidatorConfig calldata vc = _cfg.transferValidator;

        if (vc.source == TransferValidatorSource.None) {
            return;
        }

        if (vc.source == TransferValidatorSource.Existing) {
            _d.transferValidator = vc.existing;
            return;
        }

        if (vc.source == TransferValidatorSource.DeployChainlinkAce) {
            _d.transferValidator = ComponentBeaconFactory(CHAINLINK_ACE_SHARES_TRANSFER_VALIDATOR_FACTORY)
                .deployProxy(
                    _d.shares, abi.encodeCall(ChainlinkAceSharesTransferValidator.init, (vc.chainlinkAcePolicyEngine))
                );
            return;
        }

        // DeployAddressLists
        AddressListsSharesTransferValidator validator = AddressListsSharesTransferValidator(
            ComponentBeaconFactory(ADDRESS_LISTS_SHARES_TRANSFER_VALIDATOR_FACTORY).deployProxy(_d.shares, "")
        );
        _d.transferValidator = address(validator);

        address[] memory sharedCatalog = _d.sharedAddressLists;
        _d.transferValidatorRecipientList = __applyValidatorListConfig({
            _validator: validator, _isRecipient: true, _c: vc.recipientList, _sharedCatalog: sharedCatalog
        });
        _d.transferValidatorSenderList = __applyValidatorListConfig({
            _validator: validator, _isRecipient: false, _c: vc.senderList, _sharedCatalog: sharedCatalog
        });
    }

    function __applyValidatorListConfig(
        AddressListsSharesTransferValidator _validator,
        bool _isRecipient,
        AddressListsValidatorListConfig calldata _c,
        address[] memory _sharedCatalog
    ) internal returns (address list_) {
        if (_c.listType == AddressListsSharesTransferValidator.ListType.None) {
            return address(0);
        }

        list_ = __resolveExternalAllowlist({
            _source: _c.externalListSource,
            _existing: _c.externalListExisting,
            _sharedCatalog: _sharedCatalog,
            _sharedIndex: _c.sharedAddressListIndex
        });

        if (_isRecipient) {
            _validator.setRecipientList(list_, _c.listType);
        } else {
            _validator.setSenderList(list_, _c.listType);
        }
    }

    //==================================================================================================================
    // Internal: redeem handlers
    //==================================================================================================================

    function __deployRedeemHandlers(Deployed memory _d, DeployConfig calldata _cfg) internal {
        RedeemHandlerConfig[] calldata cfgs = _cfg.components.redeemHandlers;
        address[] memory deployed = new address[](cfgs.length);
        _d.redeemHandlerPreRequestHooks = new address[](cfgs.length);
        _d.redeemHandlerPostExecuteHooks = new address[](cfgs.length);
        Shares shares = Shares(_d.shares);

        for (uint256 i; i < cfgs.length; i++) {
            RedeemHandlerConfig calldata c = cfgs[i];
            ERC7540LikeRedeemQueue q =
                ERC7540LikeRedeemQueue(ComponentBeaconFactory(REDEEM_QUEUE_FACTORY).deployProxy(_d.shares, ""));
            q.setAsset(c.asset);
            q.setRedeemMinRequestDuration(c.minRequestDuration);

            __wireRedeemHooks(_d, c, q, i);

            shares.addRedeemHandler(address(q));
            deployed[i] = address(q);
        }

        _d.redeemHandlers = deployed;
    }

    /// @dev Hook arrays on `_d` must be pre-allocated to the redeem handler count.
    function __wireRedeemHooks(
        Deployed memory _d,
        RedeemHandlerConfig calldata _c,
        ERC7540LikeRedeemQueue _q,
        uint256 _i
    ) internal {
        address preRequestHook = __resolveHook({
            _c: _c.preRequestRedeemHook,
            _aceValidatorFactory: CHAINLINK_ACE_REDEEM_QUEUE_PRE_REQUEST_VALIDATOR_FACTORY,
            _shares: _d.shares,
            _handler: address(_q)
        });
        if (preRequestHook != address(0)) _q.setPreRequestRedeemHook(preRequestHook);
        _d.redeemHandlerPreRequestHooks[_i] = preRequestHook;

        address postExecuteHook = __resolveHook({
            _c: _c.postExecuteRedeemRequestHook,
            _aceValidatorFactory: CHAINLINK_ACE_REDEEM_QUEUE_POST_EXECUTE_VALIDATOR_FACTORY,
            _shares: _d.shares,
            _handler: address(_q)
        });
        if (postExecuteHook != address(0)) _q.setPostExecuteRedeemRequestHook(postExecuteHook);
        _d.redeemHandlerPostExecuteHooks[_i] = postExecuteHook;
    }

    //==================================================================================================================
    // Internal: mint/burn handlers
    //==================================================================================================================

    function __deployMintBurnHandlers(Deployed memory _d, DeployConfig calldata _cfg) internal {
        Shares shares = Shares(_d.shares);

        if (_cfg.components.sharesMintHandler.deploy) {
            SharesMintHandler handler =
                SharesMintHandler(ComponentBeaconFactory(SHARES_MINT_HANDLER_FACTORY).deployProxy(_d.shares, ""));

            address preMintHook = __resolveHook({
                _c: _cfg.components.sharesMintHandler.preMintHook,
                _aceValidatorFactory: CHAINLINK_ACE_MINT_PRE_MINT_VALIDATOR_FACTORY,
                _shares: _d.shares,
                _handler: address(handler)
            });
            if (preMintHook != address(0)) handler.setPreMintHook(preMintHook);

            shares.addDepositHandler(address(handler));
            _d.sharesMintHandler = address(handler);
            _d.sharesMintHandlerPreMintHook = preMintHook;
        }

        if (_cfg.components.sharesBurnHandler.deploy) {
            SharesBurnHandler handler =
                SharesBurnHandler(ComponentBeaconFactory(SHARES_BURN_HANDLER_FACTORY).deployProxy(_d.shares, ""));

            address preBurnHook = __resolveHook({
                _c: _cfg.components.sharesBurnHandler.preBurnHook,
                _aceValidatorFactory: CHAINLINK_ACE_BURN_PRE_BURN_VALIDATOR_FACTORY,
                _shares: _d.shares,
                _handler: address(handler)
            });
            if (preBurnHook != address(0)) handler.setPreBurnHook(preBurnHook);

            shares.addRedeemHandler(address(handler));
            _d.sharesBurnHandler = address(handler);
            _d.sharesBurnHandlerPreBurnHook = preBurnHook;
        }
    }

    //==================================================================================================================
    // Internal: automations
    //==================================================================================================================

    /// @dev Must run after every call target is deployed and while this contract still owns Shares.
    /// Leaves each consumer's workflow ID unset (see contract-level NatSpec).
    function __deployAutomations(Deployed memory _d, DeployConfig calldata _cfg)
        internal
        returns (DeployedAutomation[] memory automations_)
    {
        AutomationConfig[] calldata cfgs = _cfg.automations;
        automations_ = new DeployedAutomation[](cfgs.length);

        for (uint256 i; i < cfgs.length; i++) {
            LimitedAccessLimitedCallForwarder forwarder = LimitedAccessLimitedCallForwarder(
                ComponentBeaconFactory(LIMITED_ACCESS_LIMITED_CALL_FORWARDER_FACTORY).deployProxy(_d.shares, "")
            );
            // `init` is unprotected, so it must run atomically with proxy deployment
            address consumer = ComponentBeaconFactory(CRE_WORKFLOW_CONSUMER_FACTORY)
                .deployProxy(_d.shares, abi.encodeCall(CreWorkflowConsumer.init, (cfgs[i].workflowName, forwarder)));

            forwarder.addUser(consumer);

            CallPermission[] calldata calls = cfgs[i].calls;
            for (uint256 j; j < calls.length; j++) {
                forwarder.addCall(__resolveCallTarget(_d, calls[j]), calls[j].selector);
            }

            Shares(_d.shares).addAdmin(address(forwarder));

            automations_[i] = DeployedAutomation({
                creWorkflowConsumer: consumer, limitedAccessLimitedCallForwarder: address(forwarder)
            });
        }
    }

    /// @dev Caller must have already validated the inputs via `__validateCallPermission`.
    function __resolveCallTarget(Deployed memory _d, CallPermission calldata _p) internal pure returns (address) {
        CallTarget t = _p.target;
        if (t == CallTarget.Shares) return _d.shares;
        if (t == CallTarget.ValuationHandler) return _d.valuationHandler;
        if (t == CallTarget.FeeHandler) return _d.feeHandler;
        if (t == CallTarget.QueueDepositHandler) return _d.queueDepositHandlers[_p.handlerIndex];
        if (t == CallTarget.SyncDepositHandler) return _d.syncDepositHandlers[_p.handlerIndex];
        if (t == CallTarget.SyncRedeemHandler) return _d.syncRedeemHandlers[_p.handlerIndex];
        if (t == CallTarget.QueueRedeemHandler) return _d.redeemHandlers[_p.handlerIndex];
        if (t == CallTarget.SharesMintHandler) return _d.sharesMintHandler;
        if (t == CallTarget.SharesBurnHandler) return _d.sharesBurnHandler;
        // CallTarget.External
        return _p.externalTarget;
    }

    //==================================================================================================================
    // Internal: hook resolution
    //==================================================================================================================

    /// @dev Resolves the effective hook address for a handler hook slot. For `Existing` returns the
    /// provided address as-is. For `DeployChainlinkAce` deploys the slot's Chainlink ACE validator
    /// (implementation fixed per slot by `_aceValidatorFactory`) bound to `_handler` and the configured
    /// policy engine. Caller must have already validated the inputs via `__validateHookConfig`.
    function __resolveHook(HookConfig calldata _c, address _aceValidatorFactory, address _shares, address _handler)
        internal
        returns (address hook_)
    {
        if (_c.source == HookSource.None) {
            return address(0);
        }

        if (_c.source == HookSource.Existing) {
            return _c.existingHook;
        }

        // DeployChainlinkAce
        return ComponentBeaconFactory(_aceValidatorFactory)
            .deployProxy(_shares, abi.encodeCall(ChainlinkAceIssuanceValidatorBase.init, (_handler, _c.policyEngine)));
    }
}
