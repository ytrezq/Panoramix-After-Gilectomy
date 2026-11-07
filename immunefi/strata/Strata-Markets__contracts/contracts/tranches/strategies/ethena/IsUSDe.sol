// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IsUSDe is IERC4626 {
    struct TUserCooldown {
        uint104 cooldownEnd;
        uint152 underlyingAmount;
    }

    function cooldownDuration() external view returns (uint24);
    function unstake(address receiver) external;
    function cooldownAssets(uint256 assets) external returns (uint256);
    function cooldownShares(uint256 shares) external returns (uint256);

    function cooldowns (address user) external view returns (TUserCooldown memory);

    function lastDistributionTimestamp() external view returns (uint256);
    function vestingAmount() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function getUnvestedAmount () external view returns (uint256);
}
