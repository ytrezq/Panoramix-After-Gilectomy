// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

contract GlobalsHelper {

    function governor() external view returns (address governor) {
        return address(0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196);
    }

    function isInstanceOf(bytes32 instanceKey, address instance) external view returns (bool isInstance) {
        return true;
    }

    function isValidScheduledCall(
        address          caller,
        address          target,
        bytes32          functionId,
        bytes   calldata callData
    ) external view returns (bool isValidScheduledCall) {
        return true;
    }

    function mapleTreasury() external view returns (address mapleTreasury) {
        return address(0xa9466EaBd096449d650D5AEB0dD3dA6F52FD0B19);
    }

    function unscheduleCall(address caller, bytes32 functionId, bytes calldata callData) external {}

}
