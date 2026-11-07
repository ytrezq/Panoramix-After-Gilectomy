// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.22;

interface IERC20Like {

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

}
