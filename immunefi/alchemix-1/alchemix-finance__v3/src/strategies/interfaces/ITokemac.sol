// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IBaseRewarder {
    // actions
    function getReward() external;                              // claim for msg.sender
    function stake(address account, uint256 amount) external;   // stake vault shares on behalf of `account`

    // views
    function earned(address account) external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function rewardRate() external view returns (uint256);      // rate-per-block style
    function tokeLockDuration() external view returns (uint256);
    function lastBlockRewardApplicable() external view returns (uint256);
    function totalSupply() external view returns (uint256);     // total staked
    function balanceOf(address account) external view returns (uint256);
    function rewardToken() external view returns (address);     // e.g., TOKE
    function allowExtraRewards() external view returns (bool);
    
    // admin/ops (usually not needed by integrators, left for completeness)
    function queueNewRewards(uint256 newRewards) external;
    function addToWhitelist(address wallet) external;
    function removeFromWhitelist(address wallet) external;
    function recover(address token, address recipient) external;
    function isWhitelisted(address wallet) external view returns (bool);
}

interface IExtraRewarder is IBaseRewarder {
    // extra rewarder variant (claim-only / separate withdraw)
    function withdraw(address account, uint256 amount) external;
    function getReward(address account, address recipient) external;
}

interface IMainRewarder is IBaseRewarder {
    // full withdraw that can optionally claim extras too
    function withdraw(address account, uint256 amount, bool claim) external;

    function stake(address account, uint256 amount) external; 

    // claim to a recipient; toggle whether to also pull from linked extra rewarders
    function getReward(address account, address recipient, bool claimExtras) external;

    // optional discovery helpers
    function extraRewardsLength() external view returns (uint256);
    function extraRewards() external view returns (address[] memory);
    function getExtraRewarder(uint256 index) external view returns (IExtraRewarder);
}

interface IAutopilotRouter {
    function depositMax(IERC4626 vault, address to, uint256 minSharesOut) external payable returns (uint256 sharesOut);
    function depositBalance(IERC4626 vault, address to, uint256 minSharesOut) external payable returns (uint256 sharesOut);
    function stakeVaultToken(IERC4626 vault, uint256 maxAmount) external payable returns (uint256 staked);
    function withdrawVaultToken(IERC4626 vault, IMainRewarder rewarder, uint256 maxAmount, bool claim) external payable returns (uint256 withdrawn);
}
