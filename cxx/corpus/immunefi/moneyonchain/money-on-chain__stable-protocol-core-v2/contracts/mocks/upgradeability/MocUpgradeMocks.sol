// SPDX-License-Identifier: UNLICENSED
// solhint-disable one-contract-per-file
pragma solidity 0.8.24;

// This contract is not intended to be used in a production system
// It was designed to be used in a testing environment only

// solhint-disable-next-line max-line-length
import { UUPSUpgradeable, UpgraderUUPSChangerTemplate } from "../../governance/changerTemplates/UpgraderUUPSChangerTemplate.sol";
import { MocCACoinbase } from "../../collateral/coinbase/MocCACoinbase.sol";
import { MocCARC20 } from "../../collateral/rc20/MocCARC20.sol";
import { MocMultiCollateralGuard } from "../../multiCollateral/MocMultiCollateralGuard.sol";

/**
 * @title UpgradableMock
 * @dev Only for upgradeability testing purposes. Generic contract for initialize a mock and get a custom method.
 */
/// @custom:oz-upgrades-unsafe-allow missing-initializer
abstract contract UpgradableMock {
    uint256 public newVariable;

    function initializeMock() external {
        newVariable = 42;
    }

    function getCustomMockValue() external view virtual returns (uint256);
}

/**
 * @title MocCoinbaseMock
 * @dev Only for upgradeability testing purposes. Extends MocCACoinbase adding a new variable.
 */
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract MocCoinbaseMock is MocCACoinbase, UpgradableMock {
    function getCustomMockValue() external view override returns (uint256) {
        return newVariable + (protThrld / PRECISION);
    }
}

/**
 * @title MocCARC20Mock
 * @dev Only for upgradeability testing purposes. Extends MocCARC20 adding a new variable.
 */
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract MocCARC20Mock is MocCARC20, UpgradableMock {
    function getCustomMockValue() external view override returns (uint256) {
        return newVariable + (protThrld / PRECISION);
    }
}

/**
 * @title MocMultiCollateralGuardMock
 * @dev Only for upgradeability testing purposes. Extends MocMultiCollateralGuard adding a new variable.
 */
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract MocMultiCollateralGuardMock is MocMultiCollateralGuard, UpgradableMock {
    function getCustomMockValue() external view override returns (uint256) {
        return newVariable + maxOperPerBatch;
    }
}

/**
 * @title MocUpgradeChangerMock
 * @dev Only for upgradeability testing purposes. Extends UpgraderUUPSTemplate so that it
 * can upgrade, via UUPS, the original Moc compatible implementation
 */
contract MocUpgradeChangerMock is UpgraderUUPSChangerTemplate {
    constructor(
        UUPSUpgradeable _proxy,
        UpgradableMock _newImplementation
    ) UpgraderUUPSChangerTemplate(_proxy, address(_newImplementation)) {}

    function _beforeUpgrade() internal override {}

    function _afterUpgrade() internal override {
        UpgradableMock upgradedProxy = UpgradableMock(address(PROXY));
        upgradedProxy.initializeMock();
    }
}
