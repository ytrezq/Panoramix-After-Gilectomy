//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IGyroPool {
    function getPrice() external view returns(uint256);
    function getActualSupply() external view returns(uint256);
}
