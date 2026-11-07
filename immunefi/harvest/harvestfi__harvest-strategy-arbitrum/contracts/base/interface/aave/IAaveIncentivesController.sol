// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.26;

interface IAaveIncentivesController {
	function claimAllRewards(address[] calldata assets, address to) external;
	function claimRewards(address[] calldata assets, uint256 amount, address to, address reward) external;
	function getUserAccruedRewards(address user, address reward) external view returns(uint256);
}