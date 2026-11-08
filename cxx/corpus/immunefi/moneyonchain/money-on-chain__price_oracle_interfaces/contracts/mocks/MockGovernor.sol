// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @dev Minimal governor mock for tests.
 * Adapts to common Governed patterns by exposing a few typical selectors.
 * Tweak the function names if your Governed expects a different one.
 */
contract MockGovernor {
  mapping(address => bool) public authorized;

  function setAuthorized(address changer, bool isAuth) external {
    authorized[changer] = isAuth;
  }

  // Most common pattern
  function isAuthorizedChanger(address changer) external view returns (bool) {
    return authorized[changer];
  }

  // Alternative names some Governed variants use
  function isAuthorized(address changer) external view returns (bool) {
    return authorized[changer];
  }
}
