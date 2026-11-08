// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {DeployParams} from "../Types.sol";

struct CreditManagerParams {
    uint8 maxEnabledTokens;
    uint16 feeInterest;
    uint16 feeLiquidation;
    uint16 liquidationPremium;
    uint16 feeLiquidationExpired;
    uint16 liquidationPremiumExpired;
    uint128 minDebt;
    uint128 maxDebt;
    string name;
    DeployParams accountFactoryParams;
}

struct CreditFacadeParams {
    address degenNFT;
    bool expirable;
    bool migrateBotList;
}

interface ICreditConfigureActions {
    function upgradeCreditConfigurator() external;
    function upgradeCreditFacade(CreditFacadeParams calldata params) external;
    function allowAdapter(DeployParams calldata params) external;
    function forbidAdapter(address adapter) external;
    function configureAdapterFor(address targetContract, bytes calldata data) external;
    function setFees(
        uint16 feeLiquidation,
        uint16 liquidationPremium,
        uint16 feeLiquidationExpired,
        uint16 liquidationPremiumExpired
    ) external;
    function setMaxDebtPerBlockMultiplier(uint8 newMaxDebtLimitPerBlockMultiplier) external;
    function addCollateralToken(address token, uint16 liquidationThreshold) external;
    function rampLiquidationThreshold(
        address token,
        uint16 liquidationThresholdFinal,
        uint40 rampStart,
        uint24 rampDuration
    ) external;
    function forbidToken(address token) external;
    function allowToken(address token) external;
    function setExpirationDate(uint40 newExpirationDate) external;
    function pause() external;
    function unpause() external;
}
