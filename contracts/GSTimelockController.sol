// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title GammaSwap's Timelock Controller
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @dev Inherit's OZ's TimelockController and adds/removes emergency functions that bypass the timelock delay
contract GSTimelockController is TimelockController {

    error EmergencyCallExists(bytes32 id);
    error EmergencyCallNotExists(bytes32 id);
    error TxFailedError();

    event AddEmergencyCall(bytes32 indexed id, address indexed target, string func);
    event RemoveEmergencyCall(bytes32 indexed id, address indexed target, string func);
    event ExecuteEmergencyCall(bytes32 indexed id, address indexed target, uint256 value, string func, bytes data, uint256 timestamp);

    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    mapping(bytes32 => bool) public emergencyFuncById;

    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin) {

        _setRoleAdmin(EMERGENCY_ROLE, TIMELOCK_ADMIN_ROLE);
        _setupRole(EMERGENCY_ROLE, admin);
    }

    function hasEmergencyFunction(address _target, string calldata _func) public view returns(bool) {
        bytes32 id = getEmergencyFuncId(_target, _func);
        return emergencyFuncById[id] == true;
    }

    function getEmergencyFuncId(address _target, string calldata _func) public pure returns (bytes32) {
        return keccak256(abi.encode(_target, _func));
    }

    // Queue function signature itself without timestamp range
    function addEmergencyCall(address _target, string calldata _func) external virtual {
        require(msg.sender == address(this), "TimelockController: caller must be timelock");
        bytes32 id = getEmergencyFuncId(_target, _func);
        if (emergencyFuncById[id]) {
            revert EmergencyCallExists(id);
        }

        emergencyFuncById[id] = true;

        emit AddEmergencyCall(id, _target, _func);
    }

    // Queue function signature itself without timestamp range
    function removeEmergencyCall(address _target, string calldata _func) external virtual {
        require(msg.sender == address(this), "TimelockController: caller must be timelock");
        bytes32 id = getEmergencyFuncId(_target, _func);
        if (!emergencyFuncById[id]) {
            revert EmergencyCallNotExists(id);
        }

        delete emergencyFuncById[id];

        emit RemoveEmergencyCall(id, _target, _func);
    }

    function executeEmergency( address _target, uint256 _value, string calldata _func, bytes calldata _data) external
        payable onlyRole(EMERGENCY_ROLE) returns (bytes memory) {
        bytes32 id = getEmergencyFuncId(_target,  _func);
        if (!emergencyFuncById[id]) {
            revert EmergencyCallNotExists(id);
        }

        // prepare data
        bytes memory data;
        if (bytes(_func).length > 0) {
            // data = func selector + _data
            data = abi.encodePacked(bytes4(keccak256(bytes(_func))), _data);
        } else {
            // call fallback with data
            data = _data;
        }

        // call target
        (bool ok, bytes memory res) = _target.call{value: _value}(data);
        if (!ok) {
            revert TxFailedError();
        }

        emit ExecuteEmergencyCall(id, _target, _value, _func, _data, block.timestamp);

        return res;
    }
}
