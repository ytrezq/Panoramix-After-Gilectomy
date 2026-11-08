// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

interface IRatioSource {
    /**
     * @notice get the ratio of the split
     * @dev The sum of the ratios must be equal to 1e18 (100%)
     * @return ratios array of ratios for each recipient [PREC]
     * @return recipients array of addresses to receive the split
     */
    function getRatio() external view returns (uint256[] memory ratios, address[] memory recipients);
}
