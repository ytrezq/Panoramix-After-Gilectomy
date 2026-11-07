// SPDX-License-Identifier: UNLICENSED
// solhint-disable one-contract-per-file
pragma solidity 0.8.24;

// solhint-disable-next-line max-line-length
import { UUPSUpgradeable, UpgraderUUPSChangerTemplate } from "../../governance/changerTemplates/UpgraderUUPSChangerTemplate.sol";
import { MocCore, MocCommons, MocCoreExpansion, Address } from "../../core/MocCore.sol";
import { MocCACoinbase } from "../../collateral/coinbase/MocCACoinbase.sol";
import { MocCARC20 } from "../../collateral/rc20/MocCARC20.sol";

/**
 * @title UpgradableMock
 * @dev Only for upgradeability testing purposes. Generic contract for initialize a mock and get a custom method.
 *  It is used to test that we can add storage variables to MocCommons and
 *  MocCore keeps the compatibility with MocCoreExpansion.
 */

abstract contract UpgradableMock is MocCommons {
    uint256 public newVariable;

    function initializeMock() external {
        newVariable = 52;
    }

    function getCustomMockValue() external view returns (uint256) {
        return newVariable + (protThrld / PRECISION);
    }

    function getExpansionCustomMockValue() external virtual returns (uint256);
}

contract MocCoreExpansionMock is UpgradableMock, MocCoreExpansion {
    function getExpansionCustomMockValue() external view override returns (uint256) {
        return newVariable;
    }
}

/**
 * @title MocCoinbaseWithExpansionMock
 * @dev Only for upgradeability testing purposes. Extends MocCACoinbase adding a new variable.
 */
contract MocCoinbaseWithExpansionMock is UpgradableMock, MocCACoinbase {
    function getExpansionCustomMockValue() external override returns (uint256) {
        bytes memory payload = abi.encodeCall(MocCoreExpansionMock(mocCoreExpansion).getExpansionCustomMockValue, ());
        uint256 newVariable_ = abi.decode(Address.functionDelegateCall(mocCoreExpansion, payload), (uint256));
        return newVariable_ + (protThrld / PRECISION);
    }
}

/**
 * @title MocCARC20WithExpansionMock
 * @dev Only for upgradeability testing purposes. Extends MocCARC20Mock adding a new variable.
 */
contract MocCARC20WithExpansionMock is UpgradableMock, MocCARC20 {
    function getExpansionCustomMockValue() external override returns (uint256) {
        bytes memory payload = abi.encodeCall(MocCoreExpansionMock(mocCoreExpansion).getExpansionCustomMockValue, ());
        uint256 newVariable_ = abi.decode(Address.functionDelegateCall(mocCoreExpansion, payload), (uint256));
        return newVariable_ + (protThrld / PRECISION);
    }
}

/**
 * @title MocUpgradeChangerWithExpansionMock
 * @dev Only for upgradeability testing purposes. Extends UpgraderUUPSTemplate so that it
 * can upgrade, via UUPS, the original Moc CA implementation and set a new MocCoreExpansion
 */
contract MocUpgradeChangerWithExpansionMock is UpgraderUUPSChangerTemplate {
    address private newMocCoreExpansion;

    constructor(
        UUPSUpgradeable _proxy,
        UpgradableMock _newImplementation,
        address _newMocCoreExpansion
    ) UpgraderUUPSChangerTemplate(_proxy, address(_newImplementation)) {
        newMocCoreExpansion = _newMocCoreExpansion;
    }

    function _beforeUpgrade() internal override {}

    function _afterUpgrade() internal override {
        UpgradableMock upgradedProxy = UpgradableMock(address(PROXY));
        upgradedProxy.initializeMock();
        MocCore(address(PROXY)).setMocCoreExpansion(newMocCoreExpansion);
    }
}
