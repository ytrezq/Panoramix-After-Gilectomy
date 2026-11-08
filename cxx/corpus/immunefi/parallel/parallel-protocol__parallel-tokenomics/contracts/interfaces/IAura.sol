// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

interface IAuraBoosterLite {
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns (bool);

    function withdrawTo(uint256 _pid, uint256 _amount, address _to) external returns (bool);
}

interface IAuraRewardPool {
    function getReward() external returns (bool);

    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);
}
