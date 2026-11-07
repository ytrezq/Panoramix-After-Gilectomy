// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {Deployer} from "silo-foundry-utils/deployer/Deployer.sol";

contract CommonDeploy is Deployer {
    // Common variables
    string internal constant _FORGE_OUT_DIR = "out";
    string internal constant _DEPLOYMENTS_SUB_DIR = "";
    string internal constant _BASE_DIR = "test/deployer/mocks";

    // Smart contracts list
    string internal constant _COUNTER_SOL = "Counter.sol";
    string internal constant _COUNTER_VY = "Counter.vy";

    function _forgeOutDir() internal pure virtual override returns (string memory) {
        return _FORGE_OUT_DIR;
    }

    function _deploymentsSubDir() internal pure virtual override returns (string memory) {
        return _DEPLOYMENTS_SUB_DIR;
    }

    function _contractBaseDir() internal pure virtual override returns (string memory) {
        return _BASE_DIR;
    }
}
