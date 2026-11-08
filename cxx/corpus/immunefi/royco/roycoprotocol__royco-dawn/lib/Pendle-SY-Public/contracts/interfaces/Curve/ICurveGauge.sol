// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ICurveGauge {
    function lp_token() external view returns (address);

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function claim_rewards() external;
}
