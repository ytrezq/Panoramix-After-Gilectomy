// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ConcreteStandardVaultImplTest} from "./common/concrete-tests/ConcreteStandardVaultImpl.test.sol";
import {ERC4626Test} from "./common/a16z-erc4626-tests/ERC4626.test.sol";
import {ConcreteStandardVaultImplBaseSetup} from "../common/ConcreteStandardVaultImplBaseSetup.t.sol";

contract A16zPropertyTestsConcreteStandardVaultImpl is
    ConcreteStandardVaultImplTest,
    ConcreteStandardVaultImplBaseSetup
{
    function setUp() public override(ERC4626Test, ConcreteStandardVaultImplBaseSetup) {
        ConcreteStandardVaultImplBaseSetup.setUp();

        _underlying_ = address(asset);
        _vault_ = address(concreteStandardVault);
        _delta_ = 2;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;
    }

    function _getAllocator() internal view override returns (address) {
        return allocator;
    }

    function _getStrategyOperator() internal view override returns (address) {
        return strategyOperator;
    }
}
