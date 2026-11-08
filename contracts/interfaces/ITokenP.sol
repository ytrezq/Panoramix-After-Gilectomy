// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IEIP3009} from "contracts/interfaces/external/IEIP3009.sol";

/// @title ITokenP
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Interface for the stablecoins `TokenP` contracts
/// @dev This interface only contains functions of the `TokenP` contract which are called by other contracts.
interface ITokenP is IERC20, IERC20Permit, IEIP3009 {
    /// @notice Allow whitelisted contract to mint TokenP
    /// @param account Address to mint to
    /// @param amount Amount to mint
    /// @dev The contracts allowed to issue TokenP  contracts
    /// associated to this stablecoin as well as the flash loan module (if activated) and potentially contracts
    /// whitelisted by governance
    function mint(address account, uint256 amount) external;

    /// @notice Burns `amount` tokens from a `burner` address after being asked to by `sender`
    /// @param amount Amount of tokens to burn
    /// @param burner Address to burn from
    /// @param sender Address which requested the burn from `burner`
    /// @dev This method is to be called by a contract with the minter right after being requested
    /// to do so by a `sender` address willing to burn tokens from another `burner` address
    /// @dev The method checks the allowance between the `sender` and the `burner`
    function burnFrom(uint256 amount, address burner, address sender) external;

    /// @notice Burns `amount` tokens from a `burner` address
    /// @param amount Amount of tokens to burn
    /// @param burner Address to burn from
    /// @dev This method is to be called by a contract with a minter right on the AgToken after being
    /// requested to do so by an address willing to burn tokens from its address
    function burnSelf(uint256 amount, address burner) external;

    /// @notice Allows anyone to burn stablecoins
    /// @param amount Amount of stablecoins to burn
    /// @dev This function can typically be called if there is a settlement mechanism to burn stablecoins
    function burnStablecoin(uint256 amount) external;

}
