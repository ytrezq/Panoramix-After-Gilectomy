// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocQueueExecFees } from "./MocQueueExecFees.sol";
import { MocCore } from "../core/MocCore.sol";
import { MocCommons } from "../core/MocCommons.sol";
import { MocBaseBucket } from "../core/MocBaseBucket.sol";
import { MocOperations } from "../core/MocOperations.sol";
import { MocMultiCollateralGuard } from "../multiCollateral/MocMultiCollateralGuard.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title MocQueue: Allows queue Operation deferral execution processing
 */
contract MocQueue is MocQueueExecFees {
    // ------- Custom Errors -------
    error BucketAlreadyRegistered();
    error NotMocBucket();
    error NotMocMultiCollateralGuard();

    // ------- Errors Strings -------
    string private constant LOW_COVERAGE = "Low coverage";
    string private constant INSUFFICIENT_AC_SENT = "Insufficient qac sent";
    string private constant INSUFFICIENT_TP_SENT = "Insufficient tp sent";
    string private constant INSUFFICIENT_TC_TO_REDEEM = "Insufficient tc to redeem";
    string private constant INSUFFICIENT_TP_TO_MINT = "Insufficient tp to mint";
    string private constant AC_BELOW_MINIMUM = "qAC below minimum required";
    string private constant TC_BELOW_MINIMUM = "qTc below minimum required";
    string private constant TP_BELOW_MINIMUM = "qTp below minimum required";
    string private constant FLUX_CAPACITOR = "Max flux capacitor operation reached";

    // ------- Events -------
    event OperationError(uint256 operId_, bytes4 errorCode_, string msg_);
    event UnhandledError(uint256 operId_, bytes reason_);
    event ACUnlockFailed(uint256 operId_, address indexed sender_, uint256 qAC_);

    event OperationQueued(address indexed bucket_, uint256 operId_, OperType operType_);
    event OperationExecuted(address indexed executor, uint256 indexed operId_);

    event TCMinted(
        address indexed sender_,
        address indexed recipient_,
        uint256 qTC_,
        uint256 qAC_,
        uint256 qACfee_,
        uint256 qFeeToken_,
        uint256 qACVendorMarkup_,
        uint256 qFeeTokenVendorMarkup_,
        address vendor_,
        uint256 operId_
    );
    event TCRedeemed(
        address indexed sender_,
        address indexed recipient_,
        uint256 qTC_,
        uint256 qAC_,
        uint256 qACfee_,
        uint256 qFeeToken_,
        uint256 qACVendorMarkup_,
        uint256 qFeeTokenVendorMarkup_,
        address vendor_,
        uint256 operId_
    );
    event TPMinted(
        address indexed tp_,
        address indexed sender_,
        address indexed recipient_,
        uint256 qTP_,
        uint256 qAC_,
        uint256 qACfee_,
        uint256 qFeeToken_,
        uint256 qACVendorMarkup_,
        uint256 qFeeTokenVendorMarkup_,
        address vendor_,
        uint256 operId_
    );
    event TPRedeemed(
        address indexed tp_,
        address indexed sender_,
        address indexed recipient_,
        uint256 qTP_,
        uint256 qAC_,
        uint256 qACfee_,
        uint256 qFeeToken_,
        uint256 qACVendorMarkup_,
        uint256 qFeeTokenVendorMarkup_,
        address vendor_,
        uint256 operId_
    );
    event TCandTPRedeemed(
        address indexed tp_,
        address indexed sender_,
        address indexed recipient_,
        uint256 qTC_,
        uint256 qTP_,
        uint256 qAC_,
        uint256 qACtoRedeemTC_,
        uint256 qACtoRedeemTP_,
        uint256 qACfee_,
        uint256 qFeeToken_,
        uint256 qACVendorMarkup_,
        uint256 qFeeTokenVendorMarkup_,
        address vendor_,
        uint256 operId_
    );
    event TCandTPMinted(
        address indexed tp_,
        address indexed sender_,
        address indexed recipient_,
        uint256 qTC_,
        uint256 qTP_,
        uint256 qAC_,
        uint256 qACtoMintTC_,
        uint256 qACtoMintTP_,
        uint256 qACfee_,
        uint256 qFeeToken_,
        uint256 qACVendorMarkup_,
        uint256 qFeeTokenVendorMarkup_,
        address vendor_,
        uint256 operId_
    );
    event TPSwappedForTP(
        address indexed tpFrom_,
        address tpTo_,
        address indexed sender_,
        address indexed recipient_,
        uint256 qTPfrom_,
        uint256 qTPto_,
        uint256 qACfee_,
        uint256 qFeeToken_,
        uint256 qACVendorMarkup_,
        uint256 qFeeTokenVendorMarkup_,
        address vendor_,
        uint256 operId_
    );
    event TPSwappedForTC(
        address indexed tp_,
        address indexed sender_,
        address indexed recipient_,
        uint256 qTP_,
        uint256 qTC_,
        uint256 qACfee_,
        uint256 qFeeToken_,
        uint256 qACVendorMarkup_,
        uint256 qFeeTokenVendorMarkup_,
        address vendor_,
        uint256 operId_
    );
    event TCSwappedForTP(
        address indexed tp_,
        address indexed sender_,
        address indexed recipient_,
        uint256 qTC_,
        uint256 qTP_,
        uint256 qACfee_,
        uint256 qFeeToken_,
        uint256 qACVendorMarkup_,
        uint256 qFeeTokenVendorMarkup_,
        address vendor_,
        uint256 operId_
    );

    // ------- Structs -------
    struct OperInfo {
        // Operation Type
        OperType operType;
        // block number on which the Operation was queued
        uint248 queuedBlk;
    }

    // ------- Storage -------

    // mocOperations bucket that would be able to queue
    MocOperations public mocOperations;
    // Amount of Operations created
    uint256 public operIdCount;
    // first operation to be executed
    uint256 public firstOperId;

    mapping(uint256 => MocCore.MintTCParams) public operationsMintTC;
    mapping(uint256 => MocCore.MintTPParams) public operationsMintTP;
    mapping(uint256 => MocCore.RedeemTCParams) public operationsRedeemTC;
    mapping(uint256 => MocCore.RedeemTPParams) public operationsRedeemTP;
    mapping(uint256 => MocCore.MintTCandTPParams) public operationsMintTCandTP;
    mapping(uint256 => MocCore.RedeemTCandTPParams) public operationsRedeemTCandTP;
    mapping(uint256 => MocCore.SwapTCforTPParams) public operationsSwapTCforTP;
    mapping(uint256 => MocCore.SwapTPforTCParams) public operationsSwapTPforTC;
    mapping(uint256 => MocCore.SwapTPforTPParams) public operationsSwapTPforTP;

    // OperId => Operation Type | block.number
    mapping(uint256 => OperInfo) public opersInfo;

    // min amount of blocks the Operation should wait in the Queue before execution
    uint256 public minOperWaitingBlk;
    // max amount of blocks the Operation should wait in the Queue. Even if there is no price update
    // it can be executed after this amount of blocks
    uint256 public maxOperWaitingBlk;
    // track sender's locked funds on the bucket when they cannot be recovered after a failed operation
    mapping(address sender => uint256 lockedFunds) public senderLockedFunds;
    // total locked funds on the bucket when they cannot be recovered after a failed operation
    uint256 public totalLockedFunds;

    // ------- Modifiers -------
    /// @notice functions with this modifier can be called only by MocMultiCollateralGuard contract
    modifier onlyMocMultiCollateralGuard() {
        if (msg.sender != address(mocMultiCollateralGuard)) revert NotMocMultiCollateralGuard();
        _;
    }

    /// @notice functions with this modifier can be called only by Moc Bucket contract
    modifier onlyMocBucket() {
        if (msg.sender != address(mocOperations)) revert NotMocBucket();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ------- Initializer -------

    function initialize(
        address governor_,
        address pauser_,
        MocMultiCollateralGuard mocMultiCollateralGuard_,
        uint256 minOperWaitingBlk_,
        uint256 maxOperWaitingBlk_,
        InitializeMocQueueExecCostsParams calldata mocQueueExecCostsParams_
    ) external initializer {
        if (minOperWaitingBlk_ > maxOperWaitingBlk_) revert InvalidValue();
        __MocUpgradable_init(governor_, pauser_);
        __MocQueueExecFees_init(mocQueueExecCostsParams_);
        minOperWaitingBlk = minOperWaitingBlk_;
        maxOperWaitingBlk = maxOperWaitingBlk_;
        mocMultiCollateralGuard = mocMultiCollateralGuard_;
    }

    // ------- Internal Functions -------

    /**
     * @notice hook after mintedTC Operation execution, emits the TCMinted event
     * @param operId_ Identifier to track the Operation lifecycle
     * @param params_ TCMint params
     * @param qACtotalNeeded_ amount of AC used to mint qTC
     * @param feeCalcs_ platform fee detail breakdown
     */
    function _onDeferredTCMinted(
        uint256 operId_,
        MocCore.MintTCParams memory params_,
        uint256 qACtotalNeeded_,
        MocCore.FeeCalcs memory feeCalcs_
    ) internal {
        emit TCMinted(
            params_.sender,
            params_.recipient,
            params_.qTC,
            qACtotalNeeded_,
            feeCalcs_.qACFee,
            feeCalcs_.qFeeToken,
            feeCalcs_.qACVendorMarkup,
            feeCalcs_.qFeeTokenVendorMarkup,
            params_.vendor,
            operId_
        );
    }

    /**
     * @notice hook after redeemTC Operation execution, emits the TCRedeemed event
     * @param operId_ Identifier to track the Operation lifecycle
     * @param params_ mintTCto function params
     * @param qACRedeemed_ amount of AC redeemed
     * @param feeCalcs_ platform fee detail breakdown
     */
    function _onDeferredTCRedeemed(
        uint256 operId_,
        MocCore.RedeemTCParams memory params_,
        uint256 qACRedeemed_,
        MocCore.FeeCalcs memory feeCalcs_
    ) internal {
        emit TCRedeemed(
            params_.sender,
            params_.recipient,
            params_.qTC,
            qACRedeemed_,
            feeCalcs_.qACFee,
            feeCalcs_.qFeeToken,
            feeCalcs_.qACVendorMarkup,
            feeCalcs_.qFeeTokenVendorMarkup,
            params_.vendor,
            operId_
        );
    }

    /**
     * @notice hook after mintTP Operation is executed, emits the TPMinted event
     * @param operId_ Identifier to track the Operation lifecycle
     * @param params_ mintTP functions params
     * @param qACtotalNeeded_ amount of AC needed to mint qTP
     * @param feeCalcs_ platform fee detail breakdown
     */
    function _onDeferredTPMinted(
        uint256 operId_,
        MocCore.MintTPParams memory params_,
        uint256 qACtotalNeeded_,
        MocCore.FeeCalcs memory feeCalcs_
    ) internal {
        emit TPMinted(
            params_.tp,
            params_.sender,
            params_.recipient,
            params_.qTP,
            qACtotalNeeded_,
            feeCalcs_.qACFee,
            feeCalcs_.qFeeToken,
            feeCalcs_.qACVendorMarkup,
            feeCalcs_.qFeeTokenVendorMarkup,
            params_.vendor,
            operId_
        );
    }

    /**
     * @notice Hook after the TP is redeemed, with operation information result
     * @param operId_ operation id
     * @param params_ redeemTPto function params
     * @param qACRedeemed_ amount of AC redeemed
     * @param feeCalcs_ platform fee detail breakdown
     */
    function _onDeferredTPRedeemed(
        uint256 operId_,
        MocCore.RedeemTPParams memory params_,
        uint256 qACRedeemed_,
        MocCore.FeeCalcs memory feeCalcs_
    ) internal {
        emit TPRedeemed(
            params_.tp,
            params_.sender,
            params_.recipient,
            params_.qTP,
            qACRedeemed_,
            feeCalcs_.qACFee,
            feeCalcs_.qFeeToken,
            feeCalcs_.qACVendorMarkup,
            feeCalcs_.qFeeTokenVendorMarkup,
            params_.vendor,
            operId_
        );
    }

    /**
     * @notice Hook after the TC and TP are minted, with operation information result
     * @param operId_ operation id
     * @param params_ mintTCandTPto function params
     * @param qTCMinted_ amount of qTC minted for the given qTP
     * @param qACtoMintTC_ amount of AC used to mint TC
     * @param qACtoMintTP_ amount of AC used to mint TP
     * @param qACtoSpent_ total amount of AC spent by user
     * @param feeCalcs_ platform fee detail breakdown
     */
    function _onDeferredTCandTPMinted(
        uint256 operId_,
        MocCore.MintTCandTPParams memory params_,
        uint256 qTCMinted_,
        uint256 qACtoMintTC_,
        uint256 qACtoMintTP_,
        uint256 qACtoSpent_,
        MocCore.FeeCalcs memory feeCalcs_
    ) internal {
        emit TCandTPMinted(
            params_.tp,
            params_.sender,
            params_.recipient,
            qTCMinted_,
            params_.qTP,
            qACtoSpent_,
            qACtoMintTC_,
            qACtoMintTP_,
            feeCalcs_.qACFee,
            feeCalcs_.qFeeToken,
            feeCalcs_.qACVendorMarkup,
            feeCalcs_.qFeeTokenVendorMarkup,
            params_.vendor,
            operId_
        );
    }

    /**
     * @notice Hook after the TC and TP are redeemed, with operation information result
     * @param operId_ operation id
     * @param params_ redeemTCandTPto function params
     * @param qTPRedeemed_ total amount of TP redeemed
     * @param qACtoRedeemTC_ amount of AC redeemed due to TC redemption
     * @param qACtoRedeemTP_ amount of AC redeemed due to TP redemption
     * @param qACtoReceive_ total AC received by user after fees
     * @param feeCalcs_ platform fee detail breakdown
     */
    function _onDeferredTCandTPRedeemed(
        uint256 operId_,
        MocCore.RedeemTCandTPParams memory params_,
        uint256 qTPRedeemed_,
        uint256 qACtoRedeemTC_,
        uint256 qACtoRedeemTP_,
        uint256 qACtoReceive_,
        MocCore.FeeCalcs memory feeCalcs_
    ) internal {
        emit TCandTPRedeemed(
            params_.tp,
            params_.sender,
            params_.recipient,
            params_.qTC,
            qTPRedeemed_,
            qACtoReceive_,
            qACtoRedeemTC_,
            qACtoRedeemTP_,
            feeCalcs_.qACFee,
            feeCalcs_.qFeeToken,
            feeCalcs_.qACVendorMarkup,
            feeCalcs_.qFeeTokenVendorMarkup,
            params_.vendor,
            operId_
        );
    }

    /**
     * @notice Hook after the TC is swapped for TP, with operation information result
     * @param operId_ operation id
     * @param params_ swapTCforTP function params
     * @param qTPMinted_ total amount of TP swapped
     * @param feeCalcs_ platform fee detail breakdown
     */
    function _onDeferredTCforTPSwapped(
        uint256 operId_,
        MocCore.SwapTCforTPParams memory params_,
        uint256 qTPMinted_,
        MocCore.FeeCalcs memory feeCalcs_
    ) internal {
        emit TCSwappedForTP(
            params_.tp,
            params_.sender,
            params_.recipient,
            params_.qTC,
            qTPMinted_,
            feeCalcs_.qACFee,
            feeCalcs_.qFeeToken,
            feeCalcs_.qACVendorMarkup,
            feeCalcs_.qFeeTokenVendorMarkup,
            params_.vendor,
            operId_
        );
    }

    /**
     * @notice Hook after the TP is swapped for TC, with operation information result
     * @param operId_ operation id
     * @param params_ swapTPforTC function params
     * @param qTCMinted_ total amount of TC minted
     * @param feeCalcs_ platform fee detail breakdown
     */
    function _onDeferredTPforTCSwapped(
        uint256 operId_,
        MocCore.SwapTPforTCParams memory params_,
        uint256 qTCMinted_,
        MocCore.FeeCalcs memory feeCalcs_
    ) internal {
        emit TPSwappedForTC(
            params_.tp,
            params_.sender,
            params_.recipient,
            params_.qTP,
            qTCMinted_,
            feeCalcs_.qACFee,
            feeCalcs_.qFeeToken,
            feeCalcs_.qACVendorMarkup,
            feeCalcs_.qFeeTokenVendorMarkup,
            params_.vendor,
            operId_
        );
    }

    /**
     * @notice Hook after the TP is swapped for another TP, with operation information result
     * @param operId_ operation id
     * @param params_ swapTPforTP function params
     * @param qTPMinted_ total amount of TP `iTo` minted
     * @param feeCalcs_ platform fee detail breakdown
     */
    function _onDeferredTPforTPSwapped(
        uint256 operId_,
        MocCore.SwapTPforTPParams memory params_,
        uint256 qTPMinted_,
        MocCore.FeeCalcs memory feeCalcs_
    ) internal {
        emit TPSwappedForTP(
            params_.tpFrom,
            params_.tpTo,
            params_.sender,
            params_.recipient,
            params_.qTP,
            qTPMinted_,
            feeCalcs_.qACFee,
            feeCalcs_.qFeeToken,
            feeCalcs_.qACVendorMarkup,
            feeCalcs_.qFeeTokenVendorMarkup,
            params_.vendor,
            operId_
        );
    }

    /**
     * @notice unlocks AC in pending, handling any error
     * @dev AC transfers may fail in rare edge cases, including:
     *      1. For coinbase: if the sender is a contract without fallback function
     *      2. For RC20: if the token is paused or the sender is blacklisted
     *  To avoid blocking the execution of the queue, these errors are caught and handled.
     *  In such cases, the funds remain locked in the bucket and can later be addressed
     *  by governance depending on the specific situation.
     * @param bucket_ bucket that is intended to operate
     * @param operId_ operation id
     * @param sender_ sender that is intended to unlock
     * @param qAC_ amount of AC to unlock
     */
    function _unlockACInPending(MocOperations bucket_, uint256 operId_, address sender_, uint256 qAC_) internal {
        try bucket_.unlockACInPending(sender_, qAC_) {} catch {
            emit ACUnlockFailed(operId_, sender_, qAC_);
            senderLockedFunds[sender_] += qAC_;
            totalLockedFunds += qAC_;
        }
    }

    /**
     * @notice Executes mint TC handling any error
     * @param bucket_ bucket that is intended to operate
     * @param operId_ operation id
     *
     * May emit {TCMinted, OperationError, UnhandledError} events
     */
    function _executeMintTC(MocOperations bucket_, uint256 operId_) internal virtual {
        MocCore.MintTCParams memory params = operationsMintTC[operId_];
        try bucket_.execMintTC(params) returns (uint256 _qACtotalNeeded, uint256, MocCore.FeeCalcs memory _feeCalcs) {
            _onDeferredTCMinted(operId_, params, _qACtotalNeeded, _feeCalcs);
        } catch (bytes memory returnData) {
            // padded/shifted as decode only takes bytes32 chunks and error selector is just 4 bytes.
            bytes4 errorSelector = bytes4(returnData);
            if (errorSelector == MocCommons.InsufficientQacSent.selector) {
                emit OperationError(operId_, errorSelector, INSUFFICIENT_AC_SENT);
            } else if (errorSelector == MocBaseBucket.LowCoverage.selector) {
                emit OperationError(operId_, errorSelector, LOW_COVERAGE);
            } else emit UnhandledError(operId_, returnData);

            // On a failed Operation, we unlock user funds
            _unlockACInPending(bucket_, operId_, params.sender, params.qACmax);
        }
    }

    /**
     * @notice Executes redeem TC handling any error
     * @param bucket_ bucket that is intended to operate
     * @param operId_ operation id
     *
     * May emit {TCRedeemed, OperationError, UnhandledError} events
     */
    function _executeRedeemTC(MocOperations bucket_, uint256 operId_) internal virtual {
        MocCore.RedeemTCParams memory params = operationsRedeemTC[operId_];
        try bucket_.execRedeemTC(params) returns (uint256 _qACRedeemed, uint256, MocCore.FeeCalcs memory _feeCalcs) {
            _onDeferredTCRedeemed(operId_, params, _qACRedeemed, _feeCalcs);
        } catch (bytes memory returnData) {
            // padded/shifted as decode only takes bytes32 chunks and error selector is just 4 bytes.
            bytes4 errorSelector = bytes4(returnData);
            if (errorSelector == MocCommons.InsufficientTCtoRedeem.selector) {
                emit OperationError(operId_, errorSelector, INSUFFICIENT_TC_TO_REDEEM);
            } else if (errorSelector == MocCommons.QacBelowMinimumRequired.selector) {
                emit OperationError(operId_, errorSelector, AC_BELOW_MINIMUM);
            } else if (errorSelector == MocBaseBucket.LowCoverage.selector) {
                emit OperationError(operId_, errorSelector, LOW_COVERAGE);
            } else emit UnhandledError(operId_, returnData);

            // On a failed Operation, we unlock user funds
            bucket_.unlockTCInPending(params.sender, params.qTC);
        }
    }

    /**
     * @notice Executes mint TP handling any error
     * @param bucket_ bucket that is intended to operate
     * @param operId_ operation id
     *
     * May emit {TPMinted, OperationError, UnhandledError} events
     */
    function _executeMintTP(MocOperations bucket_, uint256 operId_) internal virtual {
        MocCore.MintTPParams memory params = operationsMintTP[operId_];
        try bucket_.execMintTP(params) returns (uint256 _qACtotalNeeded, uint256, MocCore.FeeCalcs memory _feeCalcs) {
            _onDeferredTPMinted(operId_, params, _qACtotalNeeded, _feeCalcs);
        } catch (bytes memory returnData) {
            // padded/shifted as decode only takes bytes32 chunks and error selector is just 4 bytes.
            bytes4 errorSelector = bytes4(returnData);
            if (errorSelector == MocCommons.MaxFluxCapacitorOperationReached.selector) {
                emit OperationError(operId_, errorSelector, FLUX_CAPACITOR);
            } else if (errorSelector == MocCommons.InsufficientTPtoMint.selector) {
                emit OperationError(operId_, errorSelector, INSUFFICIENT_TP_TO_MINT);
            } else if (errorSelector == MocCommons.InsufficientQacSent.selector) {
                emit OperationError(operId_, errorSelector, INSUFFICIENT_AC_SENT);
            } else if (errorSelector == MocBaseBucket.LowCoverage.selector) {
                emit OperationError(operId_, errorSelector, LOW_COVERAGE);
            } else emit UnhandledError(operId_, returnData);

            // On a failed Operation, we unlock user funds
            _unlockACInPending(bucket_, operId_, params.sender, params.qACmax);
        }
    }

    /**
     * @notice Executes redeem TP handling any error
     * @param bucket_ bucket that is intended to operate
     * @param operId_ operation id
     *
     * May emit {TPRedeemed, OperationError, UnhandledError} events
     */
    function _executeRedeemTP(MocOperations bucket_, uint256 operId_) internal virtual {
        MocCore.RedeemTPParams memory params = operationsRedeemTP[operId_];
        try bucket_.execRedeemTP(params) returns (uint256 _qACRedeemed, uint256, MocCore.FeeCalcs memory _feeCalcs) {
            _onDeferredTPRedeemed(operId_, params, _qACRedeemed, _feeCalcs);
        } catch (bytes memory returnData) {
            // padded/shifted as decode only takes bytes32 chunks and error selector is just 4 bytes.
            bytes4 errorSelector = bytes4(returnData);
            if (errorSelector == MocCommons.MaxFluxCapacitorOperationReached.selector) {
                emit OperationError(operId_, errorSelector, FLUX_CAPACITOR);
            } else if (errorSelector == MocCommons.QacBelowMinimumRequired.selector) {
                emit OperationError(operId_, errorSelector, AC_BELOW_MINIMUM);
            } else if (errorSelector == MocBaseBucket.LowCoverage.selector) {
                emit OperationError(operId_, errorSelector, LOW_COVERAGE);
            } else emit UnhandledError(operId_, returnData);

            // On a failed Operation, we unlock user funds
            bucket_.unlockTPInPending(params.sender, IERC20Upgradeable(params.tp), params.qTP);
        }
    }

    /**
     * @notice Executes mint TC and TP handling any error
     * @param bucket_ bucket that is intended to operate
     * @param operId_ operation id
     *
     * May emit {TCandTPMinted, OperationError, UnhandledError} events
     */
    function _executeMintTCandTP(MocOperations bucket_, uint256 operId_) internal virtual {
        MocCore.MintTCandTPParams memory params = operationsMintTCandTP[operId_];
        try bucket_.execMintTCandTP(params) returns (
            uint256 _qACtoMintTC,
            uint256 _qACtoMintTP,
            uint256 _qACtoSpent,
            uint256 _qTcMinted,
            uint256,
            MocCore.FeeCalcs memory _feeCalcs
        ) {
            _onDeferredTCandTPMinted(operId_, params, _qTcMinted, _qACtoMintTC, _qACtoMintTP, _qACtoSpent, _feeCalcs);
        } catch (bytes memory returnData) {
            // padded/shifted as decode only takes bytes32 chunks and error selector is just 4 bytes.
            bytes4 errorSelector = bytes4(returnData);
            if (errorSelector == MocCommons.MaxFluxCapacitorOperationReached.selector) {
                emit OperationError(operId_, errorSelector, FLUX_CAPACITOR);
            } else if (errorSelector == MocCommons.InsufficientQacSent.selector) {
                emit OperationError(operId_, errorSelector, INSUFFICIENT_AC_SENT);
            } else if (errorSelector == MocBaseBucket.LowCoverage.selector) {
                emit OperationError(operId_, errorSelector, LOW_COVERAGE);
            } else emit UnhandledError(operId_, returnData);

            // On a failed Operation, we unlock user funds
            _unlockACInPending(bucket_, operId_, params.sender, params.qACmax);
        }
    }

    /**
     * @notice Executes redeem TC and TP handling any error
     * @param bucket_ bucket that is intended to operate
     * @param operId_ operation id
     *
     * May emit {TCandTPRedeemed, OperationError, UnhandledError} events
     */
    function _executeRedeemTCandTP(MocOperations bucket_, uint256 operId_) internal virtual {
        MocCore.RedeemTCandTPParams memory params = operationsRedeemTCandTP[operId_];
        try bucket_.execRedeemTCandTP(params) returns (
            uint256 _qACtoRedeemTC,
            uint256 _qACtoRedeemTP,
            uint256 _qACtoReceive,
            uint256 _qTPRedeemed,
            uint256,
            MocCore.FeeCalcs memory _feeCalcs
        ) {
            _onDeferredTCandTPRedeemed(
                operId_,
                params,
                _qTPRedeemed,
                _qACtoRedeemTC,
                _qACtoRedeemTP,
                _qACtoReceive,
                _feeCalcs
            );
        } catch (bytes memory returnData) {
            // padded/shifted as decode only takes bytes32 chunks and error selector is just 4 bytes.
            bytes4 errorSelector = bytes4(returnData);
            if (errorSelector == MocCommons.MaxFluxCapacitorOperationReached.selector) {
                emit OperationError(operId_, errorSelector, FLUX_CAPACITOR);
            } else if (errorSelector == MocCommons.InsufficientQtpSent.selector) {
                emit OperationError(operId_, errorSelector, INSUFFICIENT_TP_SENT);
            } else if (errorSelector == MocCommons.QacBelowMinimumRequired.selector) {
                emit OperationError(operId_, errorSelector, AC_BELOW_MINIMUM);
            } else if (errorSelector == MocBaseBucket.LowCoverage.selector) {
                emit OperationError(operId_, errorSelector, LOW_COVERAGE);
            } else emit UnhandledError(operId_, returnData);

            // On a failed Operation, we unlock user funds
            bucket_.unlockTPInPending(params.sender, IERC20Upgradeable(params.tp), params.qTP);
            bucket_.unlockTCInPending(params.sender, params.qTC);
        }
    }

    /**
     * @notice Executes swap TC for TP handling any error
     * @param bucket_ bucket that is intended to operate
     * @param operId_ operation id
     *
     * May emit {TCforTPSwapped, OperationError, UnhandledError} events
     */
    function _executeSwapTCforTP(MocOperations bucket_, uint256 operId_) internal virtual {
        MocCore.SwapTCforTPParams memory params = operationsSwapTCforTP[operId_];
        try bucket_.execSwapTCforTP(params) returns (
            uint256,
            uint256 qTPMinted,
            uint256,
            MocCore.FeeCalcs memory feeCalcs
        ) {
            _onDeferredTCforTPSwapped(operId_, params, qTPMinted, feeCalcs);
        } catch (bytes memory returnData) {
            // padded/shifted as decode only takes bytes32 chunks and error selector is just 4 bytes.
            bytes4 errorSelector = bytes4(returnData);
            if (errorSelector == MocCommons.MaxFluxCapacitorOperationReached.selector) {
                emit OperationError(operId_, errorSelector, FLUX_CAPACITOR);
            } else if (errorSelector == MocCommons.InsufficientTCtoRedeem.selector) {
                emit OperationError(operId_, errorSelector, INSUFFICIENT_TC_TO_REDEEM);
            } else if (errorSelector == MocCommons.InsufficientTPtoMint.selector) {
                emit OperationError(operId_, errorSelector, INSUFFICIENT_TP_TO_MINT);
            } else if (errorSelector == MocCommons.InsufficientQacSent.selector) {
                emit OperationError(operId_, errorSelector, INSUFFICIENT_AC_SENT);
            } else if (errorSelector == MocCommons.QtpBelowMinimumRequired.selector) {
                emit OperationError(operId_, errorSelector, TP_BELOW_MINIMUM);
            } else if (errorSelector == MocBaseBucket.LowCoverage.selector) {
                emit OperationError(operId_, errorSelector, LOW_COVERAGE);
            } else emit UnhandledError(operId_, returnData);

            // On a failed Operation, we unlock user funds
            bucket_.unlockTCInPending(params.sender, params.qTC);
            _unlockACInPending(bucket_, operId_, params.sender, params.qACmax);
        }
    }

    /**
     * @notice Executes swap TP for TC handling any error
     * @param bucket_ bucket that is intended to operate
     * @param operId_ operation id
     *
     * May emit {TPforTCSwapped, OperationError, UnhandledError} events
     */
    function _executeSwapTPforTC(MocOperations bucket_, uint256 operId_) internal virtual {
        MocCore.SwapTPforTCParams memory params = operationsSwapTPforTC[operId_];
        try bucket_.execSwapTPforTC(params) returns (
            uint256,
            uint256 qTCMinted,
            uint256,
            MocCore.FeeCalcs memory feeCalcs
        ) {
            _onDeferredTPforTCSwapped(operId_, params, qTCMinted, feeCalcs);
        } catch (bytes memory returnData) {
            // padded/shifted as decode only takes bytes32 chunks and error selector is just 4 bytes.
            bytes4 errorSelector = bytes4(returnData);
            if (errorSelector == MocCommons.MaxFluxCapacitorOperationReached.selector) {
                emit OperationError(operId_, errorSelector, FLUX_CAPACITOR);
            } else if (errorSelector == MocCommons.InsufficientQacSent.selector) {
                emit OperationError(operId_, errorSelector, INSUFFICIENT_AC_SENT);
            } else if (errorSelector == MocCommons.QtcBelowMinimumRequired.selector) {
                emit OperationError(operId_, errorSelector, TC_BELOW_MINIMUM);
            } else if (errorSelector == MocBaseBucket.LowCoverage.selector) {
                emit OperationError(operId_, errorSelector, LOW_COVERAGE);
            } else emit UnhandledError(operId_, returnData);

            // On a failed Operation, we unlock user funds
            bucket_.unlockTPInPending(params.sender, IERC20Upgradeable(params.tp), params.qTP);
            _unlockACInPending(bucket_, operId_, params.sender, params.qACmax);
        }
    }

    /**
     * @notice Executes swap TP for TP handling any error
     * @param bucket_ bucket that is intended to operate
     * @param operId_ operation id
     *
     * May emit {TPforTPSwapped, OperationError, UnhandledError} events
     */
    function _executeSwapTPforTP(MocOperations bucket_, uint256 operId_) internal virtual {
        MocCore.SwapTPforTPParams memory params = operationsSwapTPforTP[operId_];
        try bucket_.execSwapTPforTP(params) returns (
            uint256,
            uint256 qTPMinted,
            uint256,
            MocCore.FeeCalcs memory feeCalcs
        ) {
            _onDeferredTPforTPSwapped(operId_, params, qTPMinted, feeCalcs);
        } catch (bytes memory returnData) {
            // padded/shifted as decode only takes bytes32 chunks and error selector is just 4 bytes.
            bytes4 errorSelector = bytes4(returnData);
            if (errorSelector == MocCommons.InsufficientTPtoMint.selector) {
                emit OperationError(operId_, errorSelector, INSUFFICIENT_TP_TO_MINT);
            } else if (errorSelector == MocCommons.InsufficientQacSent.selector) {
                emit OperationError(operId_, errorSelector, INSUFFICIENT_AC_SENT);
            } else if (errorSelector == MocCommons.QtpBelowMinimumRequired.selector) {
                emit OperationError(operId_, errorSelector, TP_BELOW_MINIMUM);
            } else if (errorSelector == MocBaseBucket.LowCoverage.selector) {
                emit OperationError(operId_, errorSelector, LOW_COVERAGE);
            } else emit UnhandledError(operId_, returnData);

            // On a failed Operation, we unlock user funds
            bucket_.unlockTPInPending(params.sender, IERC20Upgradeable(params.tpFrom), params.qTP);
            _unlockACInPending(bucket_, operId_, params.sender, params.qACmax);
        }
    }

    /**
     * @notice executes the given Operation by the `operId_`
     * @dev does not revert on Operation failure, throws Process and Error
     * events according to the Oper type and result
     * @param operId_ Id of the Operation to be executed
     * @param operType_ type of the Operation to be executed
     * @param bucket_ bucket that is intended to operate
     */
    //solhint-disable-next-line code-complexity
    function _executeOper(uint256 operId_, OperType operType_, MocOperations bucket_) internal {
        if (operType_ == OperType.mintTC) {
            _executeMintTC(bucket_, operId_);
            delete operationsMintTC[operId_];
        } else if (operType_ == OperType.redeemTC) {
            _executeRedeemTC(bucket_, operId_);
            delete operationsRedeemTC[operId_];
        } else if (operType_ == OperType.mintTP) {
            _executeMintTP(bucket_, operId_);
            delete operationsMintTP[operId_];
        } else if (operType_ == OperType.redeemTP) {
            _executeRedeemTP(bucket_, operId_);
            delete operationsRedeemTP[operId_];
        } else if (operType_ == OperType.mintTCandTP) {
            _executeMintTCandTP(bucket_, operId_);
            delete operationsMintTCandTP[operId_];
        } else if (operType_ == OperType.redeemTCandTP) {
            _executeRedeemTCandTP(bucket_, operId_);
            delete operationsRedeemTCandTP[operId_];
        } else if (operType_ == OperType.swapTCforTP) {
            _executeSwapTCforTP(bucket_, operId_);
            delete operationsSwapTCforTP[operId_];
        } else if (operType_ == OperType.swapTPforTC) {
            _executeSwapTPforTC(bucket_, operId_);
            delete operationsSwapTPforTC[operId_];
        } else if (operType_ == OperType.swapTPforTP) {
            _executeSwapTPforTP(bucket_, operId_);
            delete operationsSwapTPforTP[operId_];
        }
    }

    /**
     * @notice gets the last block in which the queued operations can be executed.
     *  Only operations enqueued before `blocksSinceLastPublication_` can be executed,
     *  but they must have been queued for at least `minOperWaitingBlk_` and at most `maxOperWaitingBlk_`
     * @param blocksSinceLastPublication_ amount of blocks since last price publication
     * @param minOperWaitingBlk_ min amount of blocks the operation should wait in the Queue before execution
     * @param maxOperWaitingBlk_ max amount of blocks the operation should wait in the Queue before execution
     * @return lastBlockToExecute last block to execute operations
     */
    function _getLastBlockToExecute(
        uint256 blocksSinceLastPublication_,
        uint256 minOperWaitingBlk_,
        uint256 maxOperWaitingBlk_
    ) internal view returns (uint256 lastBlockToExecute) {
        uint256 qBlocksToExecute;
        if (blocksSinceLastPublication_ >= maxOperWaitingBlk_) {
            qBlocksToExecute = maxOperWaitingBlk_;
        } else {
            // when maxOperWaitingBlk_ < blocksSinceLastPublication_, this max is not necessary to calculate
            // because maxOperWaitingBlk_ is always > minOperWaitingBlk_ by parameter
            qBlocksToExecute = Math.max(minOperWaitingBlk_, blocksSinceLastPublication_);
        }
        return block.number - qBlocksToExecute;
    }

    // ------- External Functions -------

    /**
     * @notice executes operation on a batch, controlled by MocMultiCollateralGuard contract
     * @dev does not revert on Operation failure, throws Process and Error
     * events according to the Oper type and result
     * @param executor_ executor address
     * @param maxOperPerBatch_ max amount of operations allowed to be executed
     * @param blocksSinceLastPublication_ amount of blocks since last price publication
     * @return totalExecutionFee total amount of execution fee to be sent to the execution fee recipient
     * @return totalOperExecuted total amount of operations executed
     */
    function execute(
        address executor_,
        uint256 maxOperPerBatch_,
        uint256 blocksSinceLastPublication_
    ) external onlyMocMultiCollateralGuard returns (uint256 totalExecutionFee, uint256 totalOperExecuted) {
        uint256 operId = firstOperId;
        uint256 lastOperId;
        uint256 limitBlk;
        unchecked {
            lastOperId = Math.min(operIdCount, operId + maxOperPerBatch_);
            limitBlk = _getLastBlockToExecute(blocksSinceLastPublication_, minOperWaitingBlk, maxOperWaitingBlk);
        }
        MocOperations bucket = mocOperations;
        // loop through all pending Operations
        while (operId < lastOperId) {
            OperInfo memory operInfo = opersInfo[operId];
            // If current Operation has not met the waiting block criteria, we end the loop
            if (operInfo.queuedBlk > limitBlk) break;

            _executeOper(operId, operInfo.operType, bucket);
            emit OperationExecuted(executor_, operId);
            delete opersInfo[operId];
            unchecked {
                operId = operId + 1;
                totalExecutionFee += execCost[operInfo.operType];
            }
        }
        unchecked {
            totalOperExecuted = operId - firstOperId;
            totalExecutionFee = totalExecutionFee * _getBaseFee();
        }
        // Define new reference to queue beginning
        firstOperId = operId;
    }

    /**
     * @notice registered enqueuer can queue an Operations
     * @return operId Identifier to track the Operation lifecycle
     */
    function queueMintTC(
        MocCore.MintTCParams calldata params
    ) external notPaused onlyMocBucket returns (uint256 operId) {
        operId = operIdCount;
        opersInfo[operId] = OperInfo(OperType.mintTC, uint248(block.number));
        operationsMintTC[operId] = params;
        emit OperationQueued(msg.sender, operId, OperType.mintTC);
        operIdCount = unchecked_inc(operIdCount);
    }

    /**
     * @notice registered enqueuer can queue an Operations
     * @return operId Identifier to track the Operation lifecycle
     */
    function queueRedeemTC(
        MocCore.RedeemTCParams calldata params
    ) external notPaused onlyMocBucket returns (uint256 operId) {
        operId = operIdCount;
        opersInfo[operId] = OperInfo(OperType.redeemTC, uint248(block.number));
        operationsRedeemTC[operId] = params;
        emit OperationQueued(msg.sender, operId, OperType.redeemTC);
        operIdCount = unchecked_inc(operIdCount);
    }

    /**
     * @notice registered enqueuer can queue an Operations
     * @return operId Identifier to track the Operation lifecycle
     */
    function queueMintTP(
        MocCore.MintTPParams calldata params
    ) external notPaused onlyMocBucket returns (uint256 operId) {
        operId = operIdCount;
        opersInfo[operId] = OperInfo(OperType.mintTP, uint248(block.number));
        operationsMintTP[operId] = params;
        emit OperationQueued(msg.sender, operId, OperType.mintTP);
        operIdCount = unchecked_inc(operIdCount);
    }

    /**
     * @notice Registered enqueuer can queue an Operations
     * @return operId Identifier to track the Operation lifecycle
     */
    function queueRedeemTP(
        MocCore.RedeemTPParams calldata params
    ) external notPaused onlyMocBucket returns (uint256 operId) {
        operId = operIdCount;
        opersInfo[operId] = OperInfo(OperType.redeemTP, uint248(block.number));
        operationsRedeemTP[operId] = params;
        emit OperationQueued(msg.sender, operId, OperType.redeemTP);
        operIdCount = unchecked_inc(operIdCount);
    }

    /**
     * @notice Registered enqueuer can queue an Operations
     * @return operId Identifier to track the Operation lifecycle
     */
    function queueMintTCandTP(
        MocCore.MintTCandTPParams calldata params
    ) external notPaused onlyMocBucket returns (uint256 operId) {
        operId = operIdCount;
        opersInfo[operId] = OperInfo(OperType.mintTCandTP, uint248(block.number));
        operationsMintTCandTP[operId] = params;
        emit OperationQueued(msg.sender, operId, OperType.mintTCandTP);
        operIdCount = unchecked_inc(operIdCount);
    }

    /**
     * @notice Registered enqueuer can queue an Operations
     * @return operId Identifier to track the Operation lifecycle
     */
    function queueRedeemTCandTP(
        MocCore.RedeemTCandTPParams calldata params
    ) external notPaused onlyMocBucket returns (uint256 operId) {
        operId = operIdCount;
        opersInfo[operId] = OperInfo(OperType.redeemTCandTP, uint248(block.number));
        operationsRedeemTCandTP[operId] = params;
        emit OperationQueued(msg.sender, operId, OperType.redeemTCandTP);
        operIdCount = unchecked_inc(operIdCount);
    }

    /**
     * @notice Registered enqueuer can queue an Operations
     * @return operId Identifier to track the Operation lifecycle
     */
    function queueSwapTCforTP(
        MocCore.SwapTCforTPParams calldata params
    ) external notPaused onlyMocBucket returns (uint256 operId) {
        operId = operIdCount;
        opersInfo[operId] = OperInfo(OperType.swapTCforTP, uint248(block.number));
        operationsSwapTCforTP[operId] = params;
        emit OperationQueued(msg.sender, operId, OperType.swapTCforTP);
        operIdCount = unchecked_inc(operIdCount);
    }

    /**
     * @notice Registered enqueuer can queue an Operations
     * @return operId Identifier to track the Operation lifecycle
     */
    function queueSwapTPforTC(
        MocCore.SwapTPforTCParams calldata params
    ) external notPaused onlyMocBucket returns (uint256 operId) {
        operId = operIdCount;
        opersInfo[operId] = OperInfo(OperType.swapTPforTC, uint248(block.number));
        operationsSwapTPforTC[operId] = params;
        emit OperationQueued(msg.sender, operId, OperType.swapTPforTC);
        operIdCount = unchecked_inc(operIdCount);
    }

    /**
     * @notice Registered enqueuer can queue an Operations
     * @return operId Identifier to track the Operation lifecycle
     */
    function queueSwapTPforTP(
        MocCore.SwapTPforTPParams calldata params
    ) external notPaused onlyMocBucket returns (uint256 operId) {
        operId = operIdCount;
        opersInfo[operId] = OperInfo(OperType.swapTPforTP, uint248(block.number));
        operationsSwapTPforTP[operId] = params;
        emit OperationQueued(msg.sender, operId, OperType.swapTPforTP);
        operIdCount = unchecked_inc(operIdCount);
    }

    /**
     * @notice true if the queue is empty
     */
    function isEmpty() public view override returns (bool) {
        return firstOperId == operIdCount;
    }

    /**
     * @notice true if the queue has at least one Operation ready to be executed
     * @param blocksSinceLastPublication_ amount of blocks since last price publication
     */
    function readyToExecute(uint256 blocksSinceLastPublication_) external view returns (bool) {
        if (isEmpty()) return false;
        OperInfo memory operInfo = opersInfo[firstOperId];
        return (operInfo.queuedBlk <=
            _getLastBlockToExecute(blocksSinceLastPublication_, minOperWaitingBlk, maxOperWaitingBlk));
    }

    // ------- Only Authorized Changer Functions -------

    /**
     * @notice sets Moc Queue minimum operation waiting blocks
     * @param minOperWaitingBlk_ minimum amount of blocks an operation needs to remain in the
     * queue before it can be executed
     */
    function setMinOperWaitingBlk(uint256 minOperWaitingBlk_) external onlyAuthorizedChanger {
        if (minOperWaitingBlk_ > maxOperWaitingBlk) revert InvalidValue();
        minOperWaitingBlk = minOperWaitingBlk_;
    }

    /**
     * @notice sets Moc Queue maximum operation waiting blocks
     * @param maxOperWaitingBlk_ max amount of blocks the Operation should wait in the Queue.
     * Even if there is no price update it can be executed after this amount of blocks
     */
    function setMaxOperWaitingBlk(uint256 maxOperWaitingBlk_) external onlyAuthorizedChanger {
        if (minOperWaitingBlk > maxOperWaitingBlk_) revert InvalidValue();
        maxOperWaitingBlk = maxOperWaitingBlk_;
    }

    /**
     * @notice sets MocMultiCollateralGuard contract address
     * @param mocMultiCollateralGuardAddress_ new MocMultiCollateralGuard contract address
     */
    function setMocMultiCollateralGuard(
        MocMultiCollateralGuard mocMultiCollateralGuardAddress_
    ) external onlyAuthorizedChanger {
        mocMultiCollateralGuard = mocMultiCollateralGuardAddress_;
    }

    /**
     * @notice registers the mocOperations bucket that would operate over this queue
     * @param bucket_ address of the mocOperations implementation to interact with
     */
    function registerBucket(MocOperations bucket_) external onlyAuthorizedChanger {
        if (address(mocOperations) != address(0)) revert BucketAlreadyRegistered();
        mocOperations = bucket_;
    }

    /**
     * @notice allows OperIdCount and firstOperId initialization
     * @dev useful while migrating from and existing Operation Id count, initialize this
     * values to avoid IDs duplications. Make sure the queue is paused so no operations
     * can "front run" this assignment.
     * @param operIdCount_ value to be assign to OperIdCount
     * @param firstOperId_ value to be assign to firstOperId
     */
    function initOperId(uint256 operIdCount_, uint256 firstOperId_) external onlyAuthorizedChanger {
        operIdCount = operIdCount_;
        firstOperId = firstOperId_;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
