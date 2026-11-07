//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IPendleDepositHelper {
    function totalStaked(address _market) external view returns (uint256);

    function balance(address _market, address _address) external view returns (uint256);

    function depositMarket(address _market, uint256 _amount) external;

    function withdrawMarket(address _market, uint256 _amount) external;
}