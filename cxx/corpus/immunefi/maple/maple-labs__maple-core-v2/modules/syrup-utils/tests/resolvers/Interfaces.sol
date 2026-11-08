// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

interface IGlobalsLike {

    function setOperationalAdmin(address operationalAdmin) external;

}

interface IMigratorLike {

    function setActive(bool active_) external;

}

interface IRdtLike {

    function approve(address spender, uint256 amount) external returns (bool success_);

    function balanceOf(address account) external view returns (uint256 balance);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares_);

}
