// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { EndpointV2Mock } from "@layerzerolabs/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { MyERC20Mock } from "../../contracts/mocks/MyERC20Mock.sol";
import { KATOFTUpgradeable } from "../../contracts/KATOFTUpgradeable.sol";
import { KATOFTAdapterUpgradeable } from "../../contracts/KATOFTAdapterUpgradeable.sol";

contract KATOFTUpgradeableTest is TestHelperOz5 {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    uint32 aEid = 1;
    uint32 cEid = 3;
    address public proxyAdmin = makeAddr("proxyAdmin");
    MyERC20Mock cERC20Mock;

    function setUp() public virtual override {
        cERC20Mock = new MyERC20Mock("Test", "TEST");
        super.setUp();
        setUpEndpoints(3, LibraryType.UltraLightNode);
    }

    function _deployContractAndProxy(
        bytes memory _oappBytecode,
        bytes memory _constructorArgs,
        bytes memory _initializeArgs
    ) internal virtual returns (address addr) {
        bytes memory bytecode = bytes.concat(abi.encodePacked(_oappBytecode), _constructorArgs);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }

        return address(new TransparentUpgradeableProxy(addr, proxyAdmin, _initializeArgs));
    }

    function test_oft_implementation_initialization_disabled() public {
        KATOFTUpgradeable oftUpgradeable = KATOFTUpgradeable(
            _deployContractAndProxy(
                type(KATOFTUpgradeable).creationCode,
                abi.encode(address(endpoints[aEid])),
                abi.encodeWithSelector(
                    KATOFTUpgradeable.initialize.selector,
                    "oftUpgradeable",
                    "oftUpgradeable",
                    address(this)
                )
            )
        );

        bytes32 implementationRaw = vm.load(address(oftUpgradeable), IMPLEMENTATION_SLOT);
        address implementationAddress = address(uint160(uint256(implementationRaw)));

        KATOFTUpgradeable oftUpgradeableImplementation = KATOFTUpgradeable(implementationAddress);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        oftUpgradeableImplementation.initialize("oftUpgradeable", "oftUpgradeable", address(this));

        EndpointV2Mock endpoint = EndpointV2Mock(address(oftUpgradeable.endpoint()));
        assertEq(endpoint.delegates(address(oftUpgradeable)), address(this));
        assertEq(endpoint.delegates(implementationAddress), address(0));
    }
}
