// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocCore } from "../core/MocCore.sol";
import { IMocRC20 } from "../tokens/MocRC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MocCoreMock: to use the protocol without a queue
 */
contract MocCoreMock is MocCore {
    // ------- Structs -------
    struct InitializeParams {
        InitializeCoreParams initializeCoreParams;
        // Collateral Asset Token contract address
        address acTokenAddress;
    }

    // ------- Storage -------
    // Collateral Asset token
    IERC20 public _acToken;

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
        _acToken = IERC20(initializeParams_.acTokenAddress);
        __MocCore_init(initializeParams_.initializeCoreParams);
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
     * @notice caller sends Collateral Asset and recipient receives Collateral Token
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     *   Requires prior sender approval of Collateral Asset to this contract
     * @param qTC_ amount of Collateral Token to mint
     * @param qACmax_ maximum amount of Collateral Asset that can be spent
     * @param recipient_ address who receives the Collateral Token
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     */
    function mintTC(
        uint256 qTC_,
        uint256 qACmax_,
        address recipient_,
        address vendor_
    ) public payable returns (uint256 qACtotalNeeded, uint256 qFeeTokenTotalNeeded, FeeCalcs memory feeCalcs) {
        SafeERC20.safeTransferFrom(_acToken, msg.sender, address(this), qACmax_);
        qACLockedInPending += qACmax_;
        MintTCParams memory params = MintTCParams({
            qTC: qTC_,
            qACmax: qACmax_,
            sender: msg.sender,
            recipient: recipient_,
            vendor: vendor_
        });
        return _mintTCto(params);
    }

    /**
     * @notice caller sends Collateral Token and recipient receives Collateral Asset
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     * @param qTC_ amount of Collateral Token to redeem
     * @param qACmin_ minimum amount of Collateral Asset that `recipient_` expects to receive
     * @param recipient_ address who receives the Collateral Asset
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     */
    function redeemTC(
        uint256 qTC_,
        uint256 qACmin_,
        address recipient_,
        address vendor_
    ) public payable returns (uint256 qACtoRedeem, uint256 qFeeTokenTotalNeeded, FeeCalcs memory feeCalcs) {
        RedeemTCParams memory params = RedeemTCParams({
            qTC: qTC_,
            qACmin: qACmin_,
            sender: msg.sender,
            recipient: recipient_,
            vendor: vendor_
        });
        // because operation is used with the queue, funds are locked and burned from this address
        // we need to mint the same amount before
        tcToken.mint(address(this), qTC_);
        (qACtoRedeem, qFeeTokenTotalNeeded, feeCalcs) = _redeemTCto(params);
        tcToken.burn(msg.sender, qTC_);
        return (qACtoRedeem, qFeeTokenTotalNeeded, feeCalcs);
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
     */
    function mintTP(
        address tp_,
        uint256 qTP_,
        uint256 qACmax_,
        address recipient_,
        address vendor_
    ) public payable returns (uint256 qACtotalNeeded, uint256 qFeeTokenTotalNeeded, FeeCalcs memory feeCalcs) {
        SafeERC20.safeTransferFrom(_acToken, msg.sender, address(this), qACmax_);
        qACLockedInPending += qACmax_;
        MintTPParams memory params = MintTPParams({
            tp: tp_,
            qTP: qTP_,
            qACmax: qACmax_,
            sender: msg.sender,
            recipient: recipient_,
            vendor: vendor_
        });
        return _mintTPto(params);
    }

    /**
     * @notice caller sends Pegged Token and recipient receives Collateral Asset
     *  `vendor_` receives a markup in Fee Token if possible or in qAC if not
     * @param tp_ Pegged Token address to redeem
     * @param qTP_ amount of Pegged Token to redeem
     * @param qACmin_ minimum amount of Collateral Asset that `recipient_` expects to receive
     * @param recipient_ address who receives the Collateral Asset
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     */
    function redeemTP(
        address tp_,
        uint256 qTP_,
        uint256 qACmin_,
        address recipient_,
        address vendor_
    ) public payable returns (uint256 qACtoRedeem, uint256 qFeeTokenTotalNeeded, FeeCalcs memory feeCalcs) {
        RedeemTPParams memory params = RedeemTPParams({
            tp: tp_,
            qTP: qTP_,
            qACmin: qACmin_,
            sender: msg.sender,
            recipient: recipient_,
            vendor: vendor_
        });
        // because operation is used with the queue, funds are locked and burned from this address
        // we need to mint the same amount before
        IMocRC20(tp_).mint(address(this), qTP_);
        (qACtoRedeem, qFeeTokenTotalNeeded, feeCalcs) = _redeemTPto(params);
        IMocRC20(tp_).burn(msg.sender, qTP_);
        return (qACtoRedeem, qFeeTokenTotalNeeded, feeCalcs);
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
     */
    function mintTCandTP(
        address tp_,
        uint256 qTP_,
        uint256 qACmax_,
        address recipient_,
        address vendor_
    )
        public
        payable
        returns (
            uint256 qACtoMintTC,
            uint256 qACtoMintTP,
            uint256 qACtoSpent,
            uint256 qTCtoMint,
            uint256 qFeeTokenTotalNeeded,
            FeeCalcs memory feeCalcs
        )
    {
        SafeERC20.safeTransferFrom(_acToken, msg.sender, address(this), qACmax_);
        qACLockedInPending += qACmax_;
        MintTCandTPParams memory params = MintTCandTPParams({
            tp: tp_,
            qTP: qTP_,
            qACmax: qACmax_,
            sender: msg.sender,
            recipient: recipient_,
            vendor: vendor_
        });
        return _mintTCandTPto(params);
    }

    /**
     * @notice Caller sends Collateral Token and Pegged Token and recipient receives Collateral Asset.
     *  `vendor_` receives a markup in Fee Token if possible or in Collateral Asset if not
     *  This operation is done without checking coverage
     *  Collateral Token and Pegged Token are redeemed in equivalent proportions so that their price
     *  and global coverage are not modified.
     *  Reverts if qTP sent are insufficient.
     * @param tp_ Pegged Token address
     * @param qTC_ Maximum amount of Collateral Token to redeem
     * @param qTP_ Maximum amount of Pegged Token to redeem
     * @param qACmin_ Minimum amount of Collateral Asset that `recipient_` expects to receive
     * @param recipient_ Address who receives the Collateral Asset
     * @param vendor_ address who receives a markup, `0x0` if not using a vendor
     */
    function redeemTCandTP(
        address tp_,
        uint256 qTC_,
        uint256 qTP_,
        uint256 qACmin_,
        address recipient_,
        address vendor_
    )
        public
        payable
        returns (
            uint256 qACtoRedeemTC,
            uint256 qACtoRedeemTP,
            uint256 qACtoReceive,
            uint256 qTPtoRedeem,
            uint256 qFeeTokenTotalNeeded,
            FeeCalcs memory feeCalcs
        )
    {
        RedeemTCandTPParams memory params = RedeemTCandTPParams({
            tp: tp_,
            qTC: qTC_,
            qTP: qTP_,
            qACmin: qACmin_,
            sender: msg.sender,
            recipient: recipient_,
            vendor: vendor_
        });
        // because operation is used with the queue, funds are locked and burned from this address
        // we need to mint the same amount before
        IMocRC20(tp_).mint(address(this), qTP_);
        tcToken.mint(address(this), qTC_);
        (qACtoRedeemTC, qACtoRedeemTP, qACtoReceive, qTPtoRedeem, qFeeTokenTotalNeeded, feeCalcs) = _redeemTCandTPto(
            params
        );
        IMocRC20(tp_).burn(address(this), qTP_ - qTPtoRedeem);
        IMocRC20(tp_).burn(msg.sender, qTPtoRedeem);
        tcToken.burn(msg.sender, qTC_);
        return (qACtoRedeemTC, qACtoRedeemTP, qACtoReceive, qTPtoRedeem, qFeeTokenTotalNeeded, feeCalcs);
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
     */
    function swapTPforTP(
        address tpFrom_,
        address tpTo_,
        uint256 qTP_,
        uint256 qTPmin_,
        uint256 qACmax_,
        address recipient_,
        address vendor_
    )
        public
        payable
        returns (uint256 qACSurcharges, uint256 qTPMinted, uint256 qFeeTokenTotalNeeded, FeeCalcs memory feeCalcs)
    {
        SafeERC20.safeTransferFrom(_acToken, msg.sender, address(this), qACmax_);
        qACLockedInPending += qACmax_;
        SwapTPforTPParams memory params = SwapTPforTPParams({
            tpFrom: tpFrom_,
            tpTo: tpTo_,
            qTP: qTP_,
            qTPmin: qTPmin_,
            qACmax: qACmax_,
            sender: msg.sender,
            recipient: recipient_,
            vendor: vendor_
        });
        // because operation is used with the queue, funds are locked and burned from this address
        // we need to mint the same amount before
        IMocRC20(tpFrom_).mint(address(this), qTP_);
        (qACSurcharges, qTPMinted, qFeeTokenTotalNeeded, feeCalcs) = _swapTPforTPto(params);
        IMocRC20(tpFrom_).burn(msg.sender, qTP_);
        return (qACSurcharges, qTPMinted, qFeeTokenTotalNeeded, feeCalcs);
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
     */
    function swapTPforTC(
        address tp_,
        uint256 qTP_,
        uint256 qTCmin_,
        uint256 qACmax_,
        address recipient_,
        address vendor_
    )
        public
        payable
        returns (uint256 qACSurcharges, uint256 qTCMinted, uint256 qFeeTokenTotalNeeded, FeeCalcs memory feeCalcs)
    {
        SafeERC20.safeTransferFrom(_acToken, msg.sender, address(this), qACmax_);
        qACLockedInPending += qACmax_;
        SwapTPforTCParams memory params = SwapTPforTCParams({
            tp: tp_,
            qTP: qTP_,
            qTCmin: qTCmin_,
            qACmax: qACmax_,
            sender: msg.sender,
            recipient: recipient_,
            vendor: vendor_
        });
        // because operation is used with the queue, funds are locked and burned from this address
        // we need to mint the same amount before
        IMocRC20(tp_).mint(address(this), qTP_);
        (qACSurcharges, qTCMinted, qFeeTokenTotalNeeded, feeCalcs) = _swapTPforTCto(params);
        IMocRC20(tp_).burn(msg.sender, qTP_);
        return (qACSurcharges, qTCMinted, qFeeTokenTotalNeeded, feeCalcs);
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
     */
    function swapTCforTP(
        address tp_,
        uint256 qTC_,
        uint256 qTPmin_,
        uint256 qACmax_,
        address recipient_,
        address vendor_
    )
        public
        payable
        returns (uint256 qACSurcharges, uint256 qTPtoMint, uint256 qFeeTokenTotalNeeded, FeeCalcs memory feeCalcs)
    {
        SafeERC20.safeTransferFrom(_acToken, msg.sender, address(this), qACmax_);
        qACLockedInPending += qACmax_;
        SwapTCforTPParams memory params = SwapTCforTPParams({
            tp: tp_,
            qTC: qTC_,
            qTPmin: qTPmin_,
            qACmax: qACmax_,
            sender: msg.sender,
            recipient: recipient_,
            vendor: vendor_
        });
        // because operation is used with the queue, funds are locked and burned from this address
        // we need to mint the same amount before
        tcToken.mint(address(this), qTC_);
        (qACSurcharges, qTPtoMint, qFeeTokenTotalNeeded, feeCalcs) = _swapTCforTPto(params);
        tcToken.burn(msg.sender, qTC_);
        return (qACSurcharges, qTPtoMint, qFeeTokenTotalNeeded, feeCalcs);
    }

    // ------- External Functions -------

    /**
     * @notice Refreshes the AC holdings for the Bucket
     * @dev Intended to be use as notification after an RC20 AC transfer to this contract
     */
    function refreshACBalance() external override {
        uint256 unaccountedAcBalance = acBalanceOf(address(this)) - nACcb;
        // On this implementation, AC token balance is nACcb plus AC locked on pending operations
        if (unaccountedAcBalance > 0) _depositAC(unaccountedAcBalance);
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
