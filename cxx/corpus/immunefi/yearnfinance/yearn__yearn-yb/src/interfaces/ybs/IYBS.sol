// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IYBS {

    enum ApprovalStatus {
        None,               // 0. Default value, indicating no approval
        StakeOnly,          // 1. Approved for stake only
        UnstakeOnly,        // 2. Approved for unstake only
        StakeAndUnstake     // 3. Approved for both stake and unstake
    }

    function stakeFor(address account, uint256 amount) external returns (uint256);

    function unstakeFor(
        address account,
        uint256 amount,
        address receiver
    ) external returns (uint256);

    function balanceOf(address account) external view returns (uint256);
    function setApprovedCaller(address caller, ApprovalStatus status) external;
}
