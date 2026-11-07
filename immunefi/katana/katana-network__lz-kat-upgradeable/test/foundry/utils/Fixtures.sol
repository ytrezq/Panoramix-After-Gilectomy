// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MyERC20Mock} from "../../../contracts/mocks/MyERC20Mock.sol";

contract Fixtures is TestHelperOz5 {
    // EIP-1967 implementation slot
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    uint8 aEid = 1;
    uint8 bEid = 2;
    address public proxyAdmin = makeAddr("proxyAdmin");
    MyERC20Mock erc20Mock;

    function setUp() public virtual override {
        super.setUp();
        // Create 2 endpoints with EIDs 1 and 2
        setUpEndpoints(2, LibraryType.SimpleMessageLib);
        erc20Mock = new MyERC20Mock("Test", "TEST");
        erc20Mock.mint(address(this), 100 ether);
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
}
