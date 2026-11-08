// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { WBERA } from "src/WBERA.sol";

abstract contract WBERADeployer is Create2Deployer {
    /// @notice Deploy WBERA contract
    function deployWBERA(uint256 wberaSalt) internal returns (address) {
        address wbera = payable(deployWithCreate2(wberaSalt, type(WBERA).creationCode));
        return wbera;
    }
}
