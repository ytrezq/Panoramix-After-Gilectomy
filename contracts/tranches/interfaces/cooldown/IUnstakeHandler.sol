// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


interface IUnstakeHandler {
    function initialize (address handler, address user) external;

    function request () external returns (uint256 unlockAt);
    function request (address receiver) external returns (uint256 unlockAt);

    function finalize() external returns (uint256);

    function getPendingAmount () external view returns (uint256 amount);

    function isCooldownActive() external view returns (bool);

    function requestedAt () external view returns (uint256);
}
