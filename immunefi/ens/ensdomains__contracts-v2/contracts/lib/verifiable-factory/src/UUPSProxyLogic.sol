// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IProxyAuthorization} from "./IProxyAuthorization.sol";
import {IUUPSProxy} from "./IUUPSProxy.sol";

contract UUPSProxyLogic is IUUPSProxy {
    /// @dev `keccak256(bytes("eip1967.proxy.implementation")) - 1`.
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev `bytes4(keccak256(bytes("ImplementationCannotBeZeroAddress()")))`.
    uint256 internal constant _IMPLEMENTATION_CANNOT_BE_ZERO_ADDRESS_ERROR_SELECTOR = 0x0760838f;

    /// @dev `bytes4(keccak256(bytes("AlreadyInitialized()")))`.
    uint256 internal constant _ALREADY_INITIALIZED_ERROR_SELECTOR = 0x0dc149f0;

    /// @dev `bytes4(keccak256(bytes("UpgradeNotAllowedInContext()")))`.
    uint256 internal constant _UPGRADE_NOT_ALLOWED_IN_CONTEXT_ERROR_SELECTOR = 0x784cf700;

    /// @dev `bytes4(keccak256(bytes("UnexpectedUpgrade()")))`.
    uint256 internal constant _UNEXPECTED_UPGRADE_ERROR_SELECTOR = 0x2be61883;

    /// @dev `bytes4(keccak256(bytes("ERC1967InvalidImplementation(address)")))`.
    uint256 internal constant _ERC1967_INVALID_IMPLEMENTATION_ERROR_SELECTOR = 0x4c9c8ce3;

    /// @dev `bytes4(keccak256(bytes("ERC1967NonPayable()")))`.
    uint256 internal constant _ERC1967_NON_PAYABLE_ERROR_SELECTOR = 0xb398979f;

    /// @dev `bytes4(keccak256(bytes("Upgraded(address)")))`.
    uint256 internal constant _UPGRADED_EVENT_SELECTOR =
        0xbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b;

    address public immutable verifiableProxyFactory;

    constructor() {
        verifiableProxyFactory = msg.sender;
    }

    function initialize(address implementation, bytes calldata data) external payable {
        assembly {
            if eq(implementation, 0) {
                mstore(0, _IMPLEMENTATION_CANNOT_BE_ZERO_ADDRESS_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }
            if iszero(eq(sload(_IMPLEMENTATION_SLOT), 0)) {
                mstore(0, _ALREADY_INITIALIZED_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }
            if iszero(extcodesize(implementation)) {
                mstore(0, _ERC1967_INVALID_IMPLEMENTATION_ERROR_SELECTOR)
                mstore(0x20, implementation)
                revert(0x1c, 0x24)
            }
            sstore(_IMPLEMENTATION_SLOT, implementation)
            log2(0, 0, _UPGRADED_EVENT_SELECTOR, implementation)

            let dlength := data.length
            switch dlength
            case 0 {
                if callvalue() {
                    mstore(0, _ERC1967_NON_PAYABLE_ERROR_SELECTOR)
                    revert(0x1c, 0x04)
                }
            }
            default {
                calldatacopy(0, data.offset, dlength)
                let result := delegatecall(gas(), implementation, 0, dlength, 0, 0)
                if iszero(result) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }
        }
    }

    function getVerifiableProxyData() public view returns (bytes32 salt, address implementation) {
        assembly {
            extcodecopy(address(), 0, sub(extcodesize(address()), 0x20), 0x20)
            salt := mload(0)
            implementation := sload(_IMPLEMENTATION_SLOT)
        }
    }

    function upgradeToAndCall(address newImplementation, bytes calldata) external payable {
        if (newImplementation == address(0)) revert ImplementationCannotBeZeroAddress();

        address implementation = _implementation();
        if (implementation == address(0)) revert ImplementationNotSet();

        IProxyAuthorization newImpl = IProxyAuthorization(newImplementation);
        if (!newImpl.canUpgradeFrom(implementation)) {
            revert InvalidUpgradeTarget(implementation, newImplementation);
        }

        _delegateUpgrade(implementation, newImplementation);
    }

    function _implementation() internal view returns (address impl) {
        assembly {
            impl := sload(_IMPLEMENTATION_SLOT)
        }
    }

    function _delegate(address implementation, bool checkImplementation) internal {
        assembly {
            calldatacopy(0, 0, calldatasize())

            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            if checkImplementation {
                if iszero(eq(implementation, sload(_IMPLEMENTATION_SLOT))) {
                    mstore(0, _UPGRADE_NOT_ALLOWED_IN_CONTEXT_ERROR_SELECTOR)
                    revert(0x1c, 0x04)
                }
            }

            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    function _delegateUpgrade(address implementation, address expectedImplementation) internal {
        assembly {
            calldatacopy(0, 0, calldatasize())

            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            if iszero(result) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            if iszero(eq(expectedImplementation, sload(_IMPLEMENTATION_SLOT))) {
                mstore(0, _UNEXPECTED_UPGRADE_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }

            returndatacopy(0, 0, returndatasize())
            return(0, returndatasize())
        }
    }

    fallback() external payable {
        _delegate(_implementation(), true);
    }
}
