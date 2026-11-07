// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

/**
 * @title  IAdministeredAgent
 * @notice Administered actor that can take on any role within the PAU system, with dedicated
 *         admins, grantors, and revokers.
 */
interface IAdministeredAgent {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when an actor is added.
     * @param  account The account that was added as an actor.
     * @param  caller  The caller that added the actor.
     */
    event ActorAdded(address indexed account, address indexed caller);

    /**
     * @notice Emitted when an actor is removed.
     * @param  account The account that was removed as an actor.
     * @param  caller  The caller that removed the actor.
     */
    event ActorRemoved(address indexed account, address indexed caller);

    /**
     * @notice Emitted when an admin is added.
     * @param  account The account that was added as an admin.
     * @param  caller  The caller that added the admin.
     */
    event AdminAdded(address indexed account, address indexed caller);

    /**
     * @notice Emitted when an admin is removed.
     * @param  account The account that was removed as an admin.
     * @param  caller  The caller that removed the admin.
     */
    event AdminRemoved(address indexed account, address indexed caller);

    /**
     * @notice Emitted when a grantor is added.
     * @param  account The account that was added as a grantor.
     * @param  caller  The caller that added the grantor.
     */
    event GrantorAdded(address indexed account, address indexed caller);

    /**
     * @notice Emitted when a grantor is removed.
     * @param  account The account that was removed as a grantor.
     * @param  caller  The caller that removed the grantor.
     */
    event GrantorRemoved(address indexed account, address indexed caller);

    /**
     * @notice Emitted when a revoker is added.
     * @param  account The account that was added as a revoker.
     * @param  caller  The caller that added the revoker.
     */
    event RevokerAdded(address indexed account, address indexed caller);

    /**
     * @notice Emitted when a revoker is removed.
     * @param  account The account that was removed as a revoker.
     * @param  caller  The caller that removed the revoker.
     */
    event RevokerRemoved(address indexed account, address indexed caller);

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when the account argument is already an actor.
    error AccountAlreadyActor();

    /// @notice Thrown when the account argument is already an admin.
    error AccountAlreadyAdmin();

    /// @notice Thrown when the account argument is already a grantor.
    error AccountAlreadyGrantor();

    /// @notice Thrown when the account argument is already a revoker.
    error AccountAlreadyRevoker();

    /// @notice Thrown when the account argument is not an actor.
    error AccountNotActor();

    /// @notice Thrown when the account argument is not an admin.
    error AccountNotAdmin();

    /// @notice Thrown when the account argument is not a grantor.
    error AccountNotGrantor();

    /// @notice Thrown when the account argument is not a revoker.
    error AccountNotRevoker();

    /// @notice Thrown when the call target is the agent itself.
    error InvalidTarget();

    /// @notice Thrown when the array lengths are mismatched.
    error MismatchedArrayLengths();

    /// @notice Thrown when there are no admins remaining.
    error NoAdminsRemaining();

    /// @notice Thrown when the caller is not an actor.
    error NotActor();

    /// @notice Thrown when the caller is not an admin.
    error NotAdmin();

    /// @notice Thrown when the caller is not a grantor.
    error NotGrantor();

    /// @notice Thrown when the caller is not a revoker.
    error NotRevoker();

    /// @notice Thrown when the account argument is the zero address.
    error ZeroAccount();

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Adds an account as an actor.
     * @param  account The account to add as an actor.
     */
    function addActor(address account) external;

    /**
     * @notice Adds an account as an admin.
     * @param  account The account to add as an admin.
     */
    function addAdmin(address account) external;

    /**
     * @notice Adds an account as a grantor.
     * @param  account The account to add as a grantor.
     */
    function addGrantor(address account) external;

    /**
     * @notice Adds an account as a revoker.
     * @param  account The account to add as a revoker.
     */
    function addRevoker(address account) external;

    /**
     * @notice Calls a batch of target contracts with data and values.
     * @param  targets The target contracts to call.
     * @param  data    The data to call the target contracts with.
     * @param  values  The values to call the target contracts with.
     * @return results The respective results of the calls.
     */
    function batchCall(address[] memory targets, bytes[] memory data, uint256[] memory values)
        external
        payable
        returns (bytes[] memory results);

    /**
     * @notice Calls a target contract with data.
     * @param  target The target contract to call.
     * @param  data   The data to call the target contract with.
     * @return result The result of the call.
     */
    function call(address target, bytes memory data) external payable returns (bytes memory result);

    /**
     * @notice Removes an account as an actor.
     * @param  account The account to remove as an actor.
     */
    function removeActor(address account) external;

    /**
     * @notice Removes an account as an admin.
     * @param  account The account to remove as an admin.
     */
    function removeAdmin(address account) external;

    /**
     * @notice Removes an account as a grantor.
     * @param  account The account to remove as a grantor.
     */
    function removeGrantor(address account) external;

    /**
     * @notice Removes an account as a revoker.
     * @param  account The account to remove as a revoker.
     */
    function removeRevoker(address account) external;

    /**
     * @notice Sends a value to a target contract.
     * @param  target The target contract to send the value to.
     * @param  value  The value to send to the target contract.
     */
    function sendValue(address target, uint256 value) external payable;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Returns the number of actors.
    function actorCount() external view returns (uint256);

    /// @notice Returns the number of admins.
    function adminCount() external view returns (uint256);

    /// @notice Returns the number of grantors.
    function grantorCount() external view returns (uint256);

    /// @notice Returns the number of revokers.
    function revokerCount() external view returns (uint256);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns an actor at a given index.
     * @param  index The index of the actor to return.
     * @return actor The actor at the given index.
     */
    function getActor(uint256 index) external view returns (address actor);

    /**
     * @notice Returns an admin at a given index.
     * @param  index The index of the admin to return.
     * @return admin The admin at the given index.
     */
    function getAdmin(uint256 index) external view returns (address admin);

    /**
     * @notice Returns a grantor at a given index.
     * @param  index   The index of the grantor to return.
     * @return grantor The grantor at the given index.
     */
    function getGrantor(uint256 index) external view returns (address grantor);

    /**
     * @notice Returns a revoker at a given index.
     * @param  index   The index of the revoker to return.
     * @return revoker The revoker at the given index.
     */
    function getRevoker(uint256 index) external view returns (address revoker);

    /**
     * @notice Returns true if the account is an actor.
     * @param  account The account to check if it is an actor.
     * @return isActor True if the account is an actor, false otherwise.
     */
    function getIsActor(address account) external view returns (bool isActor);

    /**
     * @notice Returns true if the account is an admin.
     * @param  account The account to check if it is an admin.
     * @return isAdmin True if the account is an admin, false otherwise.
     */
    function getIsAdmin(address account) external view returns (bool isAdmin);

    /**
     * @notice Returns true if the account is a grantor.
     * @param  account   The account to check if it is a grantor.
     * @return isGrantor True if the account is a grantor, false otherwise.
     */
    function getIsGrantor(address account) external view returns (bool isGrantor);

    /**
     * @notice Returns true if the account is a revoker.
     * @param  account   The account to check if it is a revoker.
     * @return isRevoker True if the account is a revoker, false otherwise.
     */
    function getIsRevoker(address account) external view returns (bool isRevoker);

}
