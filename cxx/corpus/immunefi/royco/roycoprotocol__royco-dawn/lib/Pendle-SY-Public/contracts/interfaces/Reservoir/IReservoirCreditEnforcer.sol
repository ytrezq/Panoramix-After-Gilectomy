// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface IReservoirCreditEnforcer {
    function mintStablecoin(uint256) external returns (uint256);
}
