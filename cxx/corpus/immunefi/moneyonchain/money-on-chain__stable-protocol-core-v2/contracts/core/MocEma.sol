// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocBaseBucket } from "./MocBaseBucket.sol";

/**
 * @title MocEma: Exponential Moving Average
 * @notice Moc Ema, provides a set of methods that allows to calculate and track
 * Exponential Moving Average for each of the pegged Tokens.
 * @dev More information of EMA calculation https://en.wikipedia.org/wiki/Exponential_smoothing
 */
abstract contract MocEma is MocBaseBucket {
    // ------- Events -------
    event TPemaUpdated(uint256 indexed i_, uint256 oldTPema_, uint256 newTPema_);

    // ------- Structs -------
    struct EmaItem {
        // exponential moving average
        uint256 ema;
        // smoothing factor
        uint256 sf;
    }

    // ------- Storage -------
    // TP EMA items, indexes are in sync with PeggedTokens across Moc solution
    EmaItem[] public tpEma;
    // next ema calculation time
    uint256 public nextEmaCalculation;
    // amount of seconds to wait for next ema calculation
    uint256 public emaCalculationTimeSpan;

    /**
     * @notice calculates exponential moving average of the value of a Pegged Token
     * @dev more information of EMA calculation https://en.wikipedia.org/wiki/Exponential_smoothing
     * @param currentTPema_ current Ema value
     * @param pACtp_ current tp AC price
     */
    function _calcNewEma(EmaItem memory currentTPema_, uint256 pACtp_) private pure returns (uint256) {
        // [PREC²] = [PREC] * ([PREC] - [PREC])
        uint256 term1 = currentTPema_.ema * (ONE - currentTPema_.sf);
        // [PREC²] = [PREC] * [PREC]
        uint256 term2 = currentTPema_.sf * pACtp_;
        // [PREC] = ([PREC²] + [PREC²]) / [PREC]
        return (term1 + term2) / PRECISION;
    }

    // ------- Initializer -------
    /**
     * @notice contract initializer
     * @param emaCalculationTimeSpan_ amount of seconds to wait between Pegged ema calculation
     */
    function __MocEma_init_unchained(uint256 emaCalculationTimeSpan_) internal onlyInitializing {
        emaCalculationTimeSpan = emaCalculationTimeSpan_;
        _updateNextEmaCalculation(emaCalculationTimeSpan_);
    }

    // ------- Internal Functions -------

    /**
     * @notice updates next EMA calculation
     * @param emaCalculationTimeSpan_ amount of seconds to wait between Pegged ema calculation
     */
    function _updateNextEmaCalculation(uint256 emaCalculationTimeSpan_) internal {
        unchecked {
            nextEmaCalculation = block.timestamp + emaCalculationTimeSpan_;
        }
    }

    /**
     * @notice get target coverage adjusted by the moving average of the value of a Pegged Token
     * @param i_ Pegged Token index
     * @param pACtp_ Pegged Token price [PREC]
     * @return ctargemaTP [PREC]
     */
    function _getCtargemaTP(uint256 i_, uint256 pACtp_) internal view returns (uint256 ctargemaTP) {
        uint256 auxTPctarg = tpCtarg[i_];
        uint256 auxTpEma = tpEma[i_].ema;
        if (shouldCalculateEma()) auxTpEma = _calcNewEma(tpEma[i_], pACtp_);
        if (auxTpEma >= pACtp_) return auxTPctarg;
        // [PREC] = [PREC] * [PREC] / [PREC]
        return (auxTPctarg * pACtp_) / auxTpEma;
    }

    /**
     * @notice update exponential moving average of the value of a Pegged Token
     * @param i_ Pegged Token index
     * @param pACtp_ tp price [PREC]
     */
    function _updateTPema(uint256 i_, uint256 pACtp_) internal {
        EmaItem memory currentTPema = tpEma[i_];
        uint256 newEma = _calcNewEma(currentTPema, pACtp_);
        // save new ema value to storage
        tpEma[i_].ema = newEma;
        emit TPemaUpdated(i_, currentTPema.ema, newEma);
    }

    /**
     * @notice calculates CA target coverage, adjusted by all Pegged Token's to
     *  Collateral Asset last stored moving average price
     * @dev WARN: if EMA are not up to date, the resulting coverage might not reflect real spot value
     *      qAC = (nTP + tpGain) / pACtp
     *      ctargemaCA = ∑(ctargemaTP * qAC) / ∑(qAC)
     * @param pACtps_ All tps prices [PREC]
     * @return ctargemaCA [PREC]
     */
    function _calcCtargemaCA(uint256[] memory pACtps_) internal view returns (uint256 ctargemaCA) {
        uint256 num;
        uint256 den;
        uint256 pegAmount = pegContainer.length;
        for (uint256 i = 0; i < pegAmount; i = unchecked_inc(i)) {
            uint256 pACtp = pACtps_[i];
            (uint256 tpGain, ) = _getPnLTP(i, pACtp);
            // [PREC] = [N] * [PREC] * [PREC]  / [PREC]
            uint256 qAC = _divPrec((pegContainer[i].nTP + tpGain) * PRECISION, pACtp);
            // [PREC]^2 = [PREC] * [PREC]
            num += _getCtargemaTP(i, pACtp) * qAC;
            // [PREC] = [PREC]
            den += qAC;
        }
        // we must return a default value when all nTP are 0
        // slither-disable-next-line incorrect-equality
        if (den == 0) {
            unchecked {
                return (protThrld * 2);
            }
        }
        // [PREC] = ([PREC]^2) / [PREC]
        ctargemaCA = num / den;
    }

    /**
     * @notice If time, calculates the EMA for all the Pegged Token prices.
     * @dev All price provider prices must be available, fails if not
     * @param pACtps_ All tps prices [PREC]
     */
    function _updateEmas(uint256[] memory pACtps_) internal {
        if (shouldCalculateEma()) {
            uint256 pegAmount = pegContainer.length;
            for (uint256 i = 0; i < pegAmount; i = unchecked_inc(i)) {
                _updateTPema(i, pACtps_[i]);
            }
            _updateNextEmaCalculation(emaCalculationTimeSpan);
        }
    }

    // ------- Public Functions -------

    /**
     * @notice calculates target coverage adjusted by all Pegged Token's to Collateral Asset rate moving average
     * @dev qAC = nTP / pACtp
     *      ctargemaCA = ∑(ctargemaTP * qAC) / ∑(qAC)
     * @return ctargemaCA [PREC]
     */
    function getCtargemaCA() external view returns (uint256 ctargemaCA) {
        return _calcCtargemaCA(_getPACtps());
    }

    /**
     * @notice calculates target coverage adjusted by all Pegged Token's to Collateral Asset rate moving average
     * @dev qAC = nTP / pACtp
     *      ctargemaCA = ∑(ctargemaTP * qAC) / ∑(qAC)
     * @param pACtps_ All tps prices [PREC]
     * @return ctargemaCA [PREC]
     */
    function calcCtargemaCA(uint256[] memory pACtps_) external view returns (uint256 ctargemaCA) {
        return _calcCtargemaCA(pACtps_);
    }

    /**
     * @notice calculates target coverage adjusted by the moving average of the value of a Pegged Token
     * @param tp_ Pegged Token address
     * @return ctargemaTP [PREC]
     */
    function getCtargemaTP(address tp_) external view returns (uint256 ctargemaTP) {
        uint256 i = _tpi(tp_);
        return _getCtargemaTP(i, _getPACtp(i));
    }

    /**
     * @notice calculates target coverage adjusted by the moving average of the value of a Pegged Token
     * @param tp_ Pegged Token address
     * @param pACtp_ tp price [PREC]
     * @return ctargemaTP [PREC]
     */
    function calcCtargemaTP(address tp_, uint256 pACtp_) external view returns (uint256 ctargemaTP) {
        return _getCtargemaTP(_tpi(tp_), pACtp_);
    }

    /**
     * @notice true if the necessary span has pass since last ema update
     */
    function shouldCalculateEma() public view returns (bool) {
        unchecked {
            return block.timestamp >= nextEmaCalculation;
        }
    }

    /**
     * @notice If time, calculates the EMA for all the Pegged Token prices.
     * @dev All price provider prices must be available, fails if not
     */
    function updateEmas() public {
        _updateEmas(_getPACtps());
    }

    /**
     * @param timeSpan_ Defines how many seconds should pass between EMA calculations
     * @dev nextEmaCalculation is not automatically updated, you have to wait until next
     *  EMA calculation to be made : nextEmaCalculation = block.timestamp + emaCalculationTimeSpan
     **/
    function setEmaCalculationTimeSpan(uint256 timeSpan_) external onlyAuthorizedChanger {
        emaCalculationTimeSpan = timeSpan_;
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
