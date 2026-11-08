// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { AccessControlled  } from '../../../contracts/governance/AccessControlled.sol';

contract CallAccess is AccessControlled {

    uint256 public value;

    constructor (address acm) AccessControlled () {
        setAccessControlManagerInner(acm);
    }

    modifier isCallAllowed () {
        _checkAccessAllowed(msg.sig);
        _;
    }

    function setValue(uint256 value_) public isCallAllowed () {
        value = value_;
    }
}
