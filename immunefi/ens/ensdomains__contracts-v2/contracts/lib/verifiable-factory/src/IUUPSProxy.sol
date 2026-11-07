// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUUPSProxy {
    /// @dev Error selector: `0x0760838f`
    error ImplementationCannotBeZeroAddress();

    /// @dev Error selector: `0x0dc149f0`
    error AlreadyInitialized();

    /// @dev Error selector: `0x40dde935`
    error ImplementationNotSet();

    /// @dev Error selector: `0xca331687`
    error InvalidUpgradeTarget(address currentImplementation, address newImplementation);

    /// @dev Error selector: `0x784cf700`
    error UpgradeNotAllowedInContext();

    /// @dev Error selector: `0x2be61883`
    error UnexpectedUpgrade();

    function initialize(address implementation, bytes calldata data) external payable;

    function getVerifiableProxyData() external view returns (bytes32 salt, address implementation);

    function verifiableProxyFactory() external view returns (address);
}
