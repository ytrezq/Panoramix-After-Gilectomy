//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface ICToken {
    function balanceOf(address owner) external view returns(uint256);
    function balanceOfUnderlying(address owner) external view returns (uint256);
    function redeem(uint256) external;
    function redeemUnderlying(uint256) external;
}