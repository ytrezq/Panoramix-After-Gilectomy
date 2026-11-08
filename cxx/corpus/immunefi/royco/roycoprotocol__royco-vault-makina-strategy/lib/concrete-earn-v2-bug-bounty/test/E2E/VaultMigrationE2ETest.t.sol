// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ConcreteStandardVaultImpl} from "../../src/implementation/ConcreteStandardVaultImpl.sol";
import {AllocateModule} from "../../src/module/AllocateModule.sol";
import {ConcreteFactoryBaseSetup} from "../common/ConcreteFactoryBaseSetup.t.sol";

contract ConcreteStandardVaultImpl2 is ConcreteStandardVaultImpl {
    constructor(address factory) ConcreteStandardVaultImpl(factory) {}

    function _upgrade(
        uint64,
        /* oldVersion */
        uint64,
        /* newVersion */
        bytes calldata /* data */
    )
        internal
        virtual
        override(ConcreteStandardVaultImpl)
    {
        // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))
        bytes32 ERC20StorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;
        ERC20Upgradeable.ERC20Storage storage $;
        assembly {
            $.slot := ERC20StorageLocation
        }

        $._name = "Concrete Standard Vault 2";
        $._symbol = "ConcreteStandardVault2";
    }
}

contract VaultMigrationE2ETest is ConcreteFactoryBaseSetup {
    address public vaultProxyOwner;

    address asset;

    address concreteStandardVaultImpl;
    address concreteStandardVaultImpl2;

    address vaultProxy;

    AllocateModule public allocateModule;

    function setUp() public virtual override {
        asset = makeAddr("asset");

        ConcreteFactoryBaseSetup.setUp();

        vaultProxyOwner = makeAddr("vaultProxyOwner");
        allocateModule = new AllocateModule();

        /// deploying the `ConcreteStandardVaultImpl` implementation, approving it in `factory` and deploying the proxy
        concreteStandardVaultImpl = address(new ConcreteStandardVaultImpl(address(factory)));
        vm.prank(factoryOwner);
        factory.approveImplementation(concreteStandardVaultImpl);

        /// deploying the `ConcreteStandardVaultImpl` implementation, approving it in `factory` and deploying the proxy
        concreteStandardVaultImpl2 = address(new ConcreteStandardVaultImpl2(address(factory)));
        vm.prank(factoryOwner);
        factory.approveImplementation(concreteStandardVaultImpl2);
    }

    function testDeployProxyWithStandardImplAndMigrateToCAnotherImpl() public {
        // deploy proxy with version==1 (ConcreteStandardVaultImpl)

        vaultProxy = address(
            factory.create(
                1,
                vaultProxyOwner,
                abi.encode(
                    address(allocateModule), asset, vaultProxyOwner, "Concrete Standard Vault", "ConcreteStandardVault"
                )
            )
        );

        assertEq(ConcreteStandardVaultImpl(vaultProxy).name(), "Concrete Standard Vault");
        assertEq(ConcreteStandardVaultImpl(vaultProxy).symbol(), "ConcreteStandardVault");

        vm.prank(factoryOwner);
        factory.setMigratable(1, 2);

        // migrate to version==2 (ConcreteCappedVaultImpl)
        vm.prank(vaultProxyOwner);
        factory.upgrade(vaultProxy, 2, abi.encode("Concrete Standard Vault 2", "ConcreteStandardVault2"));

        assertEq(ConcreteStandardVaultImpl(vaultProxy).name(), "Concrete Standard Vault 2");
        assertEq(ConcreteStandardVaultImpl(vaultProxy).symbol(), "ConcreteStandardVault2");
    }
}
