// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {LibString} from "@solady/utils/LibString.sol";

library Domain {
    using LibString for string;
    using LibString for bytes32;

    uint128 internal constant UNDERSCORE = 1 << 95;

    function getContractType(bytes32 domain, bytes32 postfix) internal pure returns (bytes32) {
        if (postfix == 0) return domain;
        return string.concat(domain.fromSmallString(), "::", postfix.fromSmallString()).toSmallString();
    }

    function extractDomain(bytes32 contractType) internal pure returns (bytes32) {
        string memory str = contractType.fromSmallString();
        uint256 separatorIndex = str.indexOf("::");

        // If no separator found, treat the whole type as domain
        if (separatorIndex == LibString.NOT_FOUND) return str.toSmallString();

        return str.slice(0, separatorIndex).toSmallString();
    }

    function extractPostfix(bytes32 contractType) internal pure returns (bytes32) {
        string memory str = contractType.fromSmallString();
        uint256 separatorIndex = str.indexOf("::");

        // if no separator found, return empty postfix
        if (separatorIndex == LibString.NOT_FOUND) return bytes32(0);

        return str.slice(separatorIndex + 2).toSmallString();
    }

    function isValidContractType(bytes32 contractType) internal pure returns (bool) {
        bytes32 domain = extractDomain(contractType);
        if (!isValidDomain(domain)) return false;

        bytes32 postfix = extractPostfix(contractType);
        if (!isValidPostfix(postfix)) return false;

        // avoid the "DOMAIN::" case
        return contractType == getContractType(domain, postfix);
    }

    function isValidDomain(bytes32 domain) internal pure returns (bool) {
        return domain != 0 && _isValidString(domain.fromSmallString());
    }

    function isValidPostfix(bytes32 postfix) internal pure returns (bool) {
        return _isValidString(postfix.fromSmallString());
    }

    function _isValidString(string memory str) internal pure returns (bool) {
        return str.is7BitASCII(LibString.ALPHANUMERIC_7_BIT_ASCII | UNDERSCORE);
    }
}
