// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

/// @notice Technical struct used to pass parameters in the `updateInstantWithdrawalFuses` function
struct InstantWithdrawalFusesParamsStruct {
    /// @notice The address of the fuse
    address fuse;
    /// @notice The parameters of the fuse, first element is an amount, second element is an address of the asset or a market id or other substrate specific for the fuse
    /// @dev Notice! Always first param is the asset value in underlying, next params are specific for the Fuse
    bytes32[] params;
}

interface IPlasmaVault {
    function addFuses(address[] memory fuses_) external;
    function addBalanceFuse(uint256 marketId_, address fuse_) external;
    function grantMarketSubstrates(uint256 marketId_, bytes32[] memory substrates_) external;
    function configureInstantWithdrawalFuses(InstantWithdrawalFusesParamsStruct[] calldata fuses_) external;
}