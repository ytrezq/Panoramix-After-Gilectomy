// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Domain} from "../../libraries/Domain.sol";

contract DomainUnitTest is Test {
    /// @notice Tests extracting domain from various inputs
    function test_U_DOM_01_extracts_domain() public pure {
        assertEq(Domain.extractDomain("test::name"), "test"); // With separator
        assertEq(Domain.extractDomain("test"), "test"); // Without separator
        assertEq(Domain.extractDomain(""), ""); // Empty string
        assertEq(Domain.extractDomain("test::sub::name"), "test"); // Multiple separators
    }

    /// @notice Tests extracting postfix from various inputs
    function test_U_DOM_02_extracts_postfix() public pure {
        assertEq(Domain.extractPostfix("test::name"), "name"); // With separator
        assertEq(Domain.extractPostfix("test"), bytes32(0)); // Without separator
        assertEq(Domain.extractDomain(""), ""); // Empty string
        assertEq(Domain.extractPostfix("test::sub::name"), "sub::name"); // Multiple separators
    }

    /// @notice Tests getting contract type with various inputs
    function test_U_DOM_03_gets_contract_type() public pure {
        assertEq(Domain.getContractType("test", "name"), "test::name"); // With domain and postfix
        assertEq(Domain.getContractType("test", bytes32(0)), "test"); // With domain only
        assertEq(Domain.getContractType(bytes32(0), "name"), "::name"); // With postfix only
    }

    /// @notice Tests domain validation
    function test_U_DOM_04_validates_domain() public pure {
        // Valid domains
        assertTrue(Domain.isValidDomain("test"));
        assertTrue(Domain.isValidDomain("test123"));
        assertTrue(Domain.isValidDomain("test_type"));
        assertTrue(Domain.isValidDomain("testType"));
        assertTrue(Domain.isValidDomain("123"));
        assertTrue(Domain.isValidDomain("_"));

        // Invalid domains
        assertFalse(Domain.isValidDomain("")); // empty
        assertFalse(Domain.isValidDomain("test space")); // spaces
        assertFalse(Domain.isValidDomain("test$")); // symbols
        assertFalse(Domain.isValidDomain(unicode"тест")); // unicode
    }

    /// @notice Tests postfix validation
    function test_U_DOM_05_validates_postfix() public pure {
        // Valid postfixes
        assertTrue(Domain.isValidPostfix("name"));
        assertTrue(Domain.isValidPostfix("name456"));
        assertTrue(Domain.isValidPostfix("name_test"));
        assertTrue(Domain.isValidPostfix("nameTest"));
        assertTrue(Domain.isValidPostfix("456"));
        assertTrue(Domain.isValidPostfix("_"));
        assertTrue(Domain.isValidPostfix(bytes32(0))); // empty postfix is valid

        // Invalid postfixes
        assertFalse(Domain.isValidPostfix("name space")); // spaces
        assertFalse(Domain.isValidPostfix("name#")); // symbols
        assertFalse(Domain.isValidPostfix(unicode"имя")); // unicode
    }

    /// @notice Tests contract type validation
    function test_U_DOM_06_validates_contract_type() public pure {
        // Valid contract types
        assertTrue(Domain.isValidContractType("test::name")); // with postfix
        assertTrue(Domain.isValidContractType("test")); // without postfix
        assertTrue(Domain.isValidContractType("test123::name456")); // with numbers
        assertTrue(Domain.isValidContractType("test_type::name_test")); // with underscores
        assertTrue(Domain.isValidContractType("testType::nameTest")); // mixed case
        assertTrue(Domain.isValidContractType("123::456")); // only numbers
        assertTrue(Domain.isValidContractType("_::_")); // only underscores
        assertTrue(Domain.isValidContractType("a::b")); // single chars

        // Invalid contract types
        assertFalse(Domain.isValidContractType("")); // empty
        assertFalse(Domain.isValidContractType("test::sub::name")); // double nested
        assertFalse(Domain.isValidContractType("test::")); // empty postfix after separator
        assertFalse(Domain.isValidContractType("test space::name")); // invalid domain
        assertFalse(Domain.isValidContractType("test::name space")); // invalid postfix
        assertFalse(Domain.isValidContractType("test$::name")); // invalid domain symbol
        assertFalse(Domain.isValidContractType("test::name#")); // invalid postfix symbol
        assertFalse(Domain.isValidContractType(unicode"тест::name")); // invalid domain unicode
        assertFalse(Domain.isValidContractType(unicode"test::имя")); // invalid postfix unicode
    }
}
