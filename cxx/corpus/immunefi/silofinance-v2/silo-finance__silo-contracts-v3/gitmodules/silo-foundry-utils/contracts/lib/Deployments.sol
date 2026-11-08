// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9.0;

import {IDeployerSharedMemory} from "../deployer/IDeployerSharedMemory.sol";
import {KeyValueStorage} from "../key-value/KeyValueStorage.sol";
import {VmLib} from "./VmLib.sol";
import {AddrLib} from "./AddrLib.sol";

library Deployments {
    bool public constant DEPLOYMENTS_SYNC_DISABLED_FLAG = true;
    bool public constant DEPLOYMENTS_SYNC_ENABLED_FLAG = false;

    address public constant DEPLOYER_SHARED_MEMORY =
        address(uint160(uint256(keccak256("silo foundry utils: deployer"))));

    /// @notice Disables deployments synchronization
    function disableDeploymentsSync() internal {
        mockDeploymentsSyncStatus(DEPLOYMENTS_SYNC_DISABLED_FLAG);
    }

    /// @notice Enables deployments synchronization
    function enableDeploymentsSync() internal {
        mockDeploymentsSyncStatus(DEPLOYMENTS_SYNC_ENABLED_FLAG);
    }

    /// @dev Allocate in the `shared memory` a flag that marks wether the deployments synchronization in enabled or not
    function mockDeploymentsSyncStatus(bool _flag) internal {
        VmLib.vm()
            .mockCall(
                DEPLOYER_SHARED_MEMORY,
                abi.encodePacked(IDeployerSharedMemory.deploymentsSyncDisabled.selector),
                abi.encode(_flag)
            );
    }

    /// @dev The developer can operate from scripts if it is needed to synchronize deployments.
    /// For example, deployments synchronization should be disabled in tests but enabled in scripts.
    function deploymentsSyncDisabled() internal view returns (bool result) {
        (, bytes memory data) =
            DEPLOYER_SHARED_MEMORY.staticcall(abi.encodePacked(IDeployerSharedMemory.deploymentsSyncDisabled.selector));

        if (data.length == 0) return DEPLOYMENTS_SYNC_ENABLED_FLAG;

        assembly {
            // solhint-disable-line no-inline-assembly
            result := mload(add(data, 0x20))
        }
    }

    function getAddress(string memory _deploymentsFolder, string memory _networkAlias, string memory _smartContractName)
        internal
        returns (address result)
    {
        result = AddrLib.getAddress(_networkAlias, _smartContractName);

        if (result != address(0)) {
            return result;
        }

        string memory filePath = string(
            abi.encodePacked(_deploymentsFolder, "/deployments/", _networkAlias, "/", _smartContractName, ".json")
        );

        result = KeyValueStorage.getAddress(filePath, "", "address");

        if (result != address(0)) {
            VmLib.vm().label(result, _smartContractName);
        }
    }
}
