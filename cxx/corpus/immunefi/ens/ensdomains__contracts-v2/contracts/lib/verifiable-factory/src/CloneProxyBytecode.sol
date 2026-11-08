// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library CloneProxyBytecode {
    // EIP-1167 minimal proxy creation/runtime code:
    // https://eips.ethereum.org/EIPS/eip-1167
    //
    // Standard runtime is 45 bytes:
    // 363d3d373d3d3d363d73<20-byte implementation>5af43d82803e903d91602b57fd5bf3
    //
    // We append a 32-byte salt to the runtime and make the creation stub return 77 bytes
    // instead of the standard 45. The proxy still executes the same minimal-proxy logic;
    // UUPSProxyLogic reads the appended salt with extcodecopy().
    uint256 internal constant CREATION_CODE_LENGTH = 0x57;

    function creationCode(address logic, bytes32 salt) internal pure returns (bytes memory code) {
        code = new bytes(CREATION_CODE_LENGTH);

        assembly ("memory-safe") {
            let ptr := add(code, 0x20)

            // Creation stub plus runtime prefix. The creation stub returns 77 bytes:
            // 45 bytes of EIP-1167 runtime plus our appended 32-byte salt.
            mstore(ptr, 0x3d604d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            // Fill the EIP-1167 PUSH20 slot with the shared proxy logic address.
            mstore(add(ptr, 0x14), shl(0x60, logic))
            // Runtime suffix: delegatecall to `logic`, copy returndata, then return or revert.
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            // Append salt after the executable minimal-proxy runtime for extcodecopy().
            mstore(add(ptr, 0x37), salt)
        }
    }
}
