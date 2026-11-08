//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface ISilo {
    function deposit(uint256 _assets, address _receiver, uint8 _collateralType) external;
    function redeem(uint256 _shares, address _receiver, address _owner, uint8 _collateralType) external;
    function withdraw(uint256 _assets, address _receiver, address _owner, uint8 _collateralType) external;
}