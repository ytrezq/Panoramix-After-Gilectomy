// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

interface IMocMultiCollateralGuard {
    /**
     * @notice get combined coverage and combined ctargemaCA
     * @param bucket_ bucket that is intended to operate
     * @return combinedCglb combined coverage [PREC]
     * @return combinedCtargemaCA combined ctargemaCA [PREC]
     * @return bucketPACtps all tps prices for the given bucket [PREC]
     */
    function getCombinedValues(
        address bucket_
    ) external returns (uint256 combinedCglb, uint256 combinedCtargemaCA, uint256[] memory bucketPACtps);

    /**
     * @notice get combined values and TC available to redeem
     * @param bucket_ bucket that is intended to operate
     * @return combinedCglb combined coverage [PREC]
     * @return combinedCtargemaCA combined ctargemaCA [PREC]
     * @return realTCAvailableToRedeem real TC available to redeem [N]
     * @return bucketPACtps all tps prices for the given bucket [PREC]
     */
    function getCombinedAndTC(
        address bucket_
    )
        external
        returns (
            uint256 combinedCglb,
            uint256 combinedCtargemaCA,
            uint256 realTCAvailableToRedeem,
            uint256[] memory bucketPACtps
        );

    /**
     * @notice get combined values and TP available to mint
     * @param bucket_ bucket that is intended to operate
     * @param tp_ Pegged Token that is intended to operate
     * @return combinedCglb combined coverage [PREC]
     * @return combinedCtargemaCA combined ctargemaCA [PREC]
     * @return realTPAvailableToMint real TP available to mint [N]
     * @return bucketPACtps all tps prices for the given bucket [PREC]
     */
    function getCombinedAndTP(
        address bucket_,
        address tp_
    )
        external
        returns (
            uint256 combinedCglb,
            uint256 combinedCtargemaCA,
            uint256 realTPAvailableToMint,
            uint256[] memory bucketPACtps
        );

    /**
     * @notice get combined values, TC available to redeem and TP available to mint
     * @param bucket_ bucket that is intended to operate
     * @param tp_ Pegged Token that is intended to operate
     * @return combinedCglb combined coverage [PREC]
     * @return combinedCtargemaCA combined ctargemaCA [PREC]
     * @return realTCAvailableToRedeem real TC available to redeem [N]
     * @return realTPAvailableToMint real TP available to mint [N]
     * @return bucketPACtps all tps prices for the given bucket [PREC]
     */
    function getCombinedAndTCAndTP(
        address bucket_,
        address tp_
    )
        external
        returns (
            uint256 combinedCglb,
            uint256 combinedCtargemaCA,
            uint256 realTCAvailableToRedeem,
            uint256 realTPAvailableToMint,
            uint256[] memory bucketPACtps
        );
}
