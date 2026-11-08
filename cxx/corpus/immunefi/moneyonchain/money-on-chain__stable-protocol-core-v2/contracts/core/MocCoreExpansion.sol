// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocCommons, PeggedTokenParams } from "./MocCommons.sol";
import { IMocRC20 } from "../interfaces/IMocRC20.sol";
import { IPriceProvider } from "../interfaces/IPriceProvider.sol";

/**
 * @title MocCoreExpansion
 * @notice This contract is used as an expansion of MocCore because 24kb size limitation
 *  MocCore delegate some function calls to it.
 * @dev IMPORTANT NOTES:
 *  1. MocCore and MocCoreExpansion must have always the same storage layout to avoid collisions
 *  2. Because MocCore is upgradeable and delegates calls to MocCoreExpansion, it cannot be upgradeable because
 *      a proxy contract cannot delegate calls to another proxy contract. So, for any MocCoreExpansion upgrade
 *      you must deploy a new implementation and set it to MocCore.
 */
contract MocCoreExpansion is MocCommons {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice add a Pegged Token to the protocol
     * @dev Note that the ema value, should consider `nextEmaCalculation`
     *  This function is called by MocCore contract using it's context with delegate call
     *  Checks done there:
     *  -  onlyAuthorizedChanger: the caller must have governance authorization.
     * @param tpToken_ Pegged Token contract to add
     *  peggedTokenParams_ params of Pegged Token to add:
     *      priceProviderAddress Pegged Token price provider contract address
     *      tpCtarg Pegged Token target coverage [PREC]
     *      tpMintFee additional fee pct applied on mint [PREC]
     *      tpRedeemFee additional fee pct applied on redeem [PREC]
     *      tpEma initial Pegged Token exponential moving average [PREC]
     *      tpEmaSf Pegged Token smoothing factor [PREC]
     * @dev Pegged Token should be added using the corresponding changer template, which
     *      should guarantee that it is added on all the buckets(mandatory for multiCollateral)
     *
     *  Requirements:
     *
     *  - tpTokenAddress must be a MocRC20, with mint, burn roles already settled
     *  for this contract
     */
    function addPeggedToken(IMocRC20 tpToken_, PeggedTokenParams calldata peggedTokenParams_) external {
        IPriceProvider priceProvider = IPriceProvider(peggedTokenParams_.priceProviderAddress);

        if (peggedTokenIndex[address(tpToken_)].exists) revert PeggedTokenAlreadyAdded();
        uint256 newTPindex = uint256(tpTokens.length);
        peggedTokenIndex[address(tpToken_)] = PeggedTokenIndex({ index: newTPindex, exists: true });

        // set Pegged Token address
        tpTokens.push(tpToken_);
        // set peg container item
        pegContainer.push(PegContainerItem({ nTP: 0, priceProvider: priceProvider }));
        // set target coverage
        tpCtarg.push(peggedTokenParams_.tpCtarg);
        // set mint fee pct
        tpMintFees[address(tpToken_)] = peggedTokenParams_.tpMintFee;
        // set redeem fee pct
        tpRedeemFees[address(tpToken_)] = peggedTokenParams_.tpRedeemFee;
        // set EMA initial value and smoothing factor
        tpEma.push(EmaItem({ ema: peggedTokenParams_.tpEma, sf: peggedTokenParams_.tpEmaSf }));
        tpiou.push();

        /**
         * Price providers may not be valid at the time of adding a
         * pegged token, so we initialize the last token price with a fixed value.
         * This value should be realistic, otherwise it would momentarily affect the
         * successFee calculation when the protocol starts operating.
         */
        pACtpLstop.push(peggedTokenParams_.tpEma);
        // emit the event
        emit PeggedTokenChange(newTPindex, address(tpToken_), peggedTokenParams_);
    }

    /**
     * @notice modifies a Pegged Token of the protocol
     * @dev Note that the ema value, should consider `nextEmaCalculation`
     *  This function is called by MocCore contract using it's context with delegate call
     *  Checks done there:
     *  -  onlyAuthorizedChanger: the caller must have governance authorization.
     * @param tpToken_ Pegged Token contract to edit
     *  peggedTokenParams_ params of Pegged Token to edit:
     *      priceProviderAddress Pegged Token price provider contract address
     *      tpCtarg Pegged Token target coverage [PREC]
     *      tpMintFee additional fee pct applied on mint [PREC]
     *      tpRedeemFee additional fee pct applied on redeem [PREC]
     *      tpEma initial Pegged Token exponential moving average [PREC]
     *      tpEmaSf Pegged Token smoothing factor [PREC]
     *
     *  Requirements:
     *
     * - the tpTokenAddress must exists
     */
    function editPeggedToken(IMocRC20 tpToken_, PeggedTokenParams calldata peggedTokenParams_) external {
        PeggedTokenIndex memory ptIndex = peggedTokenIndex[address(tpToken_)];
        if (!ptIndex.exists) revert InvalidAddress();
        uint256 i = ptIndex.index;
        pegContainer[i].priceProvider = IPriceProvider(peggedTokenParams_.priceProviderAddress);
        // set target coverage
        tpCtarg[i] = peggedTokenParams_.tpCtarg;
        // set mint fee pct
        tpMintFees[address(tpToken_)] = peggedTokenParams_.tpMintFee;
        // set redeem fee pct
        tpRedeemFees[address(tpToken_)] = peggedTokenParams_.tpRedeemFee;
        // set EMA initial value and smoothing factor
        tpEma[i].sf = peggedTokenParams_.tpEmaSf;
        // emit the event
        emit PeggedTokenChange(i, address(tpToken_), peggedTokenParams_);
    }

    /**
     * @dev Calculates price at liquidation event as a relation between Pegs total supply
     * and the amount of Asset Collateral available to distribute
     */
    function settleLiquidationPrices() external {
        // Total amount of AC available to be redeemed
        uint256 totalACAvailable = nACcb;
        // slither-disable-next-line incorrect-equality
        if (totalACAvailable == 0) return;
        uint256 pegAmount = pegContainer.length;
        // this could be get by getLckAC(), but given the prices are needed after,
        // it's better to cache them here.
        uint256 lckAC;
        // Auxiliary cache of pegs pACtp
        uint256[] memory pACtps = new uint256[](pegAmount);
        // for each peg, calculates the proportion of AC reserves it's locked

        for (uint256 i = 0; i < pegAmount; i = unchecked_inc(i)) {
            pACtps[i] = _getPACtp(i);
            // [N] = [N] * [PREC] / [PREC]
            lckAC += _divPrec(pegContainer[i].nTP, pACtps[i]);
        }
        for (uint256 i = 0; i < pegAmount; i = unchecked_inc(i)) {
            // [PREC] = [PREC] * [N] / [N];
            tpLiqPrices.push((pACtps[i] * lckAC) / totalACAvailable);
        }
    }

    /**
     * @notice Allow redeem on liquidation state, user Peg balance gets burned
     * @dev This function is called by MocCore contract using it's context with delegate call
     *  The equivalent AC given the liquidation frozen price(qACRedeemed) is transferred
     *  to the `recipient_` by MocCore contract
     *  Checks done there:
     *  -  notPaused: the contract must be unpaused
     * @param tp_ Pegged Token address
     * @param sender_ address owner of the TP to be redeemed
     * @param recipient_ address who receives the AC
     * @return qACRedeemed amount of AC sent to `recipient_`
     */
    function liqRedeemTP(
        address tp_,
        address sender_,
        address recipient_,
        uint256 mocACBalance
    ) external returns (uint256 qACRedeemed) {
        if (!liquidated) revert OnlyWhenLiquidated();
        uint256 i = _tpi(tp_);
        uint256 qTP = tpTokens[i].balanceOf(sender_);
        // slither-disable-next-line incorrect-equality
        if (qTP == 0) revert InsufficientTPtoRedeem(qTP, qTP);
        // [PREC]
        uint256 liqPACtp = tpLiqPrices[i];
        // [PREC] = [N] * [PREC] / [PREC]
        qACRedeemed = _divPrec(qTP, liqPACtp);
        // Given rounding errors, the last redeemer might receive a little less
        if (mocACBalance < qACRedeemed) qACRedeemed = mocACBalance;
        // in liquidation doesn't pay fees or markup
        // qACfee, qFeeToken, qACVendorMarkup, qFeeTokenVendorMarkup  = (0, 0, 0, 0)
        emit LiqTPRedeemed(tp_, sender_, recipient_, qTP, qACRedeemed);
        // burn qTP from the sender
        tpTokens[i].burn(sender_, qTP);
    }

    /**
     * @notice mint Collateral Token and Pegged Token in exchange for Collateral Asset
     *  This operation is done without checking coverage
     *  Collateral Token and Pegged Token are minted in equivalent proportions so that its price
     *  and global coverage are not modified.
     *  Reverts if qAC sent are insufficient.
     * @param params_ mint TC and TP function parameters
     * @dev
     *      i_ Pegged Token index
     *      qTP_ amount of Pegged Token to mint
     *      qACmax_ maximum amount of Collateral Asset that can be spent
     *      sender_ address who sends Collateral Asset
     *      recipient_ address who receives the Collateral Token and Pegged Token
     *      vendor_ address who receives a markup. If its address(0) no markup is applied
     * @return qACtoMintTC amount of AC used to mint Collateral Token
     * @return qACtoMintTP amount of AC used to mint Pegged Token
     * @return qACtoSpent total amount of AC spent by `sender_` for TC and TP mint plus fees
     * @return qTCtoMint amount of Collateral Token minted
     * @return qFeeTokenTotalNeeded amount of Fee Token used by `sender_` to pay fees. 0 if qAC is used instead
     * @return feeCalcs platform fee detail breakdown
     */
    function mintTCandTPto(
        MintTCandTPParams memory params_
    )
        external
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
        uint256[] memory pACtps = _getPACtps();
        uint256 i = _tpi(params_.tp);
        uint256 pACtp = pACtps[i];
        _updateTPtracking(i, pACtp);
        // evaluates whether or not the system coverage is healthy, reverts if it's not
        (uint256 lckAC, uint256 nACgain) = _evalCoverage(protThrld, pACtps);
        (qTCtoMint, qACtoMintTC, qACtoMintTP) = _calcQACforMintTCandTP(
            params_.qTP,
            pACtp,
            _getCtargemaTP(i, pACtp),
            _getPTCac(lckAC, nACgain)
        );
        uint256 qACNeededtoMint = qACtoMintTC + qACtoMintTP;
        uint256 qACSurcharges;
        (qACSurcharges, qFeeTokenTotalNeeded, feeCalcs) = _calcFees(
            params_.sender,
            params_.vendor,
            qACNeededtoMint,
            mintTCandTPFee
        );
        qACtoSpent = qACNeededtoMint + qACSurcharges;
        if (qACtoSpent > params_.qACmax) revert InsufficientQacSent(params_.qACmax, qACtoSpent);
        // if is 0 reverts because it is trying to mint an amount below precision
        // slither-disable-next-line incorrect-equality
        if (qACtoSpent == 0) revert QacNeededMustBeGreaterThanZero();
        // update flux capacitor and reverts if not allowed by accumulators
        _updateAccumulatorsOnMintTP(qACtoMintTP);
        _depositAndMintTC(qTCtoMint, qACNeededtoMint, params_.recipient);
        _depositAndMintTP(i, params_.qTP, 0, params_.recipient);
    }

    /**
     * @notice redeem Collateral Asset in exchange for Collateral Token and Pegged Token
     *  This operation is done without checking coverage
     *  Collateral Token and Pegged Token are redeemed in equivalent proportions so that its price
     *  and global coverage are not modified.
     *  Reverts if qTP sent are insufficient.
     * @param params_ redeem TC and TP function parameters
     * @dev
     *      i_ Pegged Token index
     *      qTC_ amount of Collateral Token to redeem
     *      qTP_ maximum amount of Pegged Token to redeem
     *      qACmin_ minimum amount of Collateral Asset that `recipient_` expects to receive
     *      sender_ address who sends Collateral Token and Pegged Token
     *      recipient_ address who receives the Collateral Asset
     *      vendor_ address who receives a markup. If its address(0) no markup is applied
     * @return qACtoRedeemTC amount of AC sent to `recipient_` for Collateral Token redemption
     * @return qACtoRedeemTP amount of AC sent to `recipient_` for Pegged Token redemption
     * @return qACtoReceive total amount of AC sent to `recipient_` for TC and TP redemption minus fees
     * @return qTPtoRedeem amount of Pegged Token redeemed
     * @return qFeeTokenTotalNeeded amount of Fee Token used by `sender_` to pay fees. 0 if qAC is used instead
     * @return feeCalcs platform fee detail breakdown
     */
    function redeemTCandTPto(
        RedeemTCandTPParams memory params_
    )
        external
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
        // emas are updated here
        (uint256 combinedCglb, uint256 combinedCtargemaCA, uint256[] memory pACtps) = _getMocMultiCollateralGuard()
            .getCombinedValues(address(this));

        uint256 i = _tpi(params_.tp);
        uint256 pACtp = pACtps[i];
        _updateTPtracking(i, pACtp);
        // evaluates that the system is not below the liquidation threshold
        // one of the reasons is to prevent it from failing due to underflow because the lckAC > totalACavailable
        (uint256 lckAC, uint256 nACgain) = _evalCoverage(liqThrld, pACtps);
        uint256 pTCac = _getPTCac(lckAC, nACgain);
        // ctargemaCA and ctargemaTP never should be less than ONE
        // [PREC] = [PREC - PREC] * [PREC - PREC] / [PREC - PREC]
        uint256 redeemProportion = ((combinedCglb - ONE) * (_getCtargemaTP(i, pACtp) - ONE)) /
            (combinedCtargemaCA - ONE);
        // calculate how many TP are needed to redeem TC and not compromise the coverage
        // [N] = [N] * [PREC] * [PREC] / [PREC] * [PREC]
        qTPtoRedeem = (params_.qTC * pACtp * pTCac) / (redeemProportion * PRECISION);
        if (qTPtoRedeem > params_.qTP) revert InsufficientQtpSent(params_.qTP, qTPtoRedeem);
        // if qTC == 0 => qTPtoRedeem == 0 and will revert because QacNeededMustBeGreaterThanZero
        (qACtoRedeemTC, qACtoRedeemTP) = _calcQACforRedeemTCandTP(params_.qTC, qTPtoRedeem, pACtp, pTCac);
        uint256 qACtotalToRedeem = qACtoRedeemTC + qACtoRedeemTP;
        uint256 qACSurcharges;
        (qACSurcharges, qFeeTokenTotalNeeded, feeCalcs) = _calcFees(
            params_.sender,
            params_.vendor,
            qACtotalToRedeem,
            redeemTCandTPFee
        );
        qACtoReceive = qACtotalToRedeem - qACSurcharges;
        if (qACtoReceive < params_.qACmin) revert QacBelowMinimumRequired(params_.qACmin, qACtoReceive);
        // update flux capacitor and reverts if not allowed by accumulators
        _updateAccumulatorsOnRedeemTP(qACtoRedeemTP);
        _withdrawAndBurnTC(params_.qTC, qACtotalToRedeem);
        _withdrawAndBurnTP(i, qTPtoRedeem, 0);
    }

    /**
     * @notice swap Pegged Token to another one
     *  This operation is done without checking coverage unless the target coverage for
     *  received Pegged Token is greater than the Pegged Token sent
     * @dev This function is called by MocCore contract using it's context with delegate call
     * @param params_ swap TP for TP function parameters
     * @dev
     *      iFrom_ owned Pegged Token index
     *      iTo_ target Pegged Token index
     *      qTP_ amount of owned Pegged Token to swap
     *      qTPmin_ minimum amount of target Pegged Token that `recipient_` expects to receive
     *      qACmax_ maximum amount of Collateral Asset that can be spent in fees
     *      sender_ address who sends the Pegged Token
     *      recipient_ address who receives the target Pegged Token
     *      vendor_ address who receives a markup. If its address(0) no markup is applied
     * @return qACSurcharges amount of AC used to pay fees and markup
     * @return qTPtoMint amount of Pegged Token minted
     * @return qFeeTokenTotalNeeded amount of Fee Token used by `sender_` to pay fees. 0 if qAC is used instead
     * @return feeCalcs struct with:
     * @dev
     *      qACFee amount of AC needed to pay fees
     *      qFeeToken amount of Fee Token needed to pay fess
     *      qACVendorMarkup amount of AC needed to pay vendor markup
     *      qFeeTokenVendorMarkup amount of Fee Token needed to pay vendor markup
     */
    function swapTPforTPto(
        SwapTPforTPParams memory params_
    )
        external
        payable
        returns (uint256 qACSurcharges, uint256 qTPtoMint, uint256 qFeeTokenTotalNeeded, FeeCalcs memory feeCalcs)
    {
        if (params_.tpFrom == params_.tpTo) revert InvalidValue();
        uint256[] memory pACtps = _getPACtps();
        uint256 iFrom = _tpi(params_.tpFrom);
        uint256 iTo = _tpi(params_.tpTo);
        uint256 pACtpFrom = pACtps[iFrom];
        uint256 pACtpTo = pACtps[iTo];
        _updateTPtracking(iFrom, pACtpFrom);
        _updateTPtracking(iTo, pACtpTo);
        // calculate how many total qAC are redeemed
        // [N] = [N] * [PREC] / [PREC]
        uint256 qACtotalToRedeem = _divPrec(params_.qTP, pACtpFrom);
        // calculate how many qTP can mint with the given qAC
        // [N] = [N] * [PREC] / [PREC]
        qTPtoMint = (params_.qTP * pACtpTo) / pACtpFrom;
        if (qTPtoMint < params_.qTPmin || qTPtoMint == 0) revert QtpBelowMinimumRequired(params_.qTPmin, qTPtoMint);

        bool ctargemaTPRelation = _getCtargemaTP(iTo, pACtpTo) > _getCtargemaTP(iFrom, pACtpFrom);
        // if ctargemaTPto > ctargemaTPfrom we need to check coverage
        if (ctargemaTPRelation) {
            // emas are updated here
            (
                uint256 combinedCglb,
                uint256 combinedCtargemaCA,
                uint256 tpAvailableToMint,

            ) = _getMocMultiCollateralGuard().getCombinedAndTP(address(this), params_.tpTo);
            // evaluates whether or not the system coverage is healthy enough to mint TP
            // evaluating the multi collateral status, reverts if it's not
            _evalCombinedCoverage(combinedCglb, combinedCtargemaCA);

            uint256 ctargemaCA = _calcCtargemaCA(pACtps);
            // evaluates whether or not the system coverage is healthy enough to mint TP
            // given the target coverage adjusted by the moving average, reverts if it's not
            _evalCoverage(ctargemaCA, pACtps);
            // evaluates if there are enough TP available to mint, reverts if it's not
            _evalTPavailableToMint(qTPtoMint, tpAvailableToMint);
        }
        (qACSurcharges, qFeeTokenTotalNeeded, feeCalcs) = _calcFees(
            params_.sender,
            params_.vendor,
            qACtotalToRedeem,
            swapTPforTPFee
        );
        if (qACSurcharges > params_.qACmax) revert InsufficientQacSent(params_.qACmax, feeCalcs.qACFee);
        _depositAndMintTP(iTo, qTPtoMint, 0, params_.recipient);
        _withdrawAndBurnTP(iFrom, params_.qTP, 0);
    }

    /**
     * @notice swap Pegged Token to Collateral Token
     * @dev This function is called by MocCore contract using it's context with delegate call
     * @param params_ swap TP for TC function parameters
     * @dev
     *      i_ Pegged Token index
     *      qTP_ amount Pegged Token to swap
     *      qTCmin_ minimum amount of Collateral Token that `recipient_` expects to receive
     *      qACmax_ maximum amount of Collateral Asset that can be spent in fees
     *      sender_ address who sends the Pegged Token
     *      recipient_ address who receives Collateral Token
     *      vendor_ address who receives a markup. If its address(0) no markup is applied
     * @return qACSurcharges amount of AC used to pay fees and markup
     * @return qTCtoMint amount of Collateral Token minted
     * @return qFeeTokenTotalNeeded amount of Fee Token used by `sender_` to pay fees. 0 if qAC is used instead
     * @return feeCalcs struct with:
     * @dev
     *      qACFee amount of AC needed to pay fees
     *      qFeeToken amount of Fee Token needed to pay fess
     *      qACVendorMarkup amount of AC needed to pay vendor markup
     *      qFeeTokenVendorMarkup amount of Fee Token needed to pay vendor markup
     */
    function swapTPforTCto(
        SwapTPforTCParams memory params_
    )
        external
        payable
        returns (uint256 qACSurcharges, uint256 qTCtoMint, uint256 qFeeTokenTotalNeeded, FeeCalcs memory feeCalcs)
    {
        uint256[] memory pACtps = _getPACtps();
        uint256 i = _tpi(params_.tp);
        uint256 pACtp = pACtps[i];
        _updateTPtracking(i, pACtp);
        // evaluates whether or not the system coverage is healthy enough to mint TC, reverts if it's not
        (uint256 lckAC, uint256 nACgain) = _evalCoverage(protThrld, pACtps);
        // calculate how many total qAC are redeemed TP
        // [N] = [N] * [PREC] / [PREC]
        uint256 qACtotalToRedeem = _divPrec(params_.qTP, pACtp);
        // calculate how many qTC can mint with the given qAC
        // qTCtoMint = qTP / pTCac / pACtp
        // [N] = [N] * [N] * [PREC] / ([N] - [N]) * [PREC]
        qTCtoMint = _divPrec(params_.qTP * nTCcb, (_getTotalACavailable(nACgain) - lckAC) * pACtp);
        // slither-disable-next-line incorrect-equality
        if (qTCtoMint < params_.qTCmin || qTCtoMint == 0) revert QtcBelowMinimumRequired(params_.qTCmin, qTCtoMint);

        (qACSurcharges, qFeeTokenTotalNeeded, feeCalcs) = _calcFees(
            params_.sender,
            params_.vendor,
            qACtotalToRedeem,
            swapTPforTCFee
        );
        if (qACSurcharges > params_.qACmax) revert InsufficientQacSent(params_.qACmax, feeCalcs.qACFee);
        // update flux capacitor and reverts if not allowed by accumulators
        _updateAccumulatorsOnRedeemTP(qACtotalToRedeem);
        _withdrawAndBurnTP(i, params_.qTP, 0);
        _depositAndMintTC(qTCtoMint, 0, params_.recipient);
    }

    /**
     * @notice swap Collateral Token to Pegged Token
     * @dev This function is called by MocCore contract using it's context with delegate call
     * @param params_ swap TC for TP function parameters
     * @dev
     *      i_ Pegged Token index
     *      qTC_ amount of Collateral Token to swap
     *      qTPmin_ minimum amount of Pegged Token Token that `recipient_` expects to receive
     *      qACmax_ maximum amount of Collateral Asset that can be spent in fees
     *      sender_ address who sends the Collateral Token
     *      recipient_ address who receives the Pegged Token
     *      vendor_ address who receives a markup. If its address(0) no markup is applied
     * @return qACSurcharges amount of AC used to pay fees and markup
     * @return qTPtoMint amount of Pegged Token minted
     * @return qFeeTokenTotalNeeded amount of Fee Token used by `sender_` to pay fees. 0 if qAC is used instead
     * @dev
     *      qACFee amount of AC needed to pay fees
     *      qFeeToken amount of Fee Token needed to pay fess
     *      qACVendorMarkup amount of AC needed to pay vendor markup
     *      qFeeTokenVendorMarkup amount of Fee Token needed to pay vendor markup
     */
    function swapTCforTPto(
        SwapTCforTPParams memory params_
    )
        external
        payable
        returns (uint256 qACSurcharges, uint256 qTPtoMint, uint256 qFeeTokenTotalNeeded, FeeCalcs memory feeCalcs)
    {
        // emas are updated here
        (
            uint256 combinedCglb,
            uint256 combinedCtargemaCA,
            uint256 tcAvailableToRedeem,
            uint256 tpAvailableToMint,
            uint256[] memory pACtps
        ) = _getMocMultiCollateralGuard().getCombinedAndTCAndTP(address(this), params_.tp);
        // evaluates whether or not the system coverage is healthy enough to redeem TC and mint TP
        // evaluating the multi collateral status, reverts if it's not
        _evalCombinedCoverage(combinedCglb, combinedCtargemaCA);

        uint256 ctargemaCA = _calcCtargemaCA(pACtps);
        uint256 i = _tpi(params_.tp);
        uint256 pACtp = pACtps[i];
        _updateTPtracking(i, pACtp);
        // evaluates whether or not the system coverage is healthy enough to redeem TC and mint TP
        // given the target coverage adjusted by the moving average, reverts if it's not
        (uint256 lckAC, uint256 nACgain) = _evalCoverage(ctargemaCA, pACtps);
        // evaluates if there are enough Collateral Tokens available to redeem, reverts if there are not
        _evalTCAvailableToRedeem(params_.qTC, tcAvailableToRedeem);
        // calculate how many total qAC are redeemed
        // [N] = [N] * [PREC] / [PREC]
        uint256 qACtotalToRedeem = _mulPrec(params_.qTC, _getPTCac(lckAC, nACgain));
        // if is 0 reverts because it is trying to swap an amount below precision
        // slither-disable-next-line incorrect-equality
        if (qACtotalToRedeem == 0) revert QacNeededMustBeGreaterThanZero();
        // calculate how many qTP can mint with the given qAC
        // qTPtoMint = qTC * pTCac * pACtp
        // [N] = ([N] * ([N] - [N]) * [PREC] / [N]) / [PREC]
        qTPtoMint = ((params_.qTC * (_getTotalACavailable(nACgain) - lckAC) * pACtp) / nTCcb) / PRECISION;
        // evaluates if there are enough TP available to mint, reverts if it's not
        _evalTPavailableToMint(qTPtoMint, tpAvailableToMint);
        if (qTPtoMint < params_.qTPmin) revert QtpBelowMinimumRequired(params_.qTPmin, qTPtoMint);

        (qACSurcharges, qFeeTokenTotalNeeded, feeCalcs) = _calcFees(
            params_.sender,
            params_.vendor,
            qACtotalToRedeem,
            swapTCforTPFee
        );
        if (qACSurcharges > params_.qACmax) revert InsufficientQacSent(params_.qACmax, feeCalcs.qACFee);
        // update flux capacitor and reverts if not allowed by accumulators
        _updateAccumulatorsOnMintTP(qACtotalToRedeem);
        _withdrawAndBurnTC(params_.qTC, 0);
        _depositAndMintTP(i, qTPtoMint, 0, params_.recipient);
    }

    /**
     * @notice calculate how many Collateral Asset are needed to mint an amount of Collateral Token
     * and Pegged Token in one operation
     * @param qTP_ amount of Pegged Token to mint
     * @param pACtp_ Pegged Token price [PREC]
     * @param ctargemaTP_ target coverage adjusted by the moving average of the value of a Pegged Token
     * @param pTCac_ Collateral Token price [PREC]
     * @return qTCtoMint amount of Collateral Token to mint [N]
     * @return qACtoMintTC amount of Collateral Asset needed to mint Collateral Token [N]
     * @return qACtoMintTP amount of Collateral Asset used to mint Pegged Token [N]
     */
    function _calcQACforMintTCandTP(
        uint256 qTP_,
        uint256 pACtp_,
        uint256 ctargemaTP_,
        uint256 pTCac_
    ) internal pure returns (uint256 qTCtoMint, uint256 qACtoMintTC, uint256 qACtoMintTP) {
        // calculate how many TC are needed to mint TP and total qAC used for mint both
        // [N] = [N] * ([PREC] - [PREC]) / [PREC]
        qACtoMintTC = (qTP_ * (ctargemaTP_ - ONE)) / pACtp_;
        // [N] = [N] *  [PREC] / [PREC]
        qTCtoMint = _divPrec(qACtoMintTC, pTCac_);
        // [N] = [N] *  [PREC] / [PREC]
        qACtoMintTP = _divPrec(qTP_, pACtp_);
        return (qTCtoMint, qACtoMintTC, qACtoMintTP);
    }

    /**
     * @notice calculate how many Collateral Asset are needed to redeem an amount of Collateral Token
     * and Pegged Token in one operation
     * @param qTC_ amount of Collateral Token to redeem
     * @param qTP_ amount of Pegged Token to redeem
     * @param pACtp_ Pegged Token price [PREC]
     * @param pTCac_ Collateral Token price [PREC]
     * @return qACtoRedeemTC amount of Collateral Asset needed to redeem Collateral Token [N]
     * @return qACtoRedeemTP amount of Collateral Asset used to redeem Pegged Token [N]
     */
    function _calcQACforRedeemTCandTP(
        uint256 qTC_,
        uint256 qTP_,
        uint256 pACtp_,
        uint256 pTCac_
    ) internal pure returns (uint256 qACtoRedeemTC, uint256 qACtoRedeemTP) {
        // calculate how many total qAC are redeemed
        // [N] = [N] * [PREC] / [PREC]
        qACtoRedeemTP = _divPrec(qTP_, pACtp_);
        // if is 0 reverts because it is trying to redeem an amount of TP below precision
        // we check it here to prevent qTP == 0 && qTC != 0
        // slither-disable-next-line incorrect-equality
        if (qACtoRedeemTP == 0) revert QacNeededMustBeGreaterThanZero();
        // calculate how many qAC are redeemed because TC
        // [N] = [N] * [PREC] / [PREC]
        qACtoRedeemTC = _mulPrec(qTC_, pTCac_);
        return (qACtoRedeemTC, qACtoRedeemTP);
    }
}
