// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IChangeContract } from "../../interfaces/IChangeContract.sol";

interface IUUPSLike {
  function upgradeTo(address newImplementation) external;
  // opcional: function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/**
  @title UpgraderUUPSChangerTemplate
  @notice Changer base para upgrades UUPS vía el sistema de gobernanza MoC.
  No inicializa el implementation nuevo; extendé _afterUpgrade() si necesitás init.
*/
abstract contract UpgraderUUPSChangerTemplate is IChangeContract {
  address public immutable PROXY;
  address public immutable NEW_IMPLEMENTATION;

  /**
   * @param proxy_ Dirección del proxy UUPS a actualizar
   * @param newImplementation_ Nueva implementación
   */
  constructor(address proxy_, address newImplementation_) {
    PROXY = proxy_;
    NEW_IMPLEMENTATION = newImplementation_;
  }

  /// Ejecuta el cambio (plantilla final)
  function execute() external {
    _beforeUpgrade();
    _upgrade();
    _afterUpgrade();
  }

  /// Realiza el upgrade (no sobreescribir)
  function _upgrade() internal {
    IUUPSLike(PROXY).upgradeTo(NEW_IMPLEMENTATION);
    // para upgrade + init en una sola tx:
    // IUUPSLike(PROXY).upgradeToAndCall(NEW_IMPLEMENTATION, abi.encodeWithSignature("initialize(...)"));
  }

  /// Hook opcional antes del upgrade
  function _beforeUpgrade() internal virtual;

  /// Hook opcional después del upgrade (p.ej., initialize)
  function _afterUpgrade() internal virtual;
}
