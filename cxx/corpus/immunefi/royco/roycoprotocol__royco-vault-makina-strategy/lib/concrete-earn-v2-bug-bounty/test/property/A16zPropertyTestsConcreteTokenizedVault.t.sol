// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC4626Test} from "./common/a16z-erc4626-tests/ERC4626.test.sol";
import {ERC20Mock} from "../mock/ERC20Mock.sol";
import {ConcreteFactoryBaseSetup} from "../common/ConcreteFactoryBaseSetup.t.sol";
import {UpgradeableVault} from "../../src/common/UpgradeableVault.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract ERC4626Vault is UpgradeableVault, ERC4626Upgradeable {
    constructor(address factory) UpgradeableVault(factory) {}

    function _initialize(uint64, address, bytes memory data) internal virtual override {
        (address asset, string memory name, string memory symbol) = abi.decode(data, (address, string, string));

        __ERC20_init_unchained(name, symbol);
        __ERC4626_init_unchained(IERC20(asset));
    }
}

contract A16zPropertyTestsConcreteTokenizedVault is ERC4626Test, ConcreteFactoryBaseSetup {
    function setUp() public override(ERC4626Test, ConcreteFactoryBaseSetup) {
        ConcreteFactoryBaseSetup.setUp();

        _underlying_ = address(new ERC20Mock());

        /// deploying the vault implementation, approving it in `factory` and deploying the proxy
        address erc4626VaultImpl = address(new ERC4626Vault(address(factory)));
        vm.prank(factoryOwner);
        factory.approveImplementation(erc4626VaultImpl);

        _vault_ = factory.create(
            1, factoryOwner, abi.encode(_underlying_, "Concrete Tokenized Vault", "ConcreteTokenizedVault")
        );
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;
    }
}
