// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Interface for RestrictedToken contract
/// @author Simon Mall
/// @notice Used for esGS, esGSb and bnGS
interface IRestrictedToken is IERC20 {
  enum TokenType { ESCROW, BONUS }

  function tokenType() external view returns (TokenType);

  /// @param _user Address for query
  /// @return Check if an address is manager
  function isManager(address _user) external returns (bool);

  /// @notice Only admin is allowed to do this
  /// @dev Set manager permission
  /// @param _user Address to set permission to
  /// @param _isActive True - enable, False - disable
  function setManager(address _user, bool _isActive) external;

  /// @param _user Address for query
  /// @return Check if an address is handler
  function isHandler(address _user) external returns (bool);

  /// @notice Only admin or managers are allowed to do this
  /// @dev Set handler permission
  /// @param _user Address to set permission to
  /// @param _isActive True - enable, False - disable
  function setHandler(address _user, bool _isActive) external;

  /// @notice Only admin or managers or handlers are allowed to do this
  /// @dev Mint tokens
  /// @param _account Address to mint to
  /// @param _amount Amount of tokens to mint
  function mint(address _account, uint256 _amount) external;

  /// @notice Only admin or managers or handlers are allowed to do this
  /// @dev Burn tokens
  /// @param _account Address to burn from
  /// @param _amount Amount of tokens to burn
  function burn(address _account, uint256 _amount) external;
}