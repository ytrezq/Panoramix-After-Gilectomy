// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IdleToken {
    function tokenPrice() external view returns (uint256 price);

    function token() external view returns (address);
    function getAPRs() external view returns (address[] memory addresses, uint256[] memory aprs);


    function mintIdleToken(uint256 _amount, bool _skipRebalance, address _referral) external returns (uint256 mintedTokens);

    function redeemIdleToken(uint256 _amount) external returns (uint256 redeemedTokens);
    function redeemInterestBearingTokens(uint256 _amount) external;

    function rebalance() external returns (bool);
}
