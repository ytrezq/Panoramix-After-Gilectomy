// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.22;

import { ReserveConfiguration } from "../../lib/aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes }            from "../../lib/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

import { MockToken } from "./MockToken.sol";

contract MockPool {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /**********************************************************************************************/
    /*** Declarations and Constructor                                                           ***/
    /**********************************************************************************************/

    address public aToken;
    address public debtToken;

    uint256 public liquidityIndex;
    uint256 public accruedToTreasury;

    uint256 public supplyCap;
    uint256 public borrowCap;

    uint256 public decimals;

    constructor() {
        aToken    = address(new MockToken());
        debtToken = address(new MockToken());
    }

    /**********************************************************************************************/
    /*** Pool Functions                                                                         ***/
    /**********************************************************************************************/

    function getReserveData(address) external view returns (DataTypes.ReserveData memory) {
        DataTypes.ReserveConfigurationMap memory configuration
            = DataTypes.ReserveConfigurationMap(0);

        configuration.setBorrowCap(borrowCap);
        configuration.setSupplyCap(supplyCap);

        configuration.setDecimals(decimals);

        return DataTypes.ReserveData({
            configuration:               configuration,
            liquidityIndex:              uint128(liquidityIndex),
            currentLiquidityRate:        uint128(0),
            variableBorrowIndex:         uint128(0),
            currentVariableBorrowRate:   uint128(0),
            currentStableBorrowRate:     uint128(0),
            lastUpdateTimestamp:         uint40(0),
            id:                          uint16(0),
            aTokenAddress:               aToken,
            stableDebtTokenAddress:      address(0),
            variableDebtTokenAddress:    debtToken,
            interestRateStrategyAddress: address(0),
            accruedToTreasury:           uint128(accruedToTreasury),
            unbacked:                    uint128(0),
            isolationModeTotalDebt:      uint128(0)
        });
    }

    /**********************************************************************************************/
    /*** Mock Functions                                                                         ***/
    /**********************************************************************************************/

    function __setSupplyCap(uint256 supplyCap_) external {
        supplyCap = supplyCap_;
    }

    function __setBorrowCap(uint256 borrowCap_) external {
        borrowCap = borrowCap_;
    }

    function __setATokenScaledTotalSupply(uint256 aTokenScaledTotalSupply_) external {
        MockToken(aToken).__setScaledTotalSupply(aTokenScaledTotalSupply_);
    }

    function __setTotalDebt(uint256 totalDebt_) external {
        MockToken(debtToken).__setTotalSupply(totalDebt_);
    }

    function __setLiquidityIndex(uint256 liquidityIndex_) external {
        liquidityIndex = liquidityIndex_;
    }

    function __setAccruedToTreasury(uint256 accruedToTreasury_) external {
        accruedToTreasury = accruedToTreasury_;
    }

    function __setDecimals(uint256 decimals_) external {
        decimals = decimals_;
    }

}
