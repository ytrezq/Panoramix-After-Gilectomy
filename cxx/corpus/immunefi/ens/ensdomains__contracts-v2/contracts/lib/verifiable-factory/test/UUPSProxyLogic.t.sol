// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {CloneProxyBytecode} from "../src/CloneProxyBytecode.sol";
import {IProxyAuthorization} from "../src/IProxyAuthorization.sol";
import {MockRegistry} from "../src/mock/MockRegistry.sol";
import {IUUPSProxy} from "../src/IUUPSProxy.sol";
import {UUPSProxyLogic} from "../src/UUPSProxyLogic.sol";

contract MockProxyAuthorization is IProxyAuthorization, OwnableUpgradeable, UUPSUpgradeable {
    address allowedPreviousImpl;

    constructor(address allowedPreviousImpl_) {
        allowedPreviousImpl = allowedPreviousImpl_;
    }

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function canUpgradeFrom(address previousImplementation) external view returns (bool) {
        return previousImplementation == allowedPreviousImpl;
    }
}

contract MaliciousProxyAuthorization is IProxyAuthorization, UUPSUpgradeable {
    constructor() {}

    function initialize() public initializer {
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override {}

    function canUpgradeFrom(
        address /*previousImplementation*/
    )
        external
        pure
        returns (bool)
    {
        return true;
    }

    function changeImplementation(address newImplementation) external {
        StorageSlot.getAddressSlot(ERC1967Utils.IMPLEMENTATION_SLOT).value = newImplementation;
    }
}

contract LogicPayableReceiver {
    uint256 public received;

    receive() external payable {
        received += msg.value;
    }
}

contract UUPSProxyLogicTest is Test {
    UUPSProxyLogic proxyLogic;
    UUPSProxyLogic proxy;
    MockProxyAuthorization mockProxyAuthorization;
    MaliciousProxyAuthorization maliciousProxyAuthorization;

    address factory;
    address owner = address(0x2);
    address maliciousUser = address(0x3);
    address implementation = address(new MockRegistry());
    bytes32 salt = bytes32(uint256(12345));
    bytes emptyData;

    function setUp() public {
        factory = address(this);
        proxyLogic = new UUPSProxyLogic();
        proxy = UUPSProxyLogic(payable(_deployProxyClone(address(proxyLogic), salt)));
        mockProxyAuthorization = new MockProxyAuthorization(address(implementation));
        maliciousProxyAuthorization = new MaliciousProxyAuthorization();
    }

    function test_Initialize() public {
        // initialize the proxy
        proxy.initialize(implementation, abi.encodeWithSelector(MockRegistry.initialize.selector, owner));

        // check salt and owner values
        (bytes32 actualSalt, address actualImplementation) = proxy.getVerifiableProxyData();
        assertEq(actualSalt, salt, "Salt mismatch");
        assertEq(actualImplementation, implementation, "Implementation mismatch");
        assertEq(proxy.verifiableProxyFactory(), factory, "Factory mismatch");
        assertEq(MockRegistry(address(proxy)).owner(), owner, "Owner mismatch");
    }

    function test_Initialize_ZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IUUPSProxy.ImplementationCannotBeZeroAddress.selector));
        proxy.initialize(address(0), emptyData);
    }

    function test_Initialize_AlreadyInitialized() public {
        proxy.initialize(implementation, abi.encodeWithSelector(MockRegistry.initialize.selector, owner));

        vm.expectRevert(abi.encodeWithSelector(IUUPSProxy.AlreadyInitialized.selector));
        proxy.initialize(implementation, emptyData);
    }

    function test_Initialize_WithValueAndEmptyDataReverts() public {
        vm.deal(address(this), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967NonPayable.selector));
        proxy.initialize{value: 1}(implementation, emptyData);
    }

    function test_ReceiveDelegatesToImplementation() public {
        LogicPayableReceiver receiver = new LogicPayableReceiver();
        proxy.initialize(address(receiver), emptyData);

        vm.deal(owner, 1 ether);
        vm.prank(owner);
        (bool success,) = address(proxy).call{value: 1}("");

        assertTrue(success, "Receive should delegate to implementation");
        assertEq(address(proxy).balance, 1, "Proxy balance mismatch");
        assertEq(LogicPayableReceiver(payable(address(proxy))).received(), 1, "Receive hook did not run");
    }

    function test_UpgradeToAndCall() public {
        // initialize the proxy
        proxy.initialize(implementation, abi.encodeWithSelector(MockRegistry.initialize.selector, owner));

        // upgrade to proxy authorization
        vm.prank(owner);
        proxy.upgradeToAndCall(address(mockProxyAuthorization), emptyData);

        // verify the upgrade
        (, address actualImplementation) = proxy.getVerifiableProxyData();
        assertEq(actualImplementation, address(mockProxyAuthorization), "Upgrade failed");
    }

    function test_UpgradeToAndCall_ZeroAddress() public {
        proxy.initialize(implementation, abi.encodeWithSelector(MockRegistry.initialize.selector, owner));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IUUPSProxy.ImplementationCannotBeZeroAddress.selector));
        proxy.upgradeToAndCall(address(0), emptyData);
    }

    function test_UpgradeToAndCall_ImplementationNotSet() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IUUPSProxy.ImplementationNotSet.selector));
        proxy.upgradeToAndCall(address(mockProxyAuthorization), emptyData);
    }

    function test_UpgradeToAndCall_UnauthorizedUpgrade() public {
        proxy.initialize(
            address(mockProxyAuthorization), abi.encodeWithSelector(MockRegistry.initialize.selector, owner)
        );

        vm.prank(maliciousUser);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, maliciousUser));
        proxy.upgradeToAndCall(address(maliciousProxyAuthorization), emptyData);
    }

    function test_UpgradeToAndCall_InvalidUpgradeTargetForCurrentImplementation() public {
        proxy.initialize(address(maliciousProxyAuthorization), emptyData);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IUUPSProxy.InvalidUpgradeTarget.selector,
                address(maliciousProxyAuthorization),
                address(mockProxyAuthorization)
            )
        );
        proxy.upgradeToAndCall(
            address(mockProxyAuthorization), abi.encodeWithSelector(MockRegistry.initialize.selector, owner)
        );
    }

    function test_UpgradeNotAllowedInContext() public {
        proxy.initialize(address(maliciousProxyAuthorization), emptyData);

        // change the implementation
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IUUPSProxy.UpgradeNotAllowedInContext.selector));
        MaliciousProxyAuthorization(address(proxy)).changeImplementation(address(implementation));
    }

    function _deployProxyClone(address logic, bytes32 salt_) internal returns (address clone) {
        bytes memory creationCode = CloneProxyBytecode.creationCode(logic, salt_);

        assembly {
            clone := create(0, add(creationCode, 0x20), mload(creationCode))
            if iszero(clone) {
                revert(0, 0)
            }
        }
    }
}
