// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { Governed, IGovernor } from "../../governance/Governed.sol";
import { IRatioSource } from "../../interfaces/IRatioSource.sol";

/**
 * @title TVLRatioSource
 * @notice Ratio source for the TVL MocTokenAllocator
 * @dev This contract is used to define the split ratio calculating the total value locked (TVL) in the system.
 *  The recipients are 2:
 *  1. The TC yeld recipient. The percentage if related to the amount of TC in the system.
 *  2. The TP yeld recipient. The percentage if related to the amount of TP in the system.
 */
abstract contract TVLRatioSource is IRatioSource, Governed {
    // ------- Storage -------

    // Moc contract
    address public mocSource;
    // TC yeld recipient address
    address public tcYeldRecipient;
    // TP yeld recipient address
    address public tpYeldRecipient;

    /**
     * @notice constructor
     * @param governor_ address of the governor contract
     * @param mocSource_ address of the Moc contract
     * @param tcYeldRecipient_ address of the TC yeld recipient
     * @param tpYeldRecipient_ address of the TP yeld recipient
     */
    function _initialize(
        address governor_,
        address mocSource_,
        address tcYeldRecipient_,
        address tpYeldRecipient_
    ) internal {
        _disableInitializers();
        governor = IGovernor(governor_);
        mocSource = mocSource_;
        tcYeldRecipient = tcYeldRecipient_;
        tpYeldRecipient = tpYeldRecipient_;
    }

    /**
     * @notice get total value locked (TVL) in the system
     * @param mocSource_ Moc contract
     * @param extraData_ array of extra data
     * @return tvl total value locked in the system AC [PREC]
     */
    function _getTVL(address mocSource_, uint256[] memory extraData_) internal view virtual returns (uint256 tvl);

    /**
     * @notice get the locked AC in the system
     * @param mocSource_ Moc contract
     * @param extraData_ array of extra data
     * @return lckAC locked AC in the system [PREC]
     */
    function _getLckAC(address mocSource_, uint256[] memory extraData_) internal view virtual returns (uint256 lckAC);

    /**
     * @notice get global coverage
     * @param mocSource_ Moc contract
     * @return coverage current global coverage [PREC]
     */
    function _getCoverage(address mocSource_) internal view virtual returns (uint256 coverage);

    /**
     * @notice get target coverage adjusted by EMA
     * @param mocSource_ Moc contract
     * @return targetCoverageAdj target coverage adjusted by EMA [PREC]
     */
    function _getTargetCoverageAdj(address mocSource_) internal view virtual returns (uint256 targetCoverageAdj);

    /**
     * @notice get the extra data used to calculate
     * @param mocSource_ Moc contract
     * @return extraData_ array of extra data
     */
    function _getExtraData(address mocSource_) internal view virtual returns (uint256[] memory extraData_);

    /**
     * @notice get the available amount to mint in the system
     * @param mocSource_ Moc contract
     * @param extraData_ array of extra data
     * @return availableToMint available amount to mint in the system [PREC]
     */
    function _getAvailableToMint(address mocSource_, uint256[] memory extraData_) internal view returns (uint256) {
        uint256 tvl = _getTVL(mocSource_, extraData_);
        uint256 coverage = _getCoverage(mocSource_);
        uint256 targetCoverageAdj = _getTargetCoverageAdj(mocSource_);
        if (coverage == UINT256_MAX) return UINT256_MAX;
        if (coverage <= targetCoverageAdj || targetCoverageAdj <= ONE) return 0;
        // [PREC²] = [PREC] * ([PREC] - [PREC])
        uint256 num = (tvl * (coverage - targetCoverageAdj));
        // [PREC] = ([PREC] - [PREC]) * [PREC] / [PREC]
        uint256 den = _mulPrec(targetCoverageAdj - ONE, coverage);
        // [PREC] = [PREC²] / [PREC]
        return num / den;
    }

    /**
     * @inheritdoc IRatioSource
     */
    function getRatio() external view returns (uint256[] memory ratios, address[] memory recipients) {
        ratios = new uint256[](2);
        recipients = new address[](2);
        uint256 tpRatio;
        uint256 tcRatio;

        address moc = mocSource;
        uint256[] memory extraData = _getExtraData(mocSource);
        uint256 availableToMint = _getAvailableToMint(moc, extraData);
        if (availableToMint == UINT256_MAX) {
            // there is no locked AC in TP
            tcRatio = ONE;
            tpRatio = 0;
        } else if (availableToMint == 0) {
            // there is no AC available to mint
            tcRatio = 0;
            tpRatio = ONE;
        } else {
            uint256 lckAC = _getLckAC(moc, extraData);
            // [PREC] = [PREC] * [PREC] / [PREC]
            tpRatio = _divPrec(lckAC, lckAC + availableToMint);
            tcRatio = ONE - tpRatio;
        }

        ratios[0] = tcRatio;
        ratios[1] = tpRatio;
        recipients[0] = tcYeldRecipient;
        recipients[1] = tpYeldRecipient;
    }

    /**
     * @notice get the total value locked (TVL) in the system, normalized to bucket(0) AC
     * @return tvl total value locked in the system, normalized to bucket(0) AC [N]
     */
    function getTVL() external view returns (uint256) {
        return _getTVL(mocSource, _getExtraData(mocSource)) / PRECISION;
    }

    /**
     * @notice get the locked AC in the system, normalized to bucket(0) AC
     * @return lckAC locked AC in the system, normalized to bucket(0) AC [N]
     */
    function getLckAC() external view returns (uint256) {
        return _getLckAC(mocSource, _getExtraData(mocSource)) / PRECISION;
    }

    /**
     * @notice get global coverage
     * @return coverage current global coverage [PREC]
     */
    function getCoverage() external view returns (uint256) {
        return _getCoverage(mocSource);
    }

    /**
     * @notice get target coverage adjusted by EMA
     * @return targetCoverageAdj target coverage adjusted by EMA [PREC]
     */
    function getTargetCoverageAdj() external view returns (uint256) {
        return _getTargetCoverageAdj(mocSource);
    }

    /**
     * @notice get the extra data used to calculate
     * @return extraData_ array of extra data
     */
    function getExtraData() external view returns (uint256[] memory) {
        return _getExtraData(mocSource);
    }

    /**
     * @notice get the available amount to mint in the system, normalized to bucket(0) AC
     * @return availableToMint available amount to mint in the system, normalized to bucket(0) AC [N]
     */
    function getAvailableToMint() external view returns (uint256) {
        return _getAvailableToMint(mocSource, _getExtraData(mocSource)) / PRECISION;
    }

    // ------- Only Authorized Changer Functions -------

    /**
     * @notice set the Moc contract address
     * @dev only the authorized changer can call this function
     * @param mocSource_ address of the Moc contract
     */
    function setMocSource(address mocSource_) external onlyAuthorizedChanger {
        mocSource = mocSource_;
    }

    /**
     * @notice set the TC yeld recipient address
     * @dev only the authorized changer can call this function
     * @param tcYeldRecipient_ address of the TC yeld recipient
     */
    function setTCYeldRecipient(address tcYeldRecipient_) external onlyAuthorizedChanger {
        tcYeldRecipient = tcYeldRecipient_;
    }

    /**
     * @notice set the TP yeld recipient address
     * @dev only the authorized changer can call this function
     * @param tpYeldRecipient_ address of the TP yeld recipient
     */
    function setTPYeldRecipient(address tpYeldRecipient_) external onlyAuthorizedChanger {
        tpYeldRecipient = tpYeldRecipient_;
    }
}
