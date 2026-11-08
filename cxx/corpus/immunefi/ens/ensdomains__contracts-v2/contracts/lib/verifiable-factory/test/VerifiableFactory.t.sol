// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {OwnableUpgradeable, Initializable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

import {CloneProxyBytecode} from "../src/CloneProxyBytecode.sol";
import {VerifiableFactory} from "../src/VerifiableFactory.sol";
import {IVerifiableFactory} from "../src/IVerifiableFactory.sol";
import {IProxyAuthorization} from "../src/IProxyAuthorization.sol";
import {IUUPSProxy} from "../src/IUUPSProxy.sol";
import {MockRegistry} from "../src/mock/MockRegistry.sol";
import {MockRegistryV2} from "../src/mock/MockRegistryV2.sol";
import {NonUUPSImpl} from "../src/mock/NonUUPSImpl.sol";
import {StorageConflictImplementation} from "../src/mock/StorageCollusionImpl.sol";

contract VerifiableFactoryTest is Test {
    // contract instances
    VerifiableFactory public factory;
    MockRegistry public implementation;
    MockRegistryV2 public implementationV2;
    MockRegistryV2 public nonTrustedImpl;

    // test addresses
    address public owner;
    address public user;
    address public maliciousUser;
    bytes emptyData;

    // ### Events
    event ProxyDeployed(address indexed sender, address indexed proxyAddress, uint256 salt, address implementation);

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        maliciousUser = makeAddr("malicious");

        // deploy contracts
        factory = new VerifiableFactory();
        implementation = new MockRegistry();
        implementationV2 = new MockRegistryV2(address(implementation));
        nonTrustedImpl = new MockRegistryV2(address(implementation));

        vm.label(address(factory), "Factory");
        vm.label(address(implementation), "Implementation");
        vm.label(address(implementationV2), "ImplementationV2");
    }

    function test_FactoryInitialState() public view {
        assertTrue(address(factory) != address(0), "Factory deployment failed");
        assertTrue(factory.proxyLogic() != address(0), "Proxy logic deployment failed");
        assertTrue(address(implementation) != address(0), "Implementation deployment failed");
    }

    function test_DeployProxy() public {
        uint256 salt = 1;

        // test event emit
        vm.expectEmit(true, true, true, true);
        emit ProxyDeployed(owner, computeExpectedAddress(salt), salt, address(implementation));

        vm.startPrank(owner);
        address proxyAddress = factory.deployProxy(address(implementation), salt, emptyData);

        vm.stopPrank();

        // verify proxy deployment
        assertTrue(proxyAddress != address(0), "Proxy address should not be zero");
        assertTrue(isContract(proxyAddress), "Proxy should be a contract");

        // verify proxy state
        IUUPSProxy proxy = IUUPSProxy(proxyAddress);
        bytes32 computedSalt = keccak256(abi.encode(owner, salt));
        (bytes32 actualSalt, address actualImplementation) = proxy.getVerifiableProxyData();
        assertEq(actualSalt, computedSalt, "Proxy salt mismatch");
        assertEq(actualImplementation, address(implementation), "Implementation mismatch");
        assertEq(proxy.verifiableProxyFactory(), address(factory), "Proxy factory mismatch");
    }

    function test_DeployProxyWithSameSalt() public {
        uint256 salt = 1;
        vm.startPrank(owner);

        // deploy first proxy
        factory.deployProxy(address(implementation), salt, emptyData);

        // try to deploy another proxy with same salt - should fail
        vm.expectRevert(bytes(""));
        factory.deployProxy(address(implementation), salt, emptyData);

        vm.stopPrank();
    }

    function test_DeployProxyWithEmptyBytecode() public {
        uint256 salt = 1;
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(maliciousUser))
        );
        factory.deployProxy(address(maliciousUser), salt, emptyData);
        vm.stopPrank();
    }

    function test_UpgradeImplementation() public {
        uint256 salt = 1;

        bytes memory initData = abi.encodeWithSelector(MockRegistry.initialize.selector, owner);
        // deploy proxy as owner
        vm.prank(owner);
        address proxyAddress = factory.deployProxy(address(implementation), salt, initData);

        MockRegistry proxyV1 = MockRegistry(proxyAddress);

        // try to upgrade as non-owner (should fail)
        vm.prank(maliciousUser);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, maliciousUser));
        proxyV1.upgradeToAndCall(
            address(implementationV2),
            "" // add upgrade data if we need
        );

        // upgrade as owner (should pass)
        vm.prank(owner);
        proxyV1.upgradeToAndCall(
            address(implementationV2),
            "" // add upgrade data if we need
        );

        // verify new implementation
        MockRegistryV2 upgradedProxy = MockRegistryV2(proxyAddress);
        assertEq(upgradedProxy.getRegistryVersion(), 2, "Implementation upgrade failed");
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        upgradedProxy.initialize(owner);
    }

    function test_UpgradeToNonUUPS() public {
        uint256 salt = 1;
        bytes memory initData = abi.encodeWithSelector(MockRegistry.initialize.selector, owner);

        // Deploy proxy
        vm.prank(owner);
        address proxyAddress = factory.deployProxy(address(implementation), salt, initData);

        // attempt upgrade to non-UUPS contract
        NonUUPSImpl badImpl = new NonUUPSImpl();
        MockRegistry proxy = MockRegistry(proxyAddress);

        vm.prank(owner);
        vm.expectRevert(); // should fail ERC1967 check
        proxy.upgradeToAndCall(address(badImpl), "");
    }

    function test_UpgradeToNonCompatibleImplementation() public {
        uint256 salt = 1;
        bytes memory initData = abi.encodeWithSelector(MockRegistry.initialize.selector, owner);

        // deploy proxy
        vm.prank(owner);
        address proxyAddress = factory.deployProxy(address(implementationV2), salt, initData);
        MockRegistryV2 proxy = MockRegistryV2(proxyAddress);

        vm.prank(owner);
        vm.expectRevert();
        proxy.upgradeToAndCall(address(nonTrustedImpl), "");
    }

    function test_VerifyContract() public {
        uint256 salt = 1;

        // deploy proxy
        vm.prank(owner);
        address proxyAddress = factory.deployProxy(address(implementation), salt, emptyData);

        vm.prank(owner);
        // verify the contract
        address verifiedImplementation = factory.verifyContract(proxyAddress);
        assertEq(verifiedImplementation, address(implementation), "Wrong verified implementation");

        vm.prank(owner);
        // try to verify non-existent contract
        address randomAddress = makeAddr("random");
        vm.expectRevert(abi.encodeWithSelector(IVerifiableFactory.VerificationFailed.selector, randomAddress));
        factory.verifyContract(randomAddress);
    }

    function test_VerifyContract_ReturnsCurrentImplementationAfterUpgrade() public {
        uint256 salt = 1;
        bytes memory initData = abi.encodeWithSelector(MockRegistry.initialize.selector, owner);

        // deploy proxy
        vm.prank(owner);
        address proxyAddress = factory.deployProxy(address(implementation), salt, initData);

        vm.prank(owner);
        MockRegistry(proxyAddress).upgradeToAndCall(address(implementationV2), "");

        address verifiedImplementation = factory.verifyContract(proxyAddress);
        assertEq(verifiedImplementation, address(implementationV2), "Wrong upgraded implementation");
    }

    function test_VerifyContract_RejectsTrustedImplementationAfterBypassedUpgrade() public {
        uint256 salt = 1;
        UpgradeAuthorizationBypass untrustedImplementation = new UpgradeAuthorizationBypass(address(implementationV2));
        PermissiveUpgradeTarget claimedUpgradeTarget = new PermissiveUpgradeTarget();

        assertFalse(
            implementationV2.canUpgradeFrom(address(untrustedImplementation)),
            "Trusted implementation should reject the untrusted predecessor"
        );

        vm.prank(owner);
        address proxyAddress = factory.deployProxy(address(untrustedImplementation), salt, emptyData);
        assertEq(
            factory.verifyContract(proxyAddress),
            address(untrustedImplementation),
            "Proxy should start on the untrusted implementation"
        );

        vm.expectRevert(abi.encodeWithSelector(IUUPSProxy.UnexpectedUpgrade.selector));
        IUpgradeToAndCall(proxyAddress).upgradeToAndCall(address(claimedUpgradeTarget), "");

        assertEq(
            factory.verifyContract(proxyAddress),
            address(untrustedImplementation),
            "Proxy should stay on the untrusted implementation after rejected bypass"
        );
    }

    function test_ProxyInitialization() public {
        uint256 salt = 1;

        // deploy proxy
        vm.prank(owner);
        address proxyAddress = factory.deployProxy(address(implementation), salt, emptyData);

        // test proxy state
        IUUPSProxy proxy = IUUPSProxy(proxyAddress);

        bytes32 computedSalt = keccak256(abi.encode(owner, salt));
        (bytes32 actualSalt, address actualImplementation) = proxy.getVerifiableProxyData();
        assertEq(actualSalt, computedSalt, "Wrong salt");
        assertEq(actualImplementation, address(implementation), "Wrong implementation");
        assertEq(proxy.verifiableProxyFactory(), address(factory), "Wrong factory");
    }

    function test_ProxyReceiveDelegatesToImplementation() public {
        PayableReceiver receiver = new PayableReceiver();

        vm.prank(owner);
        address proxyAddress = factory.deployProxy(address(receiver), 1, emptyData);

        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool success,) = proxyAddress.call{value: 1}("");

        assertTrue(success, "Receive should delegate to implementation");
        assertEq(proxyAddress.balance, 1, "Proxy balance mismatch");
        assertEq(PayableReceiver(payable(proxyAddress)).received(), 1, "Receive hook did not run");
    }

    function test_ProxyReceiveRevertsWhenImplementationRejectsEth() public {
        vm.prank(owner);
        address proxyAddress = factory.deployProxy(address(implementation), 1, emptyData);

        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool success,) = proxyAddress.call{value: 1}("");

        assertFalse(success, "Receive should follow implementation payable behavior");
        assertEq(proxyAddress.balance, 0, "Proxy should not retain rejected ETH");
    }

    function test_StoragePersistenceAfterUpgrade() public {
        uint256 salt = 1;
        address testAccount = makeAddr("testAccount");

        bytes memory initData = abi.encodeWithSelector(MockRegistry.initialize.selector, owner);

        // deploy proxy
        vm.prank(owner);
        address proxyAddress = factory.deployProxy(address(implementation), salt, initData);

        // initialize v1 implementation
        MockRegistry proxyV1 = MockRegistry(proxyAddress);

        assertEq(proxyV1.owner(), owner, "Owner should be set");

        // register an address
        vm.prank(owner);
        proxyV1.register(testAccount);
        assertTrue(proxyV1.registeredAddresses(testAccount), "Address should be registered in V1");
        assertEq(proxyV1.getRegistryVersion(), 1, "Should be V1 implementation");

        // upgrade to v2
        vm.prank(owner);
        proxyV1.upgradeToAndCall(
            address(implementationV2),
            "" // add upgrade data if we need
        );

        // verify state persists after upgrade
        MockRegistryV2 proxyV2 = MockRegistryV2(proxyAddress);

        // check storage persistence
        assertTrue(proxyV2.registeredAddresses(testAccount), "Address registration should persist after upgrade");
        assertEq(proxyV2.owner(), owner, "Owner should persist after upgrade");
        assertEq(proxyV2.getRegistryVersion(), 2, "Should be V2 implementation");

        // verify v2 functionality still works as it should be
        address newTestAccount = makeAddr("newTestAccount");
        vm.prank(owner);
        proxyV2.register(newTestAccount);
        assertTrue(proxyV2.registeredAddresses(newTestAccount), "Should be able to register new address in V2");

        address newTestAccount2 = makeAddr("newTestAccount2");
        vm.prank(maliciousUser);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, maliciousUser));
        proxyV2.register(newTestAccount2);
    }

    function test_ProxyOwner() public {
        uint256 salt = 1;

        bytes memory initData = abi.encodeWithSelector(MockRegistry.initialize.selector, owner);

        vm.prank(owner);
        address proxyAddress = factory.deployProxy(address(implementation), salt, initData);

        // test proxy state
        IUUPSProxy proxy = IUUPSProxy(proxyAddress);
        MockRegistry proxyRegistryV1 = MockRegistry(proxyAddress);

        bytes32 computedSalt = keccak256(abi.encode(owner, salt));
        (bytes32 actualSalt,) = proxy.getVerifiableProxyData();
        assertEq(actualSalt, computedSalt, "Wrong proxy salt");
        assertEq(proxyRegistryV1.owner(), owner, "Wrong proxyRegistryV1 owner");
        assertEq(proxy.verifiableProxyFactory(), address(factory), "Wrong proxy factory");
    }

    function test_StorageCollision() public {
        uint256 salt = 1;
        bytes memory initData = abi.encodeWithSelector(MockRegistry.initialize.selector, owner);
        // deploy proxy
        vm.prank(owner);
        address proxy = factory.deployProxy(address(implementation), salt, initData);

        // upgrade to conflicting layout
        StorageConflictImplementation conflict = new StorageConflictImplementation();
        vm.prank(owner);
        MockRegistry(proxy).upgradeToAndCall(address(conflict), "");

        // execute dangerous storage manipulation
        StorageConflictImplementation conflictedProxy = StorageConflictImplementation(proxy);
        conflictedProxy.dangerousMethod();

        // verify critical storage slots maintained
        IUUPSProxy proxyInstance = IUUPSProxy(proxy);
        assertEq(proxyInstance.verifiableProxyFactory(), address(factory), "Factory ref corrupted");
        (bytes32 actualSalt,) = proxyInstance.getVerifiableProxyData();
        assertEq(actualSalt, keccak256(abi.encode(owner, salt)), "Salt ref corrupted");
    }

    function testFuzz_VerifyContract(uint256 salt) public {
        // deploy implementation
        MockRegistry impl = new MockRegistry();

        bytes memory initData = abi.encodeWithSelector(MockRegistry.initialize.selector, owner);

        // deploy proxy
        vm.prank(owner);
        address proxy = factory.deployProxy(address(impl), salt, initData);

        // verification checks
        address verifiedImplementation = factory.verifyContract(proxy);
        assertEq(verifiedImplementation, address(impl), "Fuzz verification failed");

        // additional safety assertions
        assertEq(IUUPSProxy(proxy).verifiableProxyFactory(), address(factory), "Factory relationship broken");
        assertTrue(isContract(proxy), "Proxy must be valid contract");
    }

    // ### Helpers
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function computeExpectedAddress(uint256 salt) internal view returns (address) {
        bytes32 outerSalt = keccak256(abi.encode(owner, salt));

        bytes memory bytecode = CloneProxyBytecode.creationCode(factory.proxyLogic(), outerSalt);

        return Create2.computeAddress(outerSalt, keccak256(bytecode), address(factory));
    }
}

contract PayableReceiver {
    uint256 public received;

    receive() external payable {
        received += msg.value;
    }
}

contract PermissiveUpgradeTarget is IProxyAuthorization {
    function canUpgradeFrom(address) external pure returns (bool) {
        return true;
    }
}

interface IUpgradeToAndCall {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

contract UpgradeAuthorizationBypass is IProxyAuthorization {
    address private immutable forcedImplementation;

    constructor(address forcedImplementation_) {
        forcedImplementation = forcedImplementation_;
    }

    function canUpgradeFrom(address) external pure returns (bool) {
        return true;
    }

    function upgradeToAndCall(address, bytes calldata) external payable {
        StorageSlot.getAddressSlot(ERC1967Utils.IMPLEMENTATION_SLOT).value = forcedImplementation;
    }
}
