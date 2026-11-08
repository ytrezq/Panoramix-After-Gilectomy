// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { TokenRatioSource } from "../TokenRatioSource.sol";
import { IMocV2 } from "../../../interfaces/IMocV2.sol";
import { IPriceProvider } from "../../../interfaces/IPriceProvider.sol";

/**
 * @title TPRatioSourceV2
 * @notice Ratio source for the MocV2 TP MocTokenAllocator
 * @dev This contract is used to define the split ratio calculating the amount of AC locked by each Pegged Token.
 *  The recipients are N addresses, one for each TP
 */
contract TPRatioSourceV2 is TokenRatioSource {
    // ------- Custom Errors -------
    error MissingProviderPrice(address priceProviderAddress_);

    /**
     * @notice constructor
     * @dev index of TP address in the array should be the same as the index of the recipient addresses
     * @param governor_ address of the governor contract
     * @param mocV2_ address of the MocV2 contract
     * @param tpAddresses_ addresses of the TP
     * @param yeldRecipients_ addresses who receive the split
     */
    constructor(address governor_, address mocV2_, address[] memory tpAddresses_, address[] memory yeldRecipients_) {
        _initialize(governor_, mocV2_, tpAddresses_, yeldRecipients_);
    }

    /**
     * @notice get the amount of TPs
     * @return length
     */
    function _getTokenLength(address mocSource_) internal view override returns (uint256 length) {
        return IMocV2(mocSource_).getTpAmount();
    }

    /**
     * @notice get the recipient when there is only one TP
     * @return yeldRecipient address who receives all the funds when there is only one TP
     */
    function _getUniqueRecipient(address mocSource_) internal view override returns (address yeldRecipient) {
        return yeldRecipients[address(IMocV2(mocSource_).tpTokens(0))];
    }

    /**
     * @notice get the extra data used to calculate
     * @return extraData_ array of extra data
     */
    function _getExtraData(address /*mocSource_*/) internal pure override returns (uint256[] memory extraData_) {
        return new uint256[](0);
    }

    /**
     * @notice get the locked AC in the system
     * @param mocSource_ Moc contract
     * @param tokenLength_ amount of TP
     * @return totalLckAC total locked AC in the system [PREC]
     * @return lckACByTP array of locked AC by TP [PREC]
     * @return tpAddresses array of TP addresses
     */
    function _getShares(
        address mocSource_,
        uint256 tokenLength_,
        uint256[] memory /*extraData_*/
    ) internal view override returns (uint256 totalLckAC, uint256[] memory lckACByTP, address[] memory tpAddresses) {
        lckACByTP = new uint256[](tokenLength_);
        tpAddresses = new address[](tokenLength_);
        IMocV2 mocV2 = IMocV2(mocSource_);
        for (uint256 i = 0; i < tokenLength_; i = unchecked_inc(i)) {
            tpAddresses[i] = address(mocV2.tpTokens(i));
            (uint256 ntp, address priceProvider) = mocV2.pegContainer(i);
            (bytes32 price, bool has) = IPriceProvider(priceProvider).peek();
            if (!has) revert MissingProviderPrice(priceProvider);
            // [PREC] = [N] * [PREC] * [PREC] / [PREC]
            lckACByTP[i] += _divPrec(ntp * PRECISION, uint256(price));
            // [PREC] = [PREC] + [PREC]
            totalLckAC += lckACByTP[i];
        }
    }
}
