// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { Governed, IGovernor } from "../../governance/Governed.sol";
import { IRatioSource } from "../../interfaces/IRatioSource.sol";

/**
 * @title TokenRatioSource
 * @notice Ratio source for the MocTokenAllocator
 * @dev This contract is used to define the split ratio calculating the amount of AC locked by each Token.
 *  The recipients are N addresses, one for each Token
 */
abstract contract TokenRatioSource is IRatioSource, Governed {
    // ------- Storage -------

    // Moc contract
    address public mocSource;
    // map the Token address to the recipient address
    mapping(address tokenAddress => address yieldRecipient) public yeldRecipients;

    /**
     * @notice construct
     * @dev index of Token address in the array should be the same as the index of the yeld recipient addresses
     * @param governor_ address of the governor contract
     * @param mocSource_ address of the Moc contract
     * @param tokenAddress_ addresses of the Token
     * @param yeldRecipients_ addresses who receive the split
     */
    function _initialize(
        address governor_,
        address mocSource_,
        address[] memory tokenAddress_,
        address[] memory yeldRecipients_
    ) internal {
        _disableInitializers();
        governor = IGovernor(governor_);
        mocSource = mocSource_;
        for (uint256 i = 0; i < tokenAddress_.length; i = unchecked_inc(i)) {
            yeldRecipients[tokenAddress_[i]] = yeldRecipients_[i];
        }
    }

    /**
     * @notice get the amount of tokens
     * @return length
     */
    function _getTokenLength(address mocSource_) internal view virtual returns (uint256 length);

    /**
     * @notice get the recipient when there is only one
     * @return yeldRecipient address who receives all the funds when is the only one
     */
    function _getUniqueRecipient(address mocSource_) internal view virtual returns (address yeldRecipient);

    /**
     * @notice get the shares of each Token
     * @param mocSource_ Moc contract
     * @param extraData_ array of extra data
     * @return totalShares total shares [PREC]
     * @return shareByToken array of shares by Token [PREC]
     * @return tokenAddresses array of Token addresses
     */
    function _getShares(
        address mocSource_,
        uint256 tokenLength_,
        uint256[] memory extraData_
    )
        internal
        view
        virtual
        returns (uint256 totalShares, uint256[] memory shareByToken, address[] memory tokenAddresses);

    /**
     * @notice get the extra data used to calculate
     * @param mocSource_ Moc contract
     * @return extraData_ array of extra data
     */
    function _getExtraData(address mocSource_) internal view virtual returns (uint256[] memory extraData_);

    /**
     * @inheritdoc IRatioSource
     */
    function getRatio() external view returns (uint256[] memory ratios, address[] memory recipients) {
        address moc = mocSource;
        uint256 tokenLength = _getTokenLength(moc);
        // if there is only one Token, the ratio is 100% for the only recipient
        if (tokenLength == 1) {
            ratios = new uint256[](1);
            recipients = new address[](1);
            ratios[0] = ONE;
            recipients[0] = _getUniqueRecipient(moc);
            return (ratios, recipients);
        }
        (uint256 totalShares, uint256[] memory shareByToken, address[] memory tokenAddresses) = _getShares(
            moc,
            tokenLength,
            _getExtraData(moc)
        );

        ratios = new uint256[](tokenAddresses.length);
        recipients = new address[](tokenAddresses.length);
        for (uint256 i = 0; i < tokenAddresses.length; i = unchecked_inc(i)) {
            // because all the division are truncated, the sum of the ratios could never be greater than 100%
            // [PREC] = [PREC] * [PREC] / [PREC]
            ratios[i] = _divPrec(shareByToken[i], totalShares);
            recipients[i] = yeldRecipients[tokenAddresses[i]];
        }
    }

    /**
     * @notice get the amount of tokens
     * @return length
     */
    function getTokenLength() external view returns (uint256 length) {
        return _getTokenLength(mocSource);
    }

    /**
     * @notice get the total shares
     * @return totalShares [N]
     */
    function getTotalShares() external view returns (uint256 totalShares) {
        (totalShares, , ) = _getShares(mocSource, _getTokenLength(mocSource), _getExtraData(mocSource));
        return totalShares / PRECISION;
    }

    /**
     * @notice get the array of shares by Token
     * @return shareByToken array of shares by Token [N]
     */
    function getShareArray() external view returns (uint256[] memory shareByToken) {
        (, shareByToken, ) = _getShares(mocSource, _getTokenLength(mocSource), _getExtraData(mocSource));
        for (uint256 i = 0; i < shareByToken.length; i = unchecked_inc(i)) {
            shareByToken[i] = shareByToken[i] / PRECISION;
        }
    }

    /**
     * @notice get the shares by Token
     * @param tokenAddress address of the Token
     * @return shareByToken shares by Token [N]
     */
    function getShareByToken(address tokenAddress) external view returns (uint256 shareByToken) {
        (, uint256[] memory shareByTokenArray, address[] memory tokenAddresses) = _getShares(
            mocSource,
            _getTokenLength(mocSource),
            _getExtraData(mocSource)
        );
        for (uint256 i = 0; i < tokenAddresses.length; i = unchecked_inc(i)) {
            if (tokenAddresses[i] == tokenAddress) {
                shareByToken = shareByTokenArray[i];
                break;
            }
        }
        return shareByToken / PRECISION;
    }

    /**
     * @notice get the extra data used to calculate
     * @return extraData_ array of extra data
     */
    function getExtraData() external view returns (uint256[] memory) {
        return _getExtraData(mocSource);
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
     * @notice set the yeld recipient address
     * @dev only the authorized changer can call this function
     * @param tokenAddress_ address of the Token
     * @param yeldRecipient_ address who receive the split
     */
    function setYeldRecipient(address tokenAddress_, address yeldRecipient_) external onlyAuthorizedChanger {
        yeldRecipients[tokenAddress_] = yeldRecipient_;
    }
}
