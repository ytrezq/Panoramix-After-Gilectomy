// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

interface IDeployerSharedMemory {
    function deploymentsSyncDisabled() external view returns (bool);
}
