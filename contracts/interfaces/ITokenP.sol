// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ITokenP
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Interface for the stablecoins `tokenP` contracts
/// @dev This interface is an authorized fork of Angle's `IAgToken` interface
/// https://github.com/AngleProtocol/angle-transmuter/blob/main/contracts/interfaces/IAgToken.sol
interface ITokenP is IERC20 {
  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    MINTER ROLE ONLY FUNCTIONS                                            
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Lets a whitelisted contract mint tokenPs
  /// @param account Address to mint to
  /// @param amount Amount to mint
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
  /// @dev This method is to be called by a contract with a minter right on the tokenP after being
  /// requested to do so by an address willing to burn tokens from its address
  function burnSelf(uint256 amount, address burner) external;

  /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    EXTERNAL FUNCTIONS                                                
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

  /// @notice Amount of decimals of the stablecoin
  function decimals() external view returns (uint8);
}
