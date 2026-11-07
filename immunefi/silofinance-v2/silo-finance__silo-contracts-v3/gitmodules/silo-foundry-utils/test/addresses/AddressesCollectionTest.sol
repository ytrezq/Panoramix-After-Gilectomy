// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";

import {A} from "./mocks/A.sol";
import {B} from "./mocks/B.sol";

// forge test --match-contract AddressesCollectionTest -vvv
contract AddressesCollectionTest is IntegrationTest {
    A internal _a = new A();
    B internal _b = new B();

    address internal _addr1 = address(1);
    address internal _addr2 = address(2);

    string internal _key1 = "_key1";
    string internal _key2 = "_key2";

    function testSetGetAddress() public {
        _a.setAddress(_key1, _addr1);
        _b.setAddress(_key2, _addr2);

        address resultKey2 = _a.getAddress(_key2);
        address resultKey1 = _b.getAddress(_key1);

        assertEq(_addr1, resultKey1);
        assertEq(_addr2, resultKey2);
    }
}
