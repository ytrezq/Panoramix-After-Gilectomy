// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IRewardsDistributor {
    struct ClaimInfo {
        uint256 epoch;
        uint256 amount;
        bytes32[] proof;
    }
    function claim(ClaimInfo[] calldata _claimInfo) external;
}