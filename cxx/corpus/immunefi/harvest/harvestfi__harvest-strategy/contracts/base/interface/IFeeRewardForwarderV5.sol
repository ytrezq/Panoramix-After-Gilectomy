//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IFeeRewardForwarderV5 {
    function poolNotifyFixedTarget(address _token, uint256 _amount) external;

    function notifyFeeAndBuybackAmounts(uint256 _feeAmount, address _pool, uint256 _buybackAmount) external;
    function profitSharingPool() external view returns (address);
}
