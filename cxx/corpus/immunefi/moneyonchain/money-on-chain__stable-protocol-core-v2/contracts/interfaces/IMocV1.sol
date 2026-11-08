// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

interface IMocV1 {
    /**
     * @notice GLOBAL Coverage
     * @return [PREC]
     */
    function globalCoverage() external view returns (uint256);

    /**
     * @notice Target coverage for complete system
     * @return [PREC]
     */
    function cobj() external view returns (uint256);

    /**
     * @notice Amount of Bitcoins in the system excluding BTCx values and interests holdings
     * @return [N]
     */
    function collateralRbtcInSystem() external view returns (uint256);

    /**
     * @notice GLOBAL lockedBitcoin
     * @return [PREC]
     */
    function globalLockedBitcoin() external view returns (uint256);

    /**
     * @notice BTC price in USD
     * @return [PREC]
     */
    function getBitcoinPrice() external view returns (uint256);

    /**
     * @notice BTC conservative price in USD
     * @return [PREC]
     */
    function getBcons() external view returns (uint256);
}
