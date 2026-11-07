// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {IRegistrar} from "contracts/globalMarkets/tokenFactory/registrars/IRegistrar.sol";

/**
 * @title  TokenManagerRegistrarStub
 * @author Ondo Finance
 * @notice Placeholder implementation of a token manager registrar for chains that do not yet have a fully implemented token manager.
 */
contract TokenManagerRegistrarStub is IRegistrar {
  /**
   * @notice Registers a token address.
   * @param  token The address of the token to register.
   */
  function register(address token) external override {
    // Stubbed out, will be upgraded once GMTokenManager is live.
  }
}
