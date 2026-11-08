// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

interface IERC4626Like {

    function allowance(address owner, address spender) external view returns (uint256);
    
    function approve(address spender, uint256 amount) external returns (bool);

    function asset() external view returns (address);

    function balanceOf(address owner) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets);

    function totalSupply() external view returns (uint256);

}
