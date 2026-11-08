// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMErc20 is IERC20 {
    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function accrualBlockTimestamp() external view returns (uint256);

    function getCash() external view returns (uint256);

    function totalBorrows() external view returns (uint256);

    function totalReserves() external view returns (uint256);

    function borrowIndex() external view returns (uint256);

    function interestRateModel() external view returns (address);

    function totalSupply() external view returns (uint256);

    function reserveFactorMantissa() external view returns (uint256);

    function underlying() external view returns (address);

    function comptroller() external view returns (address);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function mint(uint256 mintAmount) external returns (uint256);
}

interface IMToken is IMErc20 {}

interface IMInterestRateModel {
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256);
}

interface IMComptroller {
    function supplyCaps(address mToken) external view returns (uint256);

    function claimReward(address holder, address[] memory mTokens) external;

    function rewardDistributor() external view returns (address);
}

interface IMRewardDistributor {
    struct RewardInfo {
        address emissionToken;
        uint256 totalAmount;
        uint256 supplySide;
        uint256 borrowSide;
    }

    function getOutstandingRewardsForUser(address _mToken, address _user) external view returns (RewardInfo[] memory);
}
