// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface IGlobalsLike {

    function governor() external view returns (address governor_);
    
    function isInstanceOf(bytes32 instanceKey_, address instance_) external view returns (bool isInstance_);

    function isValidScheduledCall(
        address          caller_,
        address          contract_,
        bytes32          functionId_,
        bytes   calldata callData_
    ) external view returns (bool isValid_);

    function mapleTreasury() external view returns (address mapleTreasury_);

    function scheduleCall(address contract_, bytes32 functionId_, bytes calldata callData_) external;

    function scheduledCalls(
        address caller_,
        address contract_,
        bytes32 functionId_
    ) external view returns (uint256 timestamp, bytes32 dataHash);

    function setDefaultTimelockParameters(uint128 defaultTimelockDelay_, uint128 defaultTimelockDuration_) external;

    function setMapleTreasury(address mapleTreasury_) external;

    function setValidInstanceOf(bytes32 instanceKey_, address instance_, bool isValid_) external;

    function setTimelockWindow(address contract_, bytes32 functionId_, uint128 delay_, uint128 duration_) external;

    function timelockParametersOf(address contract_, bytes32 functionId_) external view returns (uint128 delay, uint128 duration);

    function unscheduleCall(address caller_, bytes32 functionId_, bytes calldata callData_) external;

    function unscheduleCall(address caller_, address contract_, bytes32 functionId_, bytes calldata callData_) external;

}

interface IXmplLike {

    function asset() external view returns (address asset);

    function cancelMigration() external;

    function performMigration() external;

    function scheduleMigration(address migrator, address newAsset) external;

    function MINIMUM_MIGRATION_DELAY() external pure returns (uint256 minimumMigrationDelay);

    function owner() external view returns (address owner);

    function scheduledMigrationTimestamp() external view returns (uint256 scheduledMigrationTimestamp);

    function scheduledMigrator() external view returns (address scheduledMigrator);

    function scheduledNewAsset() external view returns (address scheduledNewAsset);

}
