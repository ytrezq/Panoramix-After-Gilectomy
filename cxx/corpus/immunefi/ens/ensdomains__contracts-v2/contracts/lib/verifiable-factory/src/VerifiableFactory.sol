// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {CloneProxyBytecode} from "./CloneProxyBytecode.sol";
import {UUPSProxyLogic} from "./UUPSProxyLogic.sol";
import {IUUPSProxy} from "./IUUPSProxy.sol";
import {IVerifiableFactory} from "./IVerifiableFactory.sol";

contract VerifiableFactory is IVerifiableFactory {
    address public immutable proxyLogic;

    constructor() {
        proxyLogic = address(new UUPSProxyLogic());
    }

    /**
     * @dev Deploys a new verifiable proxy clone at a deterministic address.
     *
     * The deployed proxy is an EIP-1167-style clone that delegates proxy mechanics to the
     * factory's `proxyLogic` contract. The clone runtime also appends the derived salt so the
     * factory can later verify the proxy's CREATE2 address.
     *
     * The CREATE2 salt is `keccak256(abi.encode(msg.sender, salt))`, so two callers can reuse
     * the same user salt without colliding.
     *
     * @param implementation The address of the contract implementation the proxy will delegate calls to.
     * @param salt A value provided by the caller to ensure uniqueness of the proxy address.
     * @return proxy The address of the deployed proxy clone.
     */
    function deployProxy(address implementation, uint256 salt, bytes memory data) external returns (address proxy) {
        bytes32 outerSalt = keccak256(abi.encode(msg.sender, salt));
        bytes memory executableBytecode = _proxyCreationCode(outerSalt);

        assembly {
            proxy := create2(0, add(executableBytecode, 0x20), mload(executableBytecode), outerSalt)
            if iszero(proxy) {
                revert(0, 0)
            }
        }

        IUUPSProxy(proxy).initialize(implementation, data);

        emit ProxyDeployed(msg.sender, proxy, salt, implementation);
    }

    /**
     * @dev Verifies a proxy contract and returns its current implementation.
     *
     * This function attempts to validate a proxy contract by retrieving its salt
     * and reconstructing the address to ensure it was correctly deployed by the
     * current factory.
     *
     * @param proxy The address of the proxy contract being verified.
     * @return implementation The proxy's current implementation.
     */
    function verifyContract(address proxy) public view returns (address implementation) {
        if (!isContract(proxy)) revert VerificationFailed(proxy);

        try IUUPSProxy(proxy).getVerifiableProxyData() returns (bytes32 salt, address actualImplementation) {
            if (_verifyContract(proxy, salt)) return actualImplementation;
        } catch {}
        revert VerificationFailed(proxy);
    }

    function _verifyContract(address proxy, bytes32 salt) private view returns (bool) {
        bytes memory proxyBytecode = _proxyCreationCode(salt);

        address expectedProxyAddress = Create2.computeAddress(salt, keccak256(proxyBytecode), address(this));

        return expectedProxyAddress == proxy;
    }

    function _proxyCreationCode(bytes32 salt) private view returns (bytes memory creationCode) {
        creationCode = CloneProxyBytecode.creationCode(proxyLogic, salt);
    }

    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}
