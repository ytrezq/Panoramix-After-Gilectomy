// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { Test } from "../../modules/forge-std/src/Test.sol";

contract Spied is Test {

    bool internal assertCalls;
    bool internal captureCall;

    uint256 callCount;

    bytes[] internal calls;

    modifier spied() {
        if (captureCall) {
            calls.push(msg.data);
            captureCall = false;
        } else {
            if (assertCalls) {
                assertEq(msg.data, calls[callCount++], "Unexpected call spied");
            }

            _;
        }
    }

    function __expectCall() public {
        assertCalls = true;
        captureCall = true;
    }

}

contract MockGlobals is Spied {

    address public governor;
    address public mapleTreasury;

    bool internal _isInstance;
    bool internal _isScheduled;

    function __setGovernor(address governor_) external {
        governor = governor_;
    }

    function __setIsInstance(bool isInstance_) external {
        _isInstance = isInstance_;
    }

    function __setIsValidScheduledCall(bool isValidScheduledCall_) external {
        _isScheduled = isValidScheduledCall_;
    }

    function __setMapleTreasury(address mapleTreasury_) external {
        mapleTreasury = mapleTreasury_;
    }

    function isInstanceOf(bytes32, address) external view returns (bool isInstance_) {
        isInstance_ = _isInstance;
    }

    function isValidScheduledCall(address, address, bytes32, bytes calldata) external view returns (bool isValidScheduledCall_) {
        isValidScheduledCall_ = _isScheduled;
    }

    function unscheduleCall(address, bytes32, bytes calldata) external spied { }

}

contract MockToken is Spied {

    address public globals;

    function burn(address, uint256) external spied { }

    function mint(address, uint256) external spied { }

    function __setGlobals(address globals_) external {
        globals = globals_;
    }

}
