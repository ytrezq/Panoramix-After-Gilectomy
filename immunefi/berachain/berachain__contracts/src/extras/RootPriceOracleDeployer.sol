// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Create2Deployer } from "../base/Create2Deployer.sol";
import { RootPriceOracle } from "src/extras/RootPriceOracle.sol";

/// @title RootPriceOracleDeployer
/// @author Berachain Team
/// @notice The RootPriceOracleDeployer contract is responsible for deploying the RootPriceOracle contract.
contract RootPriceOracleDeployer is Create2Deployer {
    /// @notice The RootPriceOracle contract.
    // solhint-disable-next-line immutable-vars-naming
    RootPriceOracle public immutable rootPriceOracle;

    constructor(address governance, uint256 salt) {
        // deploy the RootPriceOracle
        rootPriceOracle = RootPriceOracle(deployWithCreate2(salt, type(RootPriceOracle).creationCode));

        // initialize the contract
        rootPriceOracle.initialize(governance);
    }
}
