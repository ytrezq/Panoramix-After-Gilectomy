// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IListaClisBNBSwap {
    function provide(uint256 _amount, address _delegateTo) external returns (uint256);

    function release(address _recipient, uint256 _amount) external returns (uint256);

    function exchangeRate() external view returns (uint128);

    function syncUserLp(address _account) external;
}
