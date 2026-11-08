// SPDX-License-Identifier: UNLICENSED
/* solhint-disable max-states-count */
pragma solidity 0.8.24;

import { IMocRC20 } from "../interfaces/IMocRC20.sol";
import { IPriceProvider } from "../interfaces/IPriceProvider.sol";
import { IDataProvider } from "../interfaces/IDataProvider.sol";
import { MocUpgradable } from "../governance/MocUpgradable.sol";
import { IMocQueue } from "../interfaces/IMocQueue.sol";
import { IMocMultiCollateralGuard } from "../interfaces/IMocMultiCollateralGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MocBaseBucket: Moc Collateral Bag
 * @notice MocBaseBucket holds Bucket Zero state, both for the Collateral Bag and PeggedTokens Items.
 * @dev Abstracts all rw operations on the main bucket and expose all calculations relative to its state.
 */
abstract contract MocBaseBucket is MocUpgradable {
    // ------- Custom Errors -------
    error MissingProviderPrice(address priceProviderAddress_);
    error Liquidated();
    error LowCoverage(uint256 cglb_, uint256 covThrld_);
    error RecipientMustBeSender();
    error OnlyMultiCollateralGuard();

    // ------- Structs -------
    struct PegContainerItem {
        // total supply of Pegged Token
        uint256 nTP;
        // PegToken PriceFeed address
        IPriceProvider priceProvider;
    }

    struct PeggedTokenIndex {
        // Pegged Token index
        uint256 index;
        // true if Pegged Token exists
        bool exists;
    }

    struct InitializeBaseBucketParams {
        // MocQueue contract address
        address payable mocQueueAddress;
        // Fee Token contract address
        address feeTokenAddress;
        // Fee Token price provider address
        address feeTokenPriceProviderAddress;
        // Collateral Token contract address
        address tcTokenAddress;
        // Moc Fee Flow contract address
        address mocFeeFlowAddress;
        // moc appreciation beneficiary Address
        address mocAppreciationBeneficiaryAddress;
        // protected state threshold [PREC]
        uint256 protThrld;
        // liquidation coverage threshold [PREC]
        uint256 liqThrld;
        // operations fees values for each operation type
        OperationsFeeParams operationsFeeParams;
        // pct of the gain because Pegged Tokens devaluation that is transferred
        // in Collateral Asset to Moc Fee Flow during the settlement [PREC]
        uint256 successFee;
        // pct of the gain because Pegged Tokens devaluation that is returned
        // in Pegged Tokens to appreciation beneficiary during the settlement [PREC]
        uint256 appreciationFactor;
        // time between settlements
        uint256 settlementTimeSpan;
        // TC interest collector address
        address tcInterestCollectorAddress;
        // pct interest charged to TC holders on the total collateral in the protocol [PREC]
        uint256 tcInterestRate;
        // amount of seconds to wait for next TC interest payment
        uint256 tcInterestPaymentTimeSpan;
        // max absolute operation provider address:
        //  absolute maximum transaction allowed for a certain number of time
        //  if absoluteAccumulator is above the value provided the operation will be rejected
        address maxAbsoluteOpProviderAddress;
        // max operation difference provider address:
        //  differential maximum transaction allowed for a certain number of time
        //  if operationalDifference is above the value provided the operation will be rejected
        address maxOpDiffProviderAddress;
        // number of seconds that have to elapse for the linear decay factor to be 0
        uint256 decayTimeSpan;
        // flag to allow users operate using another address as the recipient of the tokens
        bool allowDifferentRecipient;
    }

    struct OperationsFeeParams {
        // additional fee pct applied on Collateral Tokens mint [PREC]
        uint256 tcMintFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
        // additional fee pct applied on Collateral Tokens redeem [PREC]
        uint256 tcRedeemFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
        // additional fee pct applied on swap a Pegged Token for another Pegged Token [PREC]
        uint256 swapTPforTPFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
        // additional fee pct applied on swap a Pegged Token for Collateral Token [PREC]
        uint256 swapTPforTCFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
        // additional fee pct applied on swap Collateral Token for a Pegged Token [PREC]
        uint256 swapTCforTPFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
        // additional fee pct applied on redeem Collateral Token and Pegged Token in one operations [PREC]
        uint256 redeemTCandTPFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
        // additional fee pct applied on mint Collateral Token and Pegged Token in one operation [PREC]
        uint256 mintTCandTPFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
        // pct retain on fees to be re-injected as Collateral, while paying fees with AC [PREC]
        uint256 feeRetainer;
        // pct applied on the top of the operation`s fee when using Fee Token as fee payment method [PREC]
        // e.g. if tcMintFee = 1%, feeTokenPct = 50% => qFeeToken = 0.5%
        uint256 feeTokenPct;
    }

    // ------- Storage -------

    // Fee Token
    IERC20 public feeToken;
    // Fee Token price provider
    IPriceProvider public feeTokenPriceProvider;
    // total amount of Collateral Asset held in the Collateral Bag
    // WARN: On RC20 implementation, this correlates with contract acBalance
    uint256 public nACcb;
    // amount of Collateral Asset that the Vaults owe to the Collateral Bag
    // this variable is not used and is reserved for a future upgrade of the protocol
    // slither-disable-next-line constable-states
    uint256 internal nACioucb;

    // Collateral Token
    IMocRC20 public tcToken;
    // Collateral Token in the Collateral Bag
    uint256 public nTCcb;

    // Pegged Tokens MocRC20 addresses
    IMocRC20[] public tpTokens;
    // Pegged Token indexes
    mapping(address => PeggedTokenIndex) public peggedTokenIndex;
    // peg container
    PegContainerItem[] public pegContainer;
    // Pegged Token prices, at which they can be redeemed after liquidation event
    uint256[] public tpLiqPrices;
    // pct of the gain because Pegged Tokens devaluation that is transferred
    // in Collateral Asset to Moc Fee Flow during the settlement [PREC]
    uint256 public successFee;
    // pct of the gain because Pegged Tokens devaluation that is returned
    // in Pegged Tokens to appreciation beneficiary during the settlement [PREC]
    uint256 public appreciationFactor;

    // ------- Storage Fees -------

    // pct retain on fees to be re-injected as Collateral, while paying fees with AC [PREC]
    uint256 public feeRetainer; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
    // additional fee pct applied on Collateral Tokens mint [PREC]
    uint256 public tcMintFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
    // additional fee pct applied on Collateral Tokens redeem [PREC]
    uint256 public tcRedeemFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
    // additional fee pct applied on swap a Pegged Token for another Pegged Token [PREC]
    uint256 public swapTPforTPFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
    // additional fee pct applied on swap a Pegged Token for Collateral Token [PREC]
    uint256 public swapTPforTCFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
    // additional fee pct applied on swap Collateral Token for a Pegged Token [PREC]
    uint256 public swapTCforTPFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
    // additional fee pct applied on redeem Collateral Token and Pegged Token in one operations [PREC]
    uint256 public redeemTCandTPFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
    // additional fee pct applied on mint Collateral Token and Pegged Token in one operation [PREC]
    uint256 public mintTCandTPFee; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
    // pct applied on the top of the operation`s fee when using Fee Token as fee payment method [PREC]
    // e.g. if tcMintFee = 1%, FeeTokenPct = 50% => qFeeToken = 0.5%
    uint256 public feeTokenPct; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18

    // Pegged Token => addition fee pct applied on TP mint [PREC]
    mapping(address => uint256) public tpMintFees; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
    // Pegged Token =>  addition fee pct applied on TP redeem [PREC]
    mapping(address => uint256) public tpRedeemFees; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18

    // Moc Fee Flow contract address
    address public mocFeeFlowAddress;
    // Moc appreciation beneficiary address
    address public mocAppreciationBeneficiaryAddress;

    // ------- Storage Coverage Tracking -------

    // Target coverage for each Pegged Token [PREC]
    uint256[] public tpCtarg;
    // Coverage protected state threshold [PREC]
    uint256 public protThrld;
    // Coverage liquidation threshold [PREC]
    uint256 public liqThrld;
    // Liquidation enabled
    bool public liqEnabled;
    // Irreversible state, peg lost, contract is terminated and all funds can be withdrawn
    bool public liquidated;
    // flag to allow users operate using another address as the recipient of the tokens
    bool internal _allowDifferentRecipient;

    // ------- Storage Settlement -------

    // time between settlements
    uint256 public settlementTimeSpan;
    // next settlement time
    uint256 public nextSettlementTime;

    // ------- Storage Queue -------

    // amount of AC locked on MocQueue for pending operations
    uint256 public qACLockedInPending;
    // address for MocQueue contract
    address payable public mocQueue; // cannot used MocQueue, import failed due circular reference

    // ------- Storage Success Fee Tracking -------

    // profit and loss in collateral asset for each Pegged Token because its devaluation [N]
    // if it is positive it is a profit that will be distributed and reset during settlement
    int256[] internal tpiou;
    // Pegged Token price used at last operation(redeem or mint) [PREC]
    uint256[] internal pACtpLstop;

    // ------- Storage Flux Capacitor -------

    // max absolute operation provider:
    //  absolute maximum transaction volume allowed for a certain number of time
    //  if absoluteAccumulator is above the value provided the operation will be rejected
    IDataProvider public maxAbsoluteOpProvider;
    // max operation difference provider:
    //  differential maximum transaction volume allowed for a certain number of time
    //  if operationalDifference is above the value provided the operation will be rejected
    IDataProvider public maxOpDiffProvider;
    // number of seconds that have to elapse for the linear decay factor to be 0
    uint256 public decayTimeSpan;
    // accumulator increased by minting and redeeming TP operations
    uint256 public absoluteAccumulator;
    // accumulator increased by minting and decreased by redeeming TP operations
    int256 public differentialAccumulator;
    // last time an operation was submitted
    uint256 public lastOperationTimeStamp;

    // ------- Storage TC Holders Interest Payment -------

    // TC interest collector address
    address public tcInterestCollectorAddress;
    // pct interest charged to TC holders on the total collateral in the protocol [PREC]
    uint256 public tcInterestRate;
    // amount of seconds to wait for next TC interest payment
    uint256 public tcInterestPaymentTimeSpan;
    // next TC interest payment time
    uint256 public nextTCInterestPayment;

    // ------- Modifiers -------
    /// @notice functions with this modifier reverts being in liquidated state
    modifier notLiquidated() {
        _checkLiquidated();
        _;
    }

    /// @notice functions with this modifier reverts if recipient is another address and is not allowed
    modifier checkRecipient(address sender_, address recipient_) {
        _checkRecipient(sender_, recipient_);
        _;
    }

    /// @notice functions with this modifier can only be called by the MultiCollateralGuard contract
    modifier onlyMultiCollateralGuard() {
        if (msg.sender != address(_getMocMultiCollateralGuard())) revert OnlyMultiCollateralGuard();
        _;
    }

    // ------- Initializer -------
    /**
     * @notice contract initializer
     * @param initializeBaseBucketParams_ contract initializer params
     * @dev   mocQueueAddress address for MocQueue contract
     *        feeTokenAddress Fee Token contract address
     *        feeTokenPriceProviderAddress Fee Token price provider contract address
     *        tcTokenAddress Collateral Token contract address
     *        mocFeeFlowAddress Moc Fee Flow contract address
     *        mocAppreciationBeneficiaryAddress Moc appreciation beneficiary address
     *        protThrld protected coverage threshold [PREC]
     *        liqThrld liquidation coverage threshold [PREC]
     *        feeRetainer pct retain on fees to be re-injected as Collateral, while paying fees with AC [PREC]
     *        tcMintFee additional fee pct applied on mint Collateral Tokens operations [PREC]
     *        tcRedeemFee additional fee pct applied on redeem Collateral Tokens operations [PREC]
     *        swapTPforTPFee additional fee pct applied on swap a Pegged Token for another Pegged Token [PREC]
     *        swapTPforTCFee additional fee pct applied on swap a Pegged Token for Collateral Token [PREC]
     *        swapTCforTPFee additional fee pct applied on swap Collateral Token for a Pegged Token [PREC]
     *        redeemTCandTPFee additional fee pct applied on redeem Collateral Token and Pegged Token [PREC]
     *        mintTCandTPFee additional fee pct applied on mint Collateral Token and Pegged Token [PREC]
     *        feeTokenPct pct applied on the top of the operation`s fee when using
     *          Fee Token as fee payment method [PREC]
     *        successFee pct of the gain because Pegged Tokens devaluation that is transferred
     *          in Collateral Asset to Moc Fee Flow during the settlement [PREC]
     *        appreciationFactor pct of the gain because Pegged Tokens devaluation that is returned
     *          in Pegged Tokens to appreciation beneficiary during the settlement [PREC]
     *        settlementTimeSpan time between settlements
     *        tcInterestCollectorAddress TC interest collector address
     *        tcInterestRate pct interest charged to TC holders on the total collateral in the protocol [PREC]
     *        tcInterestPaymentTimeSpan amount of seconds to wait for next TC interest payment
     *        maxAbsoluteOpProviderAddress max absolute operation provider address
     *        maxOpDiffProviderAddress max operation difference provider address
     *        decayTimeSpan number of seconds that have to elapse for the linear decay factor to be 0
     *        allowDifferentRecipient flag to allow users operate using another address as the recipient of the tokens
     */
    function __MocBaseBucket_init_unchained(
        InitializeBaseBucketParams calldata initializeBaseBucketParams_
    ) internal onlyInitializing {
        mocQueue = initializeBaseBucketParams_.mocQueueAddress;
        feeToken = IERC20(initializeBaseBucketParams_.feeTokenAddress);
        feeTokenPriceProvider = IPriceProvider(initializeBaseBucketParams_.feeTokenPriceProviderAddress);
        tcToken = IMocRC20(initializeBaseBucketParams_.tcTokenAddress);
        mocFeeFlowAddress = initializeBaseBucketParams_.mocFeeFlowAddress;
        mocAppreciationBeneficiaryAddress = initializeBaseBucketParams_.mocAppreciationBeneficiaryAddress;
        protThrld = initializeBaseBucketParams_.protThrld;
        liqThrld = initializeBaseBucketParams_.liqThrld;
        tcMintFee = initializeBaseBucketParams_.operationsFeeParams.tcMintFee;
        tcRedeemFee = initializeBaseBucketParams_.operationsFeeParams.tcRedeemFee;
        swapTPforTPFee = initializeBaseBucketParams_.operationsFeeParams.swapTPforTPFee;
        swapTPforTCFee = initializeBaseBucketParams_.operationsFeeParams.swapTPforTCFee;
        swapTCforTPFee = initializeBaseBucketParams_.operationsFeeParams.swapTCforTPFee;
        redeemTCandTPFee = initializeBaseBucketParams_.operationsFeeParams.redeemTCandTPFee;
        mintTCandTPFee = initializeBaseBucketParams_.operationsFeeParams.mintTCandTPFee;
        feeRetainer = initializeBaseBucketParams_.operationsFeeParams.feeRetainer;
        feeTokenPct = initializeBaseBucketParams_.operationsFeeParams.feeTokenPct;
        successFee = initializeBaseBucketParams_.successFee;
        appreciationFactor = initializeBaseBucketParams_.appreciationFactor;
        settlementTimeSpan = initializeBaseBucketParams_.settlementTimeSpan;
        tcInterestCollectorAddress = initializeBaseBucketParams_.tcInterestCollectorAddress;
        tcInterestRate = initializeBaseBucketParams_.tcInterestRate;
        tcInterestPaymentTimeSpan = initializeBaseBucketParams_.tcInterestPaymentTimeSpan;
        maxAbsoluteOpProvider = IDataProvider(initializeBaseBucketParams_.maxAbsoluteOpProviderAddress);
        maxOpDiffProvider = IDataProvider(initializeBaseBucketParams_.maxOpDiffProviderAddress);
        decayTimeSpan = initializeBaseBucketParams_.decayTimeSpan;
        lastOperationTimeStamp = block.timestamp;
        unchecked {
            nextSettlementTime = block.timestamp + initializeBaseBucketParams_.settlementTimeSpan;
            nextTCInterestPayment = block.timestamp + initializeBaseBucketParams_.tcInterestPaymentTimeSpan;
        }
        liquidated = false;
        liqEnabled = false;
        _allowDifferentRecipient = initializeBaseBucketParams_.allowDifferentRecipient;
    }

    // ------- Internal Functions -------

    /**
     * reverts if in liquidated state
     */
    function _checkLiquidated() internal view {
        if (liquidated) revert Liquidated();
    }

    /**
     * reverts if recipient is another address and is not allowed
     */
    function _checkRecipient(address sender_, address recipient_) internal view {
        if (!_allowDifferentRecipient && sender_ != recipient_) revert RecipientMustBeSender();
    }

    /**
     * @notice Adds Collateral Asset to the Bucket
     * @param qAC_ amount of Collateral Asset to add
     */
    function _depositAC(uint256 qAC_) internal {
        nACcb += qAC_;
    }

    /**
     * @notice Adds Collateral Token and Collateral Asset to the Bucket
     * @param qTC_ amount of Collateral Token to add
     * @param qAC_ amount of Collateral Asset to add
     */
    function _depositTC(uint256 qTC_, uint256 qAC_) internal {
        nTCcb += qTC_;
        _depositAC(qAC_);
    }

    /**
     * @notice Subtracts Collateral Token and Collateral Asset from the Bucket
     * @param qTC_ amount of Collateral Token to subtract
     * @param qAC_ amount of Collateral Asset to subtract
     */
    function _withdrawTC(uint256 qTC_, uint256 qAC_) internal {
        nTCcb -= qTC_;
        nACcb -= qAC_;
    }

    /**
     * @notice Adds Pegged Token and Collateral Asset to the Bucket
     * @param i_ Pegged Token index
     * @param qTP_ amount of Pegged Token to add
     * @param qAC_ amount of Collateral Asset to add
     */
    function _depositTP(uint256 i_, uint256 qTP_, uint256 qAC_) internal {
        pegContainer[i_].nTP += qTP_;
        _depositAC(qAC_);
    }

    /**
     * @notice Subtracts Pegged Token and Collateral Asset from the Bucket
     * @param i_ Pegged Token index
     * @param qTP_ amount of Pegged Token to subtract
     * @param qAC_ amount of Collateral Asset to subtract
     */
    function _withdrawTP(uint256 i_, uint256 qTP_, uint256 qAC_) internal {
        pegContainer[i_].nTP -= qTP_;
        nACcb -= qAC_;
    }

    /**
     * @notice Adds Pegged Token and Collateral Asset to the Bucket and mints `qTP_` for Pegged Token `i_`
     * @param i_ Pegged Token index
     * @param qTP_ amount of Pegged Token to add
     * @param qAC_ amount of Collateral Asset to add
     * @param recipient_ the account to mint tokens to
     */
    function _depositAndMintTP(uint256 i_, uint256 qTP_, uint256 qAC_, address recipient_) internal {
        // add qTP and qAC to the Bucket
        _depositTP(i_, qTP_, qAC_);
        // mint qTP to the recipient
        _mintToken(tpTokens[i_], recipient_, qTP_);
    }

    /**
     * @notice subtracts Pegged Token and Collateral Asset from the Bucket and burns `qTP_` for Pegged Token `i_`
     * @param i_ Pegged Token index
     * @param qTP_ amount of Pegged Token to subtract
     * @param qAC_ amount of Collateral Asset to subtract
     */
    function _withdrawAndBurnTP(uint256 i_, uint256 qTP_, uint256 qAC_) internal {
        // sub qTP and qAC from the Bucket
        _withdrawTP(i_, qTP_, qAC_);
        // burn the qTP previously locked from the user
        _burnToken(tpTokens[i_], qTP_);
    }

    /**
     * @notice Adds Collateral Token and Collateral Asset to the Bucket and mints qTCtoMint
     * @param qTC_ amount of Collateral Token to add
     * @param qAC_ amount of Collateral Asset to add
     * @param recipient_ the account to mint tokens to
     */
    function _depositAndMintTC(uint256 qTC_, uint256 qAC_, address recipient_) internal {
        // add qTC to the Bucket
        _depositTC(qTC_, qAC_);
        // mint qTC to the recipient
        _mintToken(tcToken, recipient_, qTC_);
    }

    /**
     * @notice Subtracts Collateral Token and Collateral Asset from the Bucket and burns `qTC_`
     * @param qTC_ amount of Collateral Token to subtract
     * @param qAC_ amount of Collateral Asset to subtract
     */
    function _withdrawAndBurnTC(uint256 qTC_, uint256 qAC_) internal {
        // sub qTC and qAC from the Bucket
        _withdrawTC(qTC_, qAC_);
        // burn the qTC previously locked from the user
        _burnToken(tcToken, qTC_);
    }

    /**
     * @notice mint tokens
     * @param token_ IMocRC20 token to mint
     * @param recipient_ address who receives the tokens
     * @param amount_ amount of tokens to mint
     */
    function _mintToken(IMocRC20 token_, address recipient_, uint256 amount_) internal {
        // slither-disable-next-line unused-return
        token_.mint(recipient_, amount_);
    }

    /**
     * @notice burn tokens
     * @param token_ IMocRC20 token to burn
     * @param amount_ amount of tokens to burn
     */
    function _burnToken(IMocRC20 token_, uint256 amount_) internal {
        // slither-disable-next-line unused-return
        token_.burn(address(this), amount_);
    }

    /**
     * @notice gets MocMultiCollateralGuard contract
     */
    function _getMocMultiCollateralGuard() internal view returns (IMocMultiCollateralGuard) {
        return IMocMultiCollateralGuard(IMocQueue(mocQueue).mocMultiCollateralGuard());
    }

    /**
     * @notice get amount of Collateral Asset available considering how many are locked by Pegged Token adjusted by EMA
     * @param ctargemaCA_ target coverage adjusted by the moving average of the value of the Collateral Asset [PREC]
     * @param lckAC_ amount of Collateral Asset locked by Pegged Token [N]
     * @param nACgain_ amount of collateral asset to be distributed during settlement [N]
     * @return lckACemaAdjusted [PREC]
     */
    function _getLckACemaAdjusted(
        uint256 ctargemaCA_,
        uint256 lckAC_,
        uint256 nACgain_
    ) internal view returns (int256 lckACemaAdjusted) {
        // [PREC] = [N] * [PREC] - [PREC] * [N]
        return int256(_getTotalACavailable(nACgain_) * PRECISION) - int256(ctargemaCA_ * lckAC_);
    }

    /**
     * @notice get amount of Collateral Token available to redeem
     * @param ctargemaCA_ target coverage adjusted by the moving average of the value of the Collateral Asset [PREC]
     * @param lckAC_ amount of Collateral Asset locked by Pegged Token [N]
     * @param nACgain_ amount of collateral asset to be distributed during settlement [N]
     * @return tcAvailableToRedeem [N]
     */
    function _getTCAvailableToRedeem(
        uint256 ctargemaCA_,
        uint256 lckAC_,
        uint256 nACgain_
    ) internal view virtual returns (uint256 tcAvailableToRedeem) {
        // [PREC]
        int256 lckACemaAdjusted = _getLckACemaAdjusted(ctargemaCA_, lckAC_, nACgain_);
        if (lckACemaAdjusted <= 0) return 0;
        // [N] = [PREC] / [PREC]
        return uint256(lckACemaAdjusted) / _getPTCac(lckAC_, nACgain_);
    }

    /**
     * @notice get signed amount of Pegged Token available to mint
     * @dev negative value is needed for multi collateral implementation
     * @param ctargemaCA_ target coverage adjusted by the moving average of the value of the Collateral Asset
     * @param ctargemaTP_ target coverage adjusted by the moving average of the value of a Pegged Token
     * @param pACtp_ Collateral Asset price in amount of Pegged Token [PREC]
     * @param lckAC_ amount of Collateral Asset locked by Pegged Token [N]
     * @param nACgain_ amount of collateral asset to be distributed during settlement [N]
     * @return tpAvailableToMint [N]
     */
    function _getTPAvailableToMintSigned(
        uint256 ctargemaCA_,
        uint256 ctargemaTP_,
        uint256 pACtp_,
        uint256 lckAC_,
        uint256 nACgain_
    ) internal view returns (int256 tpAvailableToMint) {
        int256 lckACemaAdjusted = _getLckACemaAdjusted(ctargemaCA_, lckAC_, nACgain_);
        // [N] = [PREC] * [PREC] / ([PREC]) * [PREC])
        return (lckACemaAdjusted * int256(pACtp_)) / int256((ctargemaTP_ - ONE) * PRECISION);
    }

    /**
     * @notice evaluates whether or not the coverage is over the cThrld_, reverts if below
     * @param cThrld_ coverage threshold to check for [PREC]
     * @param pACtps_ array of all AC prices for each TP, with [PREC]
     * @return lckAC amount of Collateral Asset locked by Pegged Tokens [PREC]
     * @return nACgain amount of collateral asset to be distributed during settlement [N]
     */
    function _evalCoverage(
        uint256 cThrld_,
        uint256[] memory pACtps_
    ) internal view returns (uint256 lckAC, uint256 nACgain) {
        (lckAC, nACgain) = _calcLckACandACgain(pACtps_);
        uint256 cglb = _getCglb(lckAC, nACgain);
        // check if coverage is above the given threshold
        if (cglb <= cThrld_) revert LowCoverage(cglb, cThrld_);
    }

    /**
     * @notice evaluates whether or not the coverage is over the cThrld_, reverts if below
     * @param cThrld_ coverage threshold to check for [PREC]
     */
    function _evalCombinedCoverage(uint256 combinedCglb_, uint256 cThrld_) internal pure {
        // check if coverage is above the given threshold
        if (combinedCglb_ < cThrld_) revert LowCoverage(combinedCglb_, cThrld_);
    }

    /**
     * @notice indicates whether or not PnL should be tracked
     * @dev if both successFee and appreciationFactor are zero, there is no point
     * to track and store PnL, so these features are considered disabled.
     */
    function _isPnLTrackingEnabled() internal view returns (bool) {
        return (successFee != 0 || appreciationFactor != 0);
    }

    /**
     * @notice updates Pegged Token P&L and last operation price
     * @param i_ Pegged Token index
     * @param pACtp_ Pegged Token price [PREC]
     */
    function _updateTPtracking(uint256 i_, uint256 pACtp_) internal {
        if (_isPnLTrackingEnabled()) {
            tpiou[i_] += _calcOtfPnLTP(i_, pACtp_);
            pACtpLstop[i_] = pACtp_;
        }
    }

    /**
     * @notice calculates on the fly Pegged Token P&L
     * @param i_ Pegged Token index
     * @param pACtp_ Pegged Token price [PREC]
     * @return otfPnLtp [N]
     */
    function _calcOtfPnLTP(uint256 i_, uint256 pACtp_) internal view returns (int256 otfPnLtp) {
        // [PREC] = [N] * [PREC]
        uint256 nTP = pegContainer[i_].nTP * PRECISION;
        // [N] = [PREC] / [PREC] - [PREC] / [PREC]
        return int256(nTP / pACtpLstop[i_]) - int256(nTP / pACtp_);
    }

    /**
     * @notice gets accumulated Pegged Token P&L
     * @param i_ Pegged Token index
     * @param pACtp_ Pegged Token price [PREC]
     * @return tpGain amount of Pegged Token to be minted during settlement [N]
     * @return adjPnLtpi total amount of P&L in Collateral Asset [N]
     */
    function _getPnLTP(uint256 i_, uint256 pACtp_) internal view returns (uint256 tpGain, uint256 adjPnLtpi) {
        if (_isPnLTrackingEnabled()) {
            // [N] = [N] + [N]
            int256 adjPnLtpiAux = tpiou[i_] + _calcOtfPnLTP(i_, pACtp_);
            if (adjPnLtpiAux > 0) {
                adjPnLtpi = uint256(adjPnLtpiAux);
                // [N] = (([PREC] * [PREC] / [PREC]) * [N]) / [PREC]
                tpGain = _mulPrec(_mulPrec(appreciationFactor, pACtp_), adjPnLtpi);
            }
        }
    }

    /**
     * @notice get amount of Collateral Asset locked by Pegged Token and
     *  amount of collateral asset to be distributed during settlement
     * @return lckAC [N]
     * @return nACgain [N]
     */
    function _getLckACandACgain(uint256[] memory pACtps_) internal view returns (uint256 lckAC, uint256 nACgain) {
        return _calcLckACandACgain(pACtps_);
    }

    /**
     * @notice calculates the amount of Collateral Asset locked by Pegged Token and
     *  amount of collateral asset to be distributed during settlement
     * @param pACtps_ array of all AC prices for each TP, with [PREC]
     * @return lckAC [N]
     * @return nACgain [N]
     */
    function _calcLckACandACgain(uint256[] memory pACtps_) internal view returns (uint256 lckAC, uint256 nACgain) {
        uint256 pegAmount = pegContainer.length;
        for (uint256 i = 0; i < pegAmount; i = unchecked_inc(i)) {
            uint256 pACtp = pACtps_[i];
            (uint256 tpGain, uint256 adjPnLtpi) = _getPnLTP(i, pACtp);
            // [N] = ([N] + [N]) * [PREC] / [PREC]
            lckAC += _divPrec(pegContainer[i].nTP + tpGain, pACtp);
            nACgain += adjPnLtpi;
        }
        // [N] = [N] * [PREC] / [PREC]
        nACgain = _mulPrec(nACgain, successFee);
        return (lckAC, nACgain);
    }

    /**
     * @notice get total Collateral Asset available
     * @param nACgain_ amount of collateral asset to be distributed during settlement [N]
     * @return totalACavailable [N]
     */
    function _getTotalACavailable(uint256 nACgain_) internal view returns (uint256 totalACavailable) {
        // [N] = [N] - [N]
        return nACcb - nACgain_;
    }

    /**
     * @notice get Collateral Token price
     * @param lckAC_ amount of Collateral Asset locked by Pegged Token [N]
     * @param nACgain_ amount of collateral asset to be distributed during settlement [N]
     * @return pTCac [PREC]
     */
    function _getPTCac(uint256 lckAC_, uint256 nACgain_) internal view returns (uint256 pTCac) {
        // slither-disable-next-line incorrect-equality
        if (nTCcb == 0) return ONE;
        // [PREC] = ([N] - [N]) * [PREC]) / [N]
        return _divPrec((_getTotalACavailable(nACgain_) - lckAC_), nTCcb);
    }

    /**
     * @notice get bucket global coverage
     * @param lckAC_ amount of Collateral Asset locked by Pegged Token [N]
     * @param nACgain_ amount of collateral asset to be distributed during settlement [N]
     * @return cglob [PREC]
     */
    function _getCglb(uint256 lckAC_, uint256 nACgain_) internal view returns (uint256 cglob) {
        // slither-disable-next-line incorrect-equality
        if (lckAC_ == 0) return UINT256_MAX;
        // [PREC] = [N] * [PREC] / [N]
        return _divPrec(_getTotalACavailable(nACgain_), lckAC_);
    }

    function _tpi(address tpAddress) internal view returns (uint256) {
        PeggedTokenIndex storage ptIndex = peggedTokenIndex[tpAddress];
        if (!ptIndex.exists) revert InvalidAddress();
        return ptIndex.index;
    }

    // ------- Public Functions -------

    /**
     * @notice If liquidation is enabled, verifies if forced liquidation has been
     * reached, checking if globalCoverage <= liquidation
     * @return true if liquidation state is reached, false otherwise
     */
    function isLiquidationReached() public view returns (bool) {
        (uint256 lckAC, uint256 nACgain) = _getLckACandACgain(_getPACtps());
        uint256 cglb = _getCglb(lckAC, nACgain);
        return cglb <= liqThrld;
    }

    /**
     * @notice get how many Pegged Token equal 1 Collateral Asset
     * @param tp_ Pegged Token address
     * @return price [PREC]
     */
    function getPACtp(address tp_) external view virtual returns (uint256) {
        return _getPACtp(_tpi(tp_));
    }

    /**
     * @notice return current amount of Tps
     */
    function getTpAmount() external view returns (uint256) {
        return tpTokens.length;
    }

    // ------- Internal Functions -------

    /**
     * @notice get how many Pegged Token equal 1 Collateral Asset
     * @param i_ Pegged Token index
     * @return price [PREC]
     */
    function _getPACtp(uint256 i_) internal view returns (uint256) {
        IPriceProvider priceProvider = pegContainer[i_].priceProvider;
        (uint256 price, bool has) = _peekPrice(priceProvider);
        if (!has) revert MissingProviderPrice(address(priceProvider));
        return price;
    }

    /**
     * @notice ask to a price provider for its token price
     * @dev saves some contract size by using this function instead of calling the external directly
     * @param priceProvider_ Pegged Token index
     * @return price casted to uint256 [PREC]
     * @return has true if has a valid price
     */
    function _peekPrice(IPriceProvider priceProvider_) internal view returns (uint256, bool) {
        (bytes32 price, bool has) = priceProvider_.peek();
        return (uint256(price), has);
    }

    /**
     * @notice gets all TP prices
     * @return pACtps All tps prices [PREC]
     */
    function _getPACtps() internal view returns (uint256[] memory pACtps) {
        uint256 pegAmount = pegContainer.length;
        pACtps = new uint256[](pegAmount);
        for (uint256 i = 0; i < pegAmount; i = unchecked_inc(i)) {
            pACtps[i] = _getPACtp(i);
        }
    }

    // ------- Only Authorized Changer Functions -------

    /**
     * @notice sets operations fees values for each operation type
     */
    function setOperationsFee(OperationsFeeParams calldata operationsFeeParams_) public onlyAuthorizedChanger {
        tcMintFee = operationsFeeParams_.tcMintFee;
        tcRedeemFee = operationsFeeParams_.tcRedeemFee;
        swapTPforTPFee = operationsFeeParams_.swapTPforTPFee;
        swapTPforTCFee = operationsFeeParams_.swapTPforTCFee;
        swapTCforTPFee = operationsFeeParams_.swapTCforTPFee;
        redeemTCandTPFee = operationsFeeParams_.redeemTCandTPFee;
        mintTCandTPFee = operationsFeeParams_.mintTCandTPFee;
        feeRetainer = operationsFeeParams_.feeRetainer;
        feeTokenPct = operationsFeeParams_.feeTokenPct;
    }

    /**
     * @dev sets Moc Fee Flow contract address
     * @param mocFeeFlowAddress_ moc Fee Flow new contract address
     */
    function setMocFeeFlowAddress(address mocFeeFlowAddress_) external onlyAuthorizedChanger {
        // slither-disable-next-line missing-zero-check
        mocFeeFlowAddress = mocFeeFlowAddress_;
    }

    /**
     * @dev sets Fee Token contract and price provider contract addresses
     * @param mocFeeTokenAddress_ Fee Token new contract address
     * @param mocFeeTokenPriceProviderAddress_ Fee Token price provider new contract address
     */
    function setFeeTokenParams(
        address mocFeeTokenAddress_,
        address mocFeeTokenPriceProviderAddress_
    ) external onlyAuthorizedChanger {
        // slither-disable-next-line missing-zero-check
        feeToken = IERC20(mocFeeTokenAddress_);
        // slither-disable-next-line missing-zero-check
        feeTokenPriceProvider = IPriceProvider(mocFeeTokenPriceProviderAddress_);
    }

    /**
     * @dev sets the coverage thresholds configuration params
     * @param protThrld_ coverage protected state threshold [PREC]
     * @param liqThrld_ liquidation threshold
     */
    function setCoverageThresholds(uint256 protThrld_, uint256 liqThrld_) external onlyAuthorizedChanger {
        protThrld = protThrld_;
        liqThrld = liqThrld_;
    }

    /**
     * @dev enables and disables the liquidation mechanism.
     * @param liqEnabled_ is liquidation enabled
     */
    function setLiqEnabled(bool liqEnabled_) external onlyAuthorizedChangerOrPauser {
        liqEnabled = liqEnabled_;
    }

    /**
     * @notice sets success Fee and appreciation Factor values.
     * @dev if P&L tracking was disabled (both values in zero) and it's being activited, pACtpLstop values
     * get reseted for each TP.
     * @param successFee_ pct of the gain because Pegged Tokens devaluation that is
     * transferred in Collateral Asset to Moc Fee Flow during the settlement [PREC]
     * @param appreciationFactor_ pct of the gain because Pegged Tokens devaluation that is returned
     * in Pegged Tokens to appreciation beneficiary during the settlement [PREC]
     * @param mocAppreciationBeneficiaryAddress_ moc Appreciation Beneficiary new address
     */
    function setSuccessFeeParams(
        uint256 successFee_,
        uint256 appreciationFactor_,
        address mocAppreciationBeneficiaryAddress_
    ) external onlyAuthorizedChanger {
        // If PnLTracking was disabled, we reset last Oepration pACtp to avoid incorrect pnl calculations
        if (!_isPnLTrackingEnabled()) {
            uint256 pegAmount = pegContainer.length;
            for (uint256 i = 0; i < pegAmount; i = unchecked_inc(i)) {
                pACtpLstop[i] = _getPACtp(i);
            }
        }
        successFee = successFee_;
        appreciationFactor = appreciationFactor_;
        // slither-disable-next-line missing-zero-check
        mocAppreciationBeneficiaryAddress = mocAppreciationBeneficiaryAddress_;
    }

    /**
     * @dev sets TC interest params
     * @param tcInterestCollectorAddress_ TC interest collector address
     * @param tcInterestRate_ pct interest charged to TC holders on the total collateral in the protocol [PREC]
     * @param tcInterestPaymentTimeSpan_ amount of seconds to wait for next TC interest payment
     * @dev nextTCInterestPayment is not automatically updated, you have to wait until next
     *  interest payment to be made : nextTCInterestPayment = block.timestamp + tcInterestPaymentTimeSpan
     */
    function setTCInterestParams(
        address tcInterestCollectorAddress_,
        uint256 tcInterestRate_,
        uint256 tcInterestPaymentTimeSpan_
    ) external onlyAuthorizedChanger {
        // slither-disable-next-line missing-zero-check
        tcInterestCollectorAddress = tcInterestCollectorAddress_;
        // max interest rate allowed == 1%
        if (tcInterestRate_ > PRECISION / 100) revert InvalidValue();
        tcInterestRate = tcInterestRate_;
        tcInterestPaymentTimeSpan = tcInterestPaymentTimeSpan_;
    }

    /**
     * @param settlementTimeSpan_ time between settlements
     * @dev settlementTimeSpan is not automatically updated, you have to wait until next
     * settlement to be made : nextSettlementTime = block.timestamp + settlementTimeSpan
     **/
    function setSettlementTimeSpan(uint256 settlementTimeSpan_) external onlyAuthorizedChanger {
        settlementTimeSpan = settlementTimeSpan_;
    }

    /**
     * @dev sets flux capacitor providers addresses
     * @param maxAbsoluteOpProviderAddress_ max absolute operation provider address
     * @param maxOpDiffProviderAddress_ max operation difference provider address
     * @param decayTimeSpan_ flux capacitor decay time span
     */
    function setFluxCapacitorParams(
        address maxAbsoluteOpProviderAddress_,
        address maxOpDiffProviderAddress_,
        uint256 decayTimeSpan_
    ) external onlyAuthorizedChanger {
        // slither-disable-next-line missing-zero-check
        maxAbsoluteOpProvider = IDataProvider(maxAbsoluteOpProviderAddress_);
        // slither-disable-next-line missing-zero-check
        maxOpDiffProvider = IDataProvider(maxOpDiffProviderAddress_);
        // slither-disable-next-line missing-zero-check
        decayTimeSpan = decayTimeSpan_;
    }

    /**
     * @dev sets Moc Queue contract address
     * @param mocQueueAddress_ Moc queue new contract address
     */
    function setMocQueue(address payable mocQueueAddress_) external onlyAuthorizedChanger {
        // slither-disable-next-line missing-zero-check
        mocQueue = mocQueueAddress_;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */

    // Purposely left unused to save some state space to allow for future upgrades
    // slither-disable-next-line unused-state
    uint256[50] private __gap;
}
