// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

interface IVestingMachine {
    /// @notice Retrieve vesting parameters
    function getParameters() external view returns (uint256[] memory, uint256[] memory);

    /// @notice Mark contract as verified by holder
    function verify() external;

    /// @notice Returns current holder address
    function getHolder() external view returns (address);

    /// @notice Calls a function from target passing data
    /// @param target Target contract to call (must be one of: staking, vesting or voting machine)
    /// @param data Data to pass target contract
    function callWithData(address target, bytes memory data) external;

    /// @notice approve a transfer to the staking machine.
    /// @param amount Token amount to approve
    function approve(uint256 amount) external;

    /// @notice deposit MOCs in the staking machine
    /// @param amount Token amount to approve
    function deposit(uint256 amount) external;

    /// @notice Withdraws tokens to holder address
    /// @param amount Tokens amount to withdraw
    /// @return Returns true on success
    function withdraw(uint256 amount) external returns (bool);

    /// @notice Withdraws all available tokens to holder address
    /// @return Returns true on success
    function withdrawAll() external returns (bool);

    /// @notice Minimum token amount required to be locked
    /// @param timestamp date to check
    function getLockedAt(uint256 timestamp) external view returns (uint256);

    /// @notice Minimum token amount required to be locked
    function getLocked() external view returns (uint256);

    /// @notice Token amount available for withdrawal
    function getAvailable() external view returns (uint256);

    /// @notice Returns true after contract has been verified by holder
    function isVerified() external view returns (bool);

    /// @notice Total token balance configured
    function getTotal() external view returns (uint256);

    /// @notice Update vesting parameters (only can be called by factory)
    /// @param _percentages array of token percentages locked at a date
    /// @param _timedeltas array of date deltas from TGE when percentages are valid
    // function update(uint256[] memory _percentages, uint256[] memory _timedeltas) external;

    /// @notice Change holder address
    /// @param newHolder the new holder (only can be called by governance)
    function setHolder(address newHolder) external;

    /// @notice Configure vesting total balance (only can be called by factory)
    function setTotal(uint256 amount) external;
}
