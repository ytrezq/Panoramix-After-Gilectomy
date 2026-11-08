// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

contract PermissionedProxy {
    address admin;
    mapping (address => bool) public operators;
    mapping (bytes4 => bool) public permissionedCalls;
    address public pendingAdmin;

    constructor(address _admin, address _operator) {
        require(_admin != address(0), "zero");
        require(_operator != address(0), "zero");
        admin = _admin;
        operators[_operator] = true;
    }

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    function _onlyAdmin() internal view {
        require(msg.sender == admin, "PD");
    }

    modifier onlyOperator() {
        _onlyOperator();
        _;
    }

    function _onlyOperator() internal view {
        require(operators[msg.sender], "PD");
    }

    event AdminUpdated(address indexed admin);
    event OperatorUpdated(address indexed operator);
    event AddedPermissionedCall(bytes4 indexed sig);

    function transferAdminOwnerShip(address _newAdmin) external onlyAdmin {
        pendingAdmin = _newAdmin;
    }

    function acceptAdminOwnership() external {
        require(msg.sender == pendingAdmin, "PD");
        admin = pendingAdmin;
        pendingAdmin = address(0);
        emit AdminUpdated(admin);
    }

    function setOperator(address _operator, bool value) external onlyAdmin {
        require(_operator != address(0), "zero");
        operators[_operator] = value;
        emit OperatorUpdated(_operator);
    }

    function setPermissionedCall(bytes4 sig, bool value) external onlyAdmin {
        permissionedCalls[sig] = value;
        emit AddedPermissionedCall(sig);
    }

    function proxy(address vault, bytes memory data) external payable onlyOperator {
        bytes4 selector;
        require(data.length >= 4, "SEL");
        assembly {
          selector := mload(add(data, 32))
        }
        require(permissionedCalls[selector], "PD");

        (bool success, ) = vault.call{value: msg.value}(data);
        require(success, "failed");
    }
}
