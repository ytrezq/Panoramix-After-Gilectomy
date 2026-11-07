// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {
    IConcreteFactory,
    ConcreteFactoryBaseSetup,
    VaultProxy,
    IConcreteStandardVaultImpl,
    ConcreteStandardVaultImpl,
    TestBaseSetup
} from "./TestBaseSetup.t.sol";
import {ConcretePredepositVaultImpl} from "../../src/implementation/ConcretePredepositVaultImpl.sol";
import {IConcretePredepositVaultImpl} from "../../src/interface/IConcretePredepositVaultImpl.sol";
import {PredepostVaultOApp} from "../../src/periphery/predeposit/PredepostVaultOApp.sol";
import {ERC20Mock} from "../mock/ERC20Mock.sol";
import {AllocateModule} from "../../src/module/AllocateModule.sol";
import {ConcreteV2RolesLib as RolesLib} from "../../src/lib/Roles.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {ShareDistributorMock} from "../mock/ShareDistributorMock.sol";
import {ConcreteStandardVaultImpl} from "../../src/implementation/ConcreteStandardVaultImpl.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ConcretePredepositVaultImplBaseSetup is TestBaseSetup, TestHelperOz5 {
    uint32 public aEid = 1;
    uint32 public bEid = 2;

    address public vaultOwner;
    address public vaultManager;
    address public hookManager;
    address public strategyOperator;
    address public allocator;

    ERC20Mock public asset;
    AllocateModule public allocateModule;
    ConcretePredepositVaultImpl public predepositVault; // Predeposit vault on chain A (source)
    PredepostVaultOApp public predepositVaultOApp; // OApp for predeposit vault
    ConcreteStandardVaultImpl public destinationVault; // Standard vault on chain B (destination)
    ShareDistributorMock public distributor; // Distributor on chain B

    function setUp() public virtual override(TestBaseSetup, TestHelperOz5) {
        TestBaseSetup.setUp();
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        _setupAddresses();
        _deployContracts();
        _setupLabels();
        _configureConnections();
        _setupRoles();
        _fundDistributor();
    }

    function _setupAddresses() private {
        vaultOwner = makeAddr("vaultOwner");
        vaultManager = makeAddr("vaultManager");
        hookManager = makeAddr("hookManager");
        strategyOperator = makeAddr("strategyOperator");
        allocator = makeAddr("allocator");
    }

    function _deployContracts() private {
        asset = new ERC20Mock();
        allocateModule = new AllocateModule();

        // Deploy and approve predeposit vault implementation
        vm.startPrank(factoryOwner);
        factory.approveImplementation(address(new ConcretePredepositVaultImpl(address(factory))));
        vm.stopPrank();

        // Deploy vault on chain A
        predepositVault = ConcretePredepositVaultImpl(
            factory.create(
                2,
                vaultOwner,
                abi.encode(address(allocateModule), address(asset), vaultManager, "Concrete Predeposit Vault A", "CPVA")
            )
        );

        // Deploy OApp
        predepositVaultOApp = PredepostVaultOApp(
            address(
                new ERC1967Proxy(
                    address(new PredepostVaultOApp(address(endpoints[aEid]))),
                    abi.encodeCall(PredepostVaultOApp.initialize, (address(predepositVault), vaultOwner))
                )
            )
        );

        // Deploy vault on chain B
        destinationVault = ConcreteStandardVaultImpl(
            factory.create(
                1,
                vaultOwner,
                abi.encode(address(allocateModule), address(asset), vaultManager, "Concrete Standard Vault B", "CSVB")
            )
        );

        // Deploy distributor on chain B
        distributor = new ShareDistributorMock(address(endpoints[bEid]), address(destinationVault), vaultManager);
    }

    function _setupLabels() private {
        vm.label(address(allocateModule), "allocateModule");
        vm.label(address(predepositVault), "predepositVault");
        vm.label(address(predepositVaultOApp), "predepositVaultOApp");
        vm.label(address(destinationVault), "destinationVault");
        vm.label(address(distributor), "distributor");
        vm.label(address(asset), "asset");
        vm.label(address(endpoints[aEid]), "lzEndpointA");
        vm.label(address(endpoints[bEid]), "lzEndpointB");
    }

    function _configureConnections() private {
        vm.startPrank(vaultManager);
        predepositVault.setOApp(address(predepositVaultOApp));
        predepositVault.setSelfClaimsEnabled(true); // Enable self claims by default for tests
        vm.stopPrank();

        vm.startPrank(vaultOwner);
        predepositVaultOApp.setDstEid(bEid);
        predepositVaultOApp.setPeer(bEid, addressToBytes32(address(distributor)));
        vm.stopPrank();

        vm.prank(vaultManager);
        distributor.setPeer(aEid, addressToBytes32(address(predepositVaultOApp)));
    }

    function _setupRoles() private {
        vm.startPrank(vaultManager);
        predepositVault.grantRole(RolesLib.STRATEGY_MANAGER, strategyOperator);
        predepositVault.grantRole(RolesLib.ALLOCATOR, allocator);
        predepositVault.grantRole(RolesLib.HOOK_MANAGER, hookManager);
        vm.stopPrank();

        vm.startPrank(vaultManager);
        destinationVault.grantRole(RolesLib.STRATEGY_MANAGER, strategyOperator);
        destinationVault.grantRole(RolesLib.ALLOCATOR, allocator);
        destinationVault.grantRole(RolesLib.HOOK_MANAGER, hookManager);
        vm.stopPrank();
    }

    function _fundDistributor() private {
        asset.mint(address(distributor), 1000000e18);
        vm.startPrank(address(distributor));
        asset.approve(address(destinationVault), 1000000e18);
        destinationVault.deposit(1000000e18, address(distributor));
        vm.stopPrank();
    }
}
