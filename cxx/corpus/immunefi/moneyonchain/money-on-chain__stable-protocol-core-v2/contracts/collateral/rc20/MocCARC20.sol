// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

// solhint-disable-next-line no-unused-import
import { MocCore } from "../../core/MocCore.sol";
import { MocOperations } from "../../core/MocOperations.sol";
import { MocQueueExecFees } from "../../queue/MocQueueExecFees.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MocCARC20: Moc Collateral Asset RC20
 * @notice Moc protocol implementation using a RC20 as Collateral Asset.
 * @dev WARNING: Fee-on-transfer tokens are NOT supported as collateral.
 *  Using them may result in incorrect accounting or loss of funds, ensure that AC token has standard ERC20 behaviors.
 */
contract MocCARC20 is MocOperations {
    // ------- Structs -------
    struct InitializeParams {
        InitializeCoreParams initializeCoreParams;
        // Collateral Asset Token contract address
        address acTokenAddress;
    }

    // ------- Storage -------
    // Collateral Asset token
    IERC20 private _acToken;

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
     *      acTokenAddress Collateral Asset Token contract address
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
     */
    function initialize(InitializeParams calldata initializeParams_) external initializer {
        __MocCore_init(initializeParams_.initializeCoreParams);
        _acToken = IERC20(initializeParams_.acTokenAddress);
    }

    // ------- Internal Functions -------

    /**
     * @inheritdoc MocCore
     * @dev this function could revert during safeTransfer call.
     *  safeTransfer will revert if token transfer reverts or returns 0
     */
    function acTransfer(address to_, uint256 amount_) internal override {
        if (amount_ > 0) {
            SafeERC20.safeTransfer(_acToken, to_, amount_);
        }
    }

    /**
     * @inheritdoc MocCore
     */
    function acBalanceOf(address account) internal view override returns (uint256 balance) {
        return _acToken.balanceOf(account);
    }

    /**
     * @inheritdoc MocCore
     */
    function acToken() external view override returns (address) {
        return address(_acToken);
    }

    /**
     * @inheritdoc MocCore
     */
    function refreshACBalance() external override {
        uint256 unaccountedAcBalance = acBalanceOf(address(this)) - nACcb - qACLockedInPending;
        // On this implementation, AC token balance is nACcb plus AC locked on pending operations
        if (unaccountedAcBalance > 0) _depositAC(unaccountedAcBalance);
    }

    /**
     * @inheritdoc MocOperations
     */
    function _lockACInPending(uint256 qACToLock_) internal override {
        super._lockACInPending(qACToLock_);
        SafeERC20.safeTransferFrom(_acToken, msg.sender, address(this), qACToLock_);
    }

    /**
     * @inheritdoc MocOperations
     */
    function _getExecFeeSent(
        uint256 qACmax_,
        MocQueueExecFees.OperType operType_
    ) internal override returns (uint256 qACmax, uint256 execFee) {
        // For RC20 solutions, msg.value should be the execution Fee
        // the user is willing to pay for this OperType
        MocQueueExecFees(mocQueue).verifyExecFeeRC20(operType_, msg.value);
        return (qACmax_, msg.value);
    }

    // ------- External Functions -------

    /**
     * @notice caller sends Collateral Asset and recipient receives Collateral Token
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     *   Requires prior sender approval of Collateral Asset to this contract
     * @param qTC_ amount of Collateral Token to mint
     * @param qACmax_ maximum amount of Collateral Asset that can be spent
     * @param recipient_ address who receives the Collateral Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor, `0x0` if not using a vendor
     * @return operId Identifier to track the Operation lifecycle
     */
    function mintTC(
        uint256 qTC_,
        uint256 qACmax_,
        address recipient_,
        address vendor_
    ) external payable returns (uint256 operId) {
        return _mintTCtoViaVendor(qTC_, qACmax_, recipient_, vendor_);
    }

    /**
     * @notice caller sends Collateral Asset and recipient receives Pegged Token
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     *   Requires prior sender approval of Collateral Asset to this contract
     * @param tp_ Pegged Token address to mint
     * @param qTP_ amount of Pegged Token to mint
     * @param qACmax_ maximum amount of Collateral Asset that can be spent
     * @param recipient_ address who receives the Pegged Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     * @return operId Identifier to track the Operation lifecycle
     */
    function mintTP(
        address tp_,
        uint256 qTP_,
        uint256 qACmax_,
        address recipient_,
        address vendor_
    ) external payable returns (uint256 operId) {
        return _mintTPtoViaVendor(tp_, qTP_, qACmax_, recipient_, vendor_);
    }

    /**
     * @notice caller sends Collateral Asset and recipient receives Collateral Token and Pegged Token
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     *  Requires prior sender approval of Collateral Asset to this contract
     *  This operation is done without checking coverage
     *  Collateral Token and Pegged Token are minted in equivalent proportions so that its price
     *  and global coverage are not modified.
     *  Reverts if qAC sent are insufficient.
     * @param tp_ Pegged Token address
     * @param qTP_ amount of Pegged Token to mint
     * @param qACmax_ maximum amount of Collateral Asset that can be spent
     * @param recipient_ address who receives the Collateral Token and Pegged Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     * @return operId Identifier to track the Operation lifecycle
     */
    function mintTCandTP(
        address tp_,
        uint256 qTP_,
        uint256 qACmax_,
        address recipient_,
        address vendor_
    ) external payable returns (uint256 operId) {
        return _mintTCandTPtoViaVendor(tp_, qTP_, qACmax_, recipient_, vendor_);
    }

    /**
     * @notice caller sends a Pegged Token and recipient receives another one
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     * @param tpFrom_ owned Pegged Token address
     * @param tpTo_ target Pegged Token address
     * @param qTP_ amount of owned Pegged Token to swap
     * @param qTPmin_ minimum amount of target Pegged Token that `recipient_` expects to receive
     * @param qACmax_ maximum amount of Collateral Asset that can be spent in fees
     * @param recipient_ address who receives the target Pegged Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     * @return operId Identifier to track the Operation lifecycle
     */
    function swapTPforTP(
        address tpFrom_,
        address tpTo_,
        uint256 qTP_,
        uint256 qTPmin_,
        uint256 qACmax_,
        address recipient_,
        address vendor_
    ) external payable returns (uint256 operId) {
        return _swapTPforTPtoViaVendor(tpFrom_, tpTo_, qTP_, qTPmin_, qACmax_, recipient_, vendor_);
    }

    /**
     * @notice caller sends a Pegged Token and recipient receives Collateral Token
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     * @param tp_ Pegged Token address
     * @param qTP_ amount of owned Pegged Token to swap
     * @param qTCmin_ minimum amount of Collateral Token that `recipient_` expects to receive
     * @param qACmax_ maximum amount of Collateral Asset that can be spent in fees
     * @param recipient_ address who receives the Collateral Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     * @return operId Identifier to track the Operation lifecycle
     */
    function swapTPforTC(
        address tp_,
        uint256 qTP_,
        uint256 qTCmin_,
        uint256 qACmax_,
        address recipient_,
        address vendor_
    ) external payable returns (uint256 operId) {
        return _swapTPforTCtoViaVendor(tp_, qTP_, qTCmin_, qACmax_, recipient_, vendor_);
    }

    /**
     * @notice Caller sends a Collateral Token and recipient receives Pegged Token.
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not.
     * @param tp_ Pegged Token address
     * @param qTC_ Amount of owned Collateral Token to swap
     * @param qTPmin_ Minimum amount of Pegged Token that `recipient_` expects to receive
     * @param qACmax_ Maximum amount of Collateral Asset that can be spent in fees
     * @param recipient_ Address who receives the Pegged Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     * @return operId Identifier to track the Operation lifecycle
     */
    function swapTCforTP(
        address tp_,
        uint256 qTC_,
        uint256 qTPmin_,
        uint256 qACmax_,
        address recipient_,
        address vendor_
    ) external payable returns (uint256 operId) {
        return _swapTCforTPtoViaVendor(tp_, qTC_, qTPmin_, qACmax_, recipient_, vendor_);
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
