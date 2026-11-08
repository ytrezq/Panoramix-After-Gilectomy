// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {IRegistrar} from "contracts/globalMarkets/tokenFactory/registrars/IRegistrar.sol";

/**
 * @title  BridgeRegistrarStub
 * @author Ondo Finance
 * @notice Placeholder implementation of a bridge registrar meant to be fleshed out in a future release.
 */
contract BridgeRegistrarStub is IRegistrar {
  /**
   * @notice Registers a token address.
   * @param  token The address of the token to register.
   */
  function register(address token) external override {
    // Stubbed out, will be implemented in a future release.
  }
}
