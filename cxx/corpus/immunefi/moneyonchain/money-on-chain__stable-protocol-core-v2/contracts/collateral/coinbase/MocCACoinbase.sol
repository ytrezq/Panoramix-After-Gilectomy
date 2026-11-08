// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

// solhint-disable-next-line no-unused-import
import { MocCore } from "../../core/MocCore.sol";
import { MocOperations } from "../../core/MocOperations.sol";
import { MocQueueExecFees } from "../../queue/MocQueueExecFees.sol";

/**
 * @title MocCACoinbase: Moc Collateral Asset Coinbase
 * @notice Moc protocol implementation using network Coinbase as Collateral Asset
 */
contract MocCACoinbase is MocOperations {
    // ------- Structs -------
    struct InitializeParams {
        InitializeCoreParams initializeCoreParams;
        // max amount of gas forwarded on AC transfer
        uint256 transferMaxGas;
    }

    // ------- Storage -------
    // max amount of gas forwarded on AC transfer to avoid
    // using all the gas on the fallback function
    uint256 public transferMaxGas;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ------- Initializer -------
    /**
     * @notice contract initializer
     * @param initializeParams_ contract initializer params
     * @dev governorAddress The address that will define when a change contract is authorized
     *      pauserAddress The address that is authorized to pause this contract
     *      mocCoreExpansion Moc Core Expansion contract address
     *      mocQueueAddress address for MocQueue contract
     *      feeTokenAddress Fee Token contract address
     *      feeTokenPriceProviderAddress Fee Token price provider contract address
     *      tcTokenAddress Collateral Token contract address
     *      mocFeeFlowAddress Moc Fee Flow contract address
     *      mocAppreciationBeneficiaryAddress Moc appreciation beneficiary address
     *      protThrld protected state threshold [PREC]
     *      liqThrld liquidation coverage threshold [PREC]
     *      feeRetainer pct retain on fees to be re-injected as Collateral, while paying fees with AC [PREC]
     *      tcMintFee additional fee pct applied on mint Collateral Tokens operations [PREC]
     *      tcRedeemFee additional fee pct applied on redeem Collateral Tokens operations [PREC]
     *      successFee pct of the gain because Pegged Tokens devaluation that is transferred
     *        in Collateral Asset to Moc Fee Flow during the settlement [PREC]
     *      appreciationFactor pct of the gain because Pegged Tokens devaluation that is returned
     *        in Pegged Tokens to appreciation beneficiary during the settlement [PREC]
     *      settlementTimeSpan time between settlements
     *      tcInterestCollectorAddress TC interest collector address
     *      tcInterestRate pct interest charged to TC holders on the total collateral in the protocol [PREC]
     *      tcInterestPaymentTimeSpan amount of seconds to wait for next TC interest payment
     *      maxAbsoluteOpProviderAddress max absolute operation provider address
     *      maxOpDiffProviderAddress max operation difference provider address
     *      decayTimeSpan number of seconds that have to elapse for the linear decay factor to be 0
     *      emaCalculationTimeSpan amount of seconds to wait between Pegged ema calculation
     *      mocVendors address for MocVendors contract
     *      mocQueueAddress address for MocQueue contract
     *      transferMaxGas max amount of gas forwarded on AC transfer
     */
    function initialize(InitializeParams calldata initializeParams_) external initializer {
        __MocCore_init(initializeParams_.initializeCoreParams);
        transferMaxGas = initializeParams_.transferMaxGas;
    }

    // ------- Internal Functions -------

    /**
     * @inheritdoc MocCore
     */
    function acTransfer(address to_, uint256 amount_) internal override {
        if (amount_ > 0) {
            if (to_ == address(0)) revert InvalidAddress();
            // this transfer is gas capped to avoid spent more than the fixed precalculated execution fees
            // by using the fallback function if `to_` is a contract
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = to_.call{ value: amount_, gas: transferMaxGas }("");
            if (!success) revert TransferFailed();
        }
    }

    /**
     * @inheritdoc MocCore
     */
    function acBalanceOf(address account) internal view override returns (uint256 balance) {
        return account.balance;
    }

    /**
     * @inheritdoc MocCore
     */
    function acToken() external pure override returns (address) {
        return address(0);
    }

    /**
     * @inheritdoc MocCore
     */
    function refreshACBalance() external override {}

    /**
     * @inheritdoc MocOperations
     */
    function _getExecFeeSent(
        uint256 qACTotal_,
        MocQueueExecFees.OperType operType_
    ) internal view override returns (uint256 qACmax, uint256 execFee) {
        return MocQueueExecFees(mocQueue).verifyExecFeeCoinbase(operType_, qACTotal_);
    }

    // ------- External Functions -------

    /**
     * @notice caller sends coinbase as Collateral Asset and recipient receives Collateral Token
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     * @dev any extra value, not spent on TC nor fees, will be return to sender
     * @param qTC_ amount of Collateral Token to mint
     * @param recipient_ address who receives the Collateral Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     * @return operId Identifier to track the Operation lifecycle
     */
    function mintTC(uint256 qTC_, address recipient_, address vendor_) external payable returns (uint256 operId) {
        return _mintTCtoViaVendor(qTC_, msg.value, recipient_, vendor_);
    }

    /**
     * @notice caller sends coinbase as Collateral Asset and recipient receives Pegged Token
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     * @dev any extra value, not spent on TP nor fees, will be return to sender
     * @param tp_ Pegged Token address to mint
     * @param qTP_ amount of Pegged Token to mint
     * @param recipient_ address who receives the Pegged Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     * @return operId Identifier to track the Operation lifecycle
     */
    function mintTP(
        address tp_,
        uint256 qTP_,
        address recipient_,
        address vendor_
    ) external payable returns (uint256 operId) {
        return _mintTPtoViaVendor(tp_, qTP_, msg.value, recipient_, vendor_);
    }

    /**
     * @notice caller sends coinbase as Collateral Asset and recipient receives Collateral Token and Pegged Token
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     *  This operation is done without checking coverage
     *  Collateral Token and Pegged Token are minted in equivalent proportions so that its price
     *  and global coverage are not modified.
     *  Reverts if qAC sent are insufficient.
     * @param tp_ Pegged Token address
     * @param qTP_ amount of Pegged Token to mint
     * @param recipient_ address who receives the Collateral Token and Pegged Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     * @return operId Identifier to track the Operation lifecycle
     */
    function mintTCandTP(
        address tp_,
        uint256 qTP_,
        address recipient_,
        address vendor_
    ) external payable returns (uint256 operId) {
        return _mintTCandTPtoViaVendor(tp_, qTP_, msg.value, recipient_, vendor_);
    }

    /**
     * @notice caller sends a Pegged Token and recipient receives another one
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     * @param tpFrom_ owned Pegged Token address
     * @param tpTo_ target Pegged Token address
     * @param qTP_ amount of owned Pegged Token to swap
     * @param qTPmin_ minimum amount of target Pegged Token that `recipient_` expects to receive
     * @param recipient_ address who receives the target Pegged Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     * @return operId Identifier to track the Operation lifecycle
     */
    function swapTPforTP(
        address tpFrom_,
        address tpTo_,
        uint256 qTP_,
        uint256 qTPmin_,
        address recipient_,
        address vendor_
    ) external payable returns (uint256 operId) {
        return _swapTPforTPtoViaVendor(tpFrom_, tpTo_, qTP_, qTPmin_, msg.value, recipient_, vendor_);
    }

    /**
     * @notice caller sends a Pegged Token and recipient receives Collateral Token
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     * @param tp_ Pegged Token address
     * @param qTP_ amount of owned Pegged Token to swap
     * @param qTCmin_ minimum amount of Collateral Token that `recipient_` expects to receive
     * @param recipient_ address who receives the Collateral Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     * @return operId Identifier to track the Operation lifecycle
     */
    function swapTPforTC(
        address tp_,
        uint256 qTP_,
        uint256 qTCmin_,
        address recipient_,
        address vendor_
    ) external payable returns (uint256 operId) {
        return _swapTPforTCtoViaVendor(tp_, qTP_, qTCmin_, msg.value, recipient_, vendor_);
    }

    /**
     * @notice caller sends Collateral Token and recipient receives Pegged Token
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     * @param tp_ Pegged Token address
     * @param qTC_ amount of Collateral to swap
     * @param qTPmin_ minimum amount of Pegged Token that `recipient_` expects to receive
     * @param recipient_ address who receives the Pegged Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     * @return operId Identifier to track the Operation lifecycle
     */
    function swapTCforTP(
        address tp_,
        uint256 qTC_,
        uint256 qTPmin_,
        address recipient_,
        address vendor_
    ) external payable returns (uint256 operId) {
        return _swapTCforTPtoViaVendor(tp_, qTC_, qTPmin_, msg.value, recipient_, vendor_);
    }

    /**
     * @notice allow to send Coinbase to increment the Collateral Asset in the protocol
     */
    receive() external payable {
        _depositAC(msg.value);
    }

    /**
     * @notice sets max amount of gas forwarded on AC transfer
     * @param transferMaxGas_ new max amount of gas forwarded on AC transfer
     */
    function setTransferMaxGas(uint256 transferMaxGas_) external onlyAuthorizedChanger {
        transferMaxGas = transferMaxGas_;
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
