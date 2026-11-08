// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {DeployResult} from "../Types.sol";
import {IMarketFactory} from "./IMarketFactory.sol";

interface IPriceOracleFactory is IMarketFactory {
    function deployPriceOracle(address pool) external returns (DeployResult memory);

    function computePriceOracleAddress(address marketConfigurator, address pool) external view returns (address);
}
