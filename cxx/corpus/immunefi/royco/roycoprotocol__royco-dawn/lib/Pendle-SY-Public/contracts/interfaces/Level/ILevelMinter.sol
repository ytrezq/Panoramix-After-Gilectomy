// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ILevelMinter {
    enum OrderType {
        MINT,
        REDEEM
    }

    struct Order {
        OrderType order_type;
        address benefactor;
        address beneficiary;
        address collateral_asset;
        uint256 collateral_amount;
        uint256 lvlusd_amount;
    }

    function mintDefault(Order memory order) external;

    function oracles(address token) external view returns (address);
}
