// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {BytecodeRepository} from "../../global/BytecodeRepository.sol";
import {ProxyCall} from "../../helpers/ProxyCall.sol";
import {InstanceManager} from "../../instance/InstanceManager.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {IInstanceManager} from "../../interfaces/IInstanceManager.sol";
import {
    AP_ADDRESS_PROVIDER,
    AP_BYTECODE_REPOSITORY,
    AP_CROSS_CHAIN_GOVERNANCE,
    AP_CROSS_CHAIN_GOVERNANCE_PROXY,
    AP_GEAR_STAKING,
    AP_GEAR_TOKEN,
    AP_INSTANCE_MANAGER,
    AP_INSTANCE_MANAGER_PROXY,
    AP_TREASURY,
    AP_TREASURY_PROXY,
    AP_WETH_TOKEN,
    NO_VERSION_CONTROL
} from "../../libraries/ContractLiterals.sol";

contract InstanceManagerTest is Test {
    InstanceManager public manager;
    address public owner;
    address public crossChainGovernance;
    address public treasury;
    address public weth;
    address public gear;
    IAddressProvider public addressProvider;

    function setUp() public {
        owner = makeAddr("owner");
        crossChainGovernance = makeAddr("crossChainGovernance");
        treasury = makeAddr("treasury");
        weth = makeAddr("weth");
        gear = makeAddr("gear");

        // Deploy with cross-chain governance as initial owner
        manager = new InstanceManager(crossChainGovernance);
        addressProvider = IAddressProvider(manager.addressProvider());

        // Activate instance and transfer ownership to instance owner
        vm.prank(crossChainGovernance);
        manager.activate(owner, treasury, weth, gear);
    }

    /// @notice Test constructor sets up initial state correctly
    function test_U_IM_01_constructor_sets_initial_state() public {
        // Create new non-activated instance
        InstanceManager newManager = new InstanceManager(crossChainGovernance);
        IAddressProvider newAddressProvider = IAddressProvider(newManager.addressProvider());

        // Verify proxies were created
        assertTrue(newManager.instanceManagerProxy() != address(0));
        assertTrue(newManager.treasuryProxy() != address(0));
        assertTrue(newManager.crossChainGovernanceProxy() != address(0));

        // Verify initial addresses were set
        assertEq(
            newAddressProvider.getAddressOrRevert(AP_BYTECODE_REPOSITORY, NO_VERSION_CONTROL),
            newManager.bytecodeRepository()
        );
        assertEq(
            newAddressProvider.getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE, NO_VERSION_CONTROL), crossChainGovernance
        );
        assertEq(
            newAddressProvider.getAddressOrRevert(AP_INSTANCE_MANAGER_PROXY, NO_VERSION_CONTROL),
            newManager.instanceManagerProxy()
        );
        assertEq(
            newAddressProvider.getAddressOrRevert(AP_TREASURY_PROXY, NO_VERSION_CONTROL), newManager.treasuryProxy()
        );
        assertEq(
            newAddressProvider.getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE_PROXY, NO_VERSION_CONTROL),
            newManager.crossChainGovernanceProxy()
        );
        assertEq(newAddressProvider.getAddressOrRevert(AP_INSTANCE_MANAGER, NO_VERSION_CONTROL), address(newManager));

        // Verify ownership
        assertEq(newManager.owner(), crossChainGovernance);

        // Verify not activated
        assertFalse(newManager.isActivated());
    }

    /// @notice Test activation functionality
    function test_U_IM_02_activate_works() public {
        // Create new non-activated instance
        InstanceManager newManager = new InstanceManager(crossChainGovernance);
        IAddressProvider newAddressProvider = IAddressProvider(newManager.addressProvider());

        // Test it reverts if not governance
        vm.prank(makeAddr("notGovernance"));
        vm.expectRevert("Ownable: caller is not the owner");
        newManager.activate(owner, treasury, weth, gear);

        // Test successful activation
        vm.prank(crossChainGovernance);
        newManager.activate(owner, treasury, weth, gear);

        assertTrue(newManager.isActivated());
        assertEq(newManager.owner(), owner);
        assertEq(newAddressProvider.getAddressOrRevert(AP_INSTANCE_MANAGER, NO_VERSION_CONTROL), address(newManager));
        assertEq(newAddressProvider.getAddressOrRevert(AP_TREASURY, NO_VERSION_CONTROL), treasury);
        assertEq(newAddressProvider.getAddressOrRevert(AP_WETH_TOKEN, NO_VERSION_CONTROL), weth);
        assertEq(newAddressProvider.getAddressOrRevert(AP_GEAR_TOKEN, NO_VERSION_CONTROL), gear);

        // Test it can't be activated twice
        address newTreasury = makeAddr("newTreasury");
        vm.prank(owner);
        newManager.activate(owner, newTreasury, weth, gear);
        assertEq(newAddressProvider.getAddressOrRevert(AP_TREASURY, NO_VERSION_CONTROL), treasury);

        // Test successful activation without GEAR
        newManager = new InstanceManager(crossChainGovernance);
        vm.prank(crossChainGovernance);
        newManager.activate(owner, treasury, weth, address(0));
    }

    /// @notice Test address setting functionality
    function test_U_IM_03_setAddress_functions_work() public {
        bytes32 globalKey = "GLOBAL::TEST";
        bytes32 localKey = "LOCAL::TEST";
        address testAddr = makeAddr("testAddr");

        // Test setGlobalAddress
        // Test it reverts if not governance
        address notGovernance = makeAddr("notGovernance");
        vm.prank(notGovernance);
        vm.expectRevert(
            abi.encodeWithSelector(IInstanceManager.CallerIsNotCrossChainGovernanceException.selector, notGovernance)
        );
        manager.setGlobalAddress(globalKey, testAddr, false);

        // Test it reverts if key doesn't have correct prefix
        vm.prank(crossChainGovernance);
        vm.expectRevert(abi.encodeWithSelector(IInstanceManager.InvalidKeyException.selector, bytes32("INVALID")));
        manager.setGlobalAddress("INVALID", testAddr, false);

        // Test successful global address setting
        vm.prank(crossChainGovernance);
        manager.setGlobalAddress(globalKey, testAddr, false);
        assertEq(addressProvider.getAddressOrRevert(globalKey, NO_VERSION_CONTROL), testAddr);

        // Test setLocalAddress
        // Test it reverts if not governance
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        manager.setLocalAddress(localKey, testAddr, false);

        // Test it reverts if key doesn't have correct prefix
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IInstanceManager.InvalidKeyException.selector, bytes32("INVALID")));
        manager.setLocalAddress("INVALID", testAddr, false);

        // Test successful local address setting
        vm.prank(owner);
        manager.setLocalAddress(localKey, testAddr, false);
        assertEq(addressProvider.getAddressOrRevert(localKey, NO_VERSION_CONTROL), testAddr);
    }

    /// @notice Test configuration functionality
    function test_U_IM_04_configure_functions_work() public {
        address target = makeAddr("target");
        bytes memory data = "test";
        vm.mockCall(target, data, "");

        // Test configureGlobal
        // Test it reverts if not governance
        address notGovernance = makeAddr("notGovernance");
        vm.expectRevert(
            abi.encodeWithSelector(IInstanceManager.CallerIsNotCrossChainGovernanceException.selector, notGovernance)
        );
        vm.prank(notGovernance);
        manager.configureGlobal(target, data);

        // Test successful global configuration
        vm.expectCall(manager.crossChainGovernanceProxy(), abi.encodeCall(ProxyCall.proxyCall, (target, data)));
        vm.prank(crossChainGovernance);
        manager.configureGlobal(target, data);

        // Test configureLocal
        // Test it reverts if not governance
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        manager.configureLocal(target, data);

        // Test successful local configuration
        vm.expectCall(manager.instanceManagerProxy(), abi.encodeCall(ProxyCall.proxyCall, (target, data)));
        vm.prank(owner);
        manager.configureLocal(target, data);

        // Test configureTreasury
        // Test it reverts if not treasury
        address notTreasury = makeAddr("notTreasury");
        vm.expectRevert(abi.encodeWithSelector(IInstanceManager.CallerIsNotTreasuryException.selector, notTreasury));
        vm.prank(notTreasury);
        manager.configureTreasury(target, data);

        // Test successful treasury configuration
        vm.expectCall(manager.treasuryProxy(), abi.encodeCall(ProxyCall.proxyCall, (target, data)));
        vm.prank(treasury);
        manager.configureTreasury(target, data);
    }

    /// @notice Test governance transfer works
    function test_U_IM_05_governance_transfer_works() public {
        address newGovernance = makeAddr("newGovernance");

        // Test only current governance can set pending
        vm.prank(makeAddr("notGovernance"));
        vm.expectRevert(
            abi.encodeWithSelector(
                IInstanceManager.CallerIsNotCrossChainGovernanceException.selector, makeAddr("notGovernance")
            )
        );
        manager.setPendingGovernance(newGovernance);

        // Test setting pending governance
        vm.prank(crossChainGovernance);
        vm.expectEmit(true, false, false, true);
        emit IInstanceManager.SetPendingGovernance(newGovernance);
        manager.setPendingGovernance(newGovernance);
        assertEq(manager.pendingGovernance(), newGovernance);

        // Test only pending governance can accept
        vm.prank(makeAddr("notPending"));
        vm.expectRevert(
            abi.encodeWithSelector(
                IInstanceManager.CallerIsNotPendingGovernanceException.selector, makeAddr("notPending")
            )
        );
        manager.acceptGovernance();

        // Test accepting governance
        vm.prank(newGovernance);
        vm.expectEmit(true, false, false, true);
        emit IInstanceManager.AcceptGovernance(newGovernance);
        manager.acceptGovernance();

        assertEq(manager.pendingGovernance(), address(0));
        assertEq(addressProvider.getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE, NO_VERSION_CONTROL), newGovernance);
    }

    /// @notice Test system contract deployment
    function test_U_IM_06_deploy_system_contract() public {
        bytes32 contractType = "TYPE::TEST";
        uint256 version = 3_10;
        address newContract = makeAddr("newContract");

        // Test it reverts if not governance
        vm.prank(makeAddr("notGovernance"));
        vm.expectRevert(
            abi.encodeWithSelector(
                IInstanceManager.CallerIsNotCrossChainGovernanceException.selector, makeAddr("notGovernance")
            )
        );
        manager.deploySystemContract(contractType, version, false);

        // Mock successful deployment
        vm.mockCall(
            address(manager.bytecodeRepository()),
            abi.encodeCall(
                BytecodeRepository.deploy, (contractType, version, abi.encode(manager.addressProvider()), bytes32(0))
            ),
            abi.encode(newContract)
        );

        // Test successful deployment
        vm.prank(crossChainGovernance);
        manager.deploySystemContract(contractType, version, false);
        assertEq(addressProvider.getAddressOrRevert(contractType, NO_VERSION_CONTROL), newContract);

        // Test deployment with version saving
        address newVersionedContract = makeAddr("newVersionedContract");
        vm.mockCall(newVersionedContract, abi.encodeWithSignature("version()"), abi.encode(version));
        vm.mockCall(
            address(manager.bytecodeRepository()),
            abi.encodeCall(
                BytecodeRepository.deploy, (contractType, version, abi.encode(manager.addressProvider()), bytes32(0))
            ),
            abi.encode(newVersionedContract)
        );

        vm.prank(crossChainGovernance);
        manager.deploySystemContract(contractType, version, true);
        assertEq(addressProvider.getAddressOrRevert(contractType, version), newVersionedContract);

        // Test deployment failure
        vm.mockCallRevert(
            address(manager.bytecodeRepository()),
            abi.encodeCall(
                BytecodeRepository.deploy, (contractType, version, abi.encode(manager.addressProvider()), bytes32(0))
            ),
            "DEPLOYMENT_FAILED"
        );

        vm.expectRevert("DEPLOYMENT_FAILED");
        vm.prank(crossChainGovernance);
        manager.deploySystemContract(contractType, version, false);
    }

    /// @notice Test legacy GEAR staking deployment
    function test_U_IM_07_deploy_legacy_gear_staking() public {
        // Test on legacy chains
        uint256[] memory legacyChains = new uint256[](4);
        legacyChains[0] = 1; // Mainnet
        legacyChains[1] = 10; // Optimism
        legacyChains[2] = 146; // Sonic
        legacyChains[3] = 42161; // Arbitrum

        address[] memory expectedAddresses = new address[](4);
        expectedAddresses[0] = 0x2fcbD02d5B1D52FC78d4c02890D7f4f47a459c33;
        expectedAddresses[1] = 0x8D2622f1CA3B42b637e2ff6753E6b69D3ab9Adfd;
        expectedAddresses[2] = 0xe88846b6C85AA67688e453c7eaeeeb40F51e1F0a;
        expectedAddresses[3] = 0xf3599BEfe8E79169Afd5f0b7eb0A1aA322F193D9;

        for (uint256 i = 0; i < legacyChains.length; i++) {
            vm.chainId(legacyChains[i]);

            // Test legacy address is used for version 3.10
            vm.prank(crossChainGovernance);
            manager.deploySystemContract(AP_GEAR_STAKING, 3_10, false);
            assertEq(addressProvider.getAddressOrRevert(AP_GEAR_STAKING, NO_VERSION_CONTROL), expectedAddresses[i]);

            // Test normal deployment for other versions
            address newStaking = makeAddr("newStaking");
            vm.mockCall(
                address(manager.bytecodeRepository()),
                abi.encodeCall(
                    BytecodeRepository.deploy,
                    (AP_GEAR_STAKING, 3_11, abi.encode(manager.addressProvider()), bytes32(0))
                ),
                abi.encode(newStaking)
            );

            vm.prank(crossChainGovernance);
            manager.deploySystemContract(AP_GEAR_STAKING, 3_11, false);
            assertEq(addressProvider.getAddressOrRevert(AP_GEAR_STAKING, NO_VERSION_CONTROL), newStaking);
        }

        // Test on non-legacy chain
        vm.chainId(137); // Polygon
        address nonLegacyStaking = makeAddr("nonLegacyStaking");
        vm.mockCall(
            address(manager.bytecodeRepository()),
            abi.encodeCall(
                BytecodeRepository.deploy, (AP_GEAR_STAKING, 3_10, abi.encode(manager.addressProvider()), bytes32(0))
            ),
            abi.encode(nonLegacyStaking)
        );

        vm.prank(crossChainGovernance);
        manager.deploySystemContract(AP_GEAR_STAKING, 3_10, false);
        assertEq(addressProvider.getAddressOrRevert(AP_GEAR_STAKING, NO_VERSION_CONTROL), nonLegacyStaking);
    }
}
