// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import {IRegistry} from "./IRegistry.sol";
import {IVestingMachine} from "./IVestingMachine.sol";

interface IVestingFactory {
    /// @notice Create a holder wallet
    /// @param holder wallet's owner
    /// @param percentages percentages allowed in each step
    /// @param timedeltas duration of each step
    function create(address holder, uint256[] memory percentages, uint256[] memory timedeltas) external;

    /// @notice Update the vesting machine values
    /// function update(
    ///     IVestingMachine wallet,
    ///     uint256[] memory percentages,
    ///     uint256[] memory timedeltas
    /// ) external;

    /// @notice Set the TGE time enabling holder wallets
    function setTGE() external;

    /// @notice Returns true when the TGE was configured
    function isTGEConfigured() external view returns (bool);

    /// @notice Returns the configured TGE timestamp
    function getTGETimestamp() external view returns (uint256);

    /// @notice Set a holder wallet balance
    /// @param wallet the vesting machine
    /// @param amount wallet balance
    function setTotal(IVestingMachine wallet, uint256 amount) external;

    /// @notice Return registry
    function getRegistry() external view returns (IRegistry);

    /// @notice Get the length of the list of vesting machines
    function getVestingMachinesLen() external view returns (uint256);

    /// @notice Get the an entry of the list of vesting machines
    /// @param idx the index in the list
    function getVestingMachinesEntry(uint256 idx) external view returns (address);
}
