// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Address }       from "../lib/openzeppelin/contracts/utils/Address.sol";
import { EnumerableSet } from "../lib/openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IAdministeredAgent } from "./interfaces/IAdministeredAgent.sol";

contract AdministeredAgent is IAdministeredAgent {

    using EnumerableSet for EnumerableSet.AddressSet;

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    EnumerableSet.AddressSet internal _actors;
    EnumerableSet.AddressSet internal _admins;
    EnumerableSet.AddressSet internal _grantors;
    EnumerableSet.AddressSet internal _revokers;

    /**********************************************************************************************/
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

    modifier onlyActor {
        require(_actors.contains(msg.sender), NotActor());
        _;
    }

    modifier onlyAdmin {
        require(_admins.contains(msg.sender), NotAdmin());
        _;
    }

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address admin) {
        _addAdmin(admin);
    }

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function addAdmin(address account) external override onlyAdmin {
        _addAdmin(account);
    }

    function removeAdmin(address account) external override onlyAdmin {
        require(_admins.remove(account), AccountNotAdmin());
        require(_admins.length() > 0,    NoAdminsRemaining());

        emit AdminRemoved(account, msg.sender);
    }

    function addGrantor(address account) external override onlyAdmin {
        require(account != address(0),  ZeroAccount());
        require(_grantors.add(account), AccountAlreadyGrantor());

        emit GrantorAdded(account, msg.sender);
    }

    function removeGrantor(address account) external override onlyAdmin {
        require(_grantors.remove(account), AccountNotGrantor());

        emit GrantorRemoved(account, msg.sender);
    }

    function addRevoker(address account) external override onlyAdmin {
        require(account != address(0),  ZeroAccount());
        require(_revokers.add(account), AccountAlreadyRevoker());

        emit RevokerAdded(account, msg.sender);
    }

    function removeRevoker(address account) external override onlyAdmin {
        require(_revokers.remove(account), AccountNotRevoker());

        emit RevokerRemoved(account, msg.sender);
    }

    /**********************************************************************************************/
    /*** External Interactive Grantor/Revoker Functions                                         ***/
    /**********************************************************************************************/

    function addActor(address account) external override {
        require(_admins.contains(msg.sender) || _grantors.contains(msg.sender), NotGrantor());

        require(account != address(0), ZeroAccount());
        require(_actors.add(account),  AccountAlreadyActor());

        emit ActorAdded(account, msg.sender);
    }

    function removeActor(address account) external override {
        require(_admins.contains(msg.sender) || _revokers.contains(msg.sender), NotRevoker());

        require(_actors.remove(account), AccountNotActor());

        emit ActorRemoved(account, msg.sender);
    }

    /**********************************************************************************************/
    /*** External Interactive Actor Functions                                                   ***/
    /**********************************************************************************************/

    function call(address target, bytes memory data)
        external
        payable
        override
        onlyActor
        returns (bytes memory result)
    {
        require(target != address(this), InvalidTarget());

        result = Address.functionCallWithValue(target, data, msg.value);
    }

    function batchCall(address[] memory targets, bytes[] memory data, uint256[] memory values)
        external
        payable
        override
        onlyActor
        returns (bytes[] memory results)
    {
        require(
            targets.length == data.length && targets.length == values.length,
            MismatchedArrayLengths()
        );

        results = new bytes[](targets.length);

        for (uint256 i = 0; i < targets.length; ++i) {
            require(targets[i] != address(this), InvalidTarget());

            results[i] = Address.functionCallWithValue(targets[i], data[i], values[i]);
        }
    }

    function sendValue(address target, uint256 value) external payable override onlyActor {
        Address.sendValue(payable(target), value);
    }

    /**********************************************************************************************/
    /*** External Variable Getters                                                              ***/
    /**********************************************************************************************/

    function adminCount() external view override returns (uint256) {
        return _admins.length();
    }

    function actorCount() external view override returns (uint256) {
        return _actors.length();
    }

    function grantorCount() external view override returns (uint256) {
        return _grantors.length();
    }

    function revokerCount() external view override returns (uint256) {
        return _revokers.length();
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function getAdmin(uint256 index) external view override returns (address) {
        return _admins.at(index);
    }

    function getActor(uint256 index) external view override returns (address) {
        return _actors.at(index);
    }

    function getGrantor(uint256 index) external view override returns (address) {
        return _grantors.at(index);
    }

    function getRevoker(uint256 index) external view override returns (address) {
        return _revokers.at(index);
    }

    function getIsAdmin(address account) external view override returns (bool) {
        return _admins.contains(account);
    }

    function getIsActor(address account) external view override returns (bool) {
        return _actors.contains(account);
    }

    function getIsGrantor(address account) external view override returns (bool) {
        return _grantors.contains(account);
    }

    function getIsRevoker(address account) external view override returns (bool) {
        return _revokers.contains(account);
    }

    /**********************************************************************************************/
    /*** Receive Function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable {}

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _addAdmin(address account) internal {
        require(account != address(0), ZeroAccount());
        require(_admins.add(account),  AccountAlreadyAdmin());

        emit AdminAdded(account, msg.sender);
    }

}
