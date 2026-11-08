// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface ICaviarChef {
    function balanceOf() external view returns(uint256);
    function userInfo(address _user) external view returns (uint256, uint256);
    function update(address from, address to) external;
    function harvestRebase(address from, address to) external;
    function underlying() external view returns (address);
    function seedRewards(uint256 _amount) external;
    function claimEmissions() external returns (uint256);
    function harvest(address to) external;
    function deposit(uint256 amount, address to) external;
    function withdraw(uint256 amount, address to) external;
    function withdrawAndHarvest(uint256 amount, address to) external;
}