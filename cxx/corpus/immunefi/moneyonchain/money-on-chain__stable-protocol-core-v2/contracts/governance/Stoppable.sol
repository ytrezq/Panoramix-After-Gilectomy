// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { Governed } from "./Governed.sol";

/**
 * @title Stoppable
 * @notice Allow a contract to be paused through the stopper subsystem. This contracts
 * is able to disable the stoppability feature through governance.
 * @dev This contract was heavily based on the _Pausable_ contract of openzeppelin-eth but
 * it was modified in order to being able to turn on and off its stoppability
 */
abstract contract Stoppable is Governed {
    event Paused(address account);
    event Unpaused(address account);

    bool public stoppable;
    bool private _paused;
    address public pauser;

    // ------- Custom Errors -------
    error Unstoppable();
    error OnlyWhilePaused();
    error NotWhenPaused();
    error OnlyPauser();

    /**
     * @notice Modifier to make a function callable only when the contract is not paused
     */
    modifier notPaused() {
        _checkNotPaused();
        _;
    }

    /**
     * @notice Modifier to make a function callable only when the contract is paused
     */
    modifier onlyPaused() {
        if (!_paused) revert OnlyWhilePaused();
        _;
    }

    /**
     * @notice Initialize the contract with the basic settings
     * @dev This initialize replaces the constructor but it is not called automatically.
     * It is necessary because of the upgradeability of the contracts. Either this function or the previous can be used
     * @param pauserAddress_ The address that is authorized to pause this contract
     * @param stoppable_ Define if the contract starts being unstoppable or not
     */
    function __Stoppable_init_unchained(address pauserAddress_, bool stoppable_) internal onlyInitializing {
        stoppable = stoppable_;
        pauser = pauserAddress_;
    }

    /**
     * @dev reverts with NotWhenPaused when _paused
     */
    function _checkNotPaused() internal view {
        if (_paused) revert NotWhenPaused();
    }

    /**
     * @notice Returns true if paused
     */
    function paused() external view returns (bool) {
        return _paused;
    }

    /**
     * @notice Called by the owner to pause, triggers stopped state
     * @dev Should only be called by the pauser and when it is stoppable
     */
    function pause() external notPaused {
        if (msg.sender != pauser) revert OnlyPauser();
        if (!stoppable) revert Unstoppable();
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Called by the owner to unpause, returns to normal state
     * @dev Should only be called by the pauser and when it is stoppable
     */
    function unpause() external onlyPaused {
        if (msg.sender != pauser && !governor.isAuthorizedChanger(msg.sender)) revert OnlyPauser();
        if (!stoppable) revert Unstoppable();
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Switches OFF the stoppability of the contract. It cannot be paused or unpaused
     * Doesn't change the pause state, if the contract was already paused it cannot be operated
     * @dev Should be called through governance
     */
    function makeUnstoppable() external onlyAuthorizedChanger {
        stoppable = false;
    }

    /**
     * @notice Switches ON the stoppability of the contract. It can be paused or unpaused
     *  Doesn't change the pause state, if the contract was already paused it cannot be operated
     * @dev Should be called through governance
     */
    function makeStoppable() external onlyAuthorizedChanger {
        stoppable = true;
    }

    /**
     * @notice Changes the address which is enable to pause this contract
     * @param newPauser_ Address of the new pauser
     * @dev Should be called through governance
     */
    function setPauser(address newPauser_) external onlyAuthorizedChanger {
        // slither-disable-next-line missing-zero-check
        pauser = newPauser_;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */

    // Purposely left unused to save some state space to allow for future upgrades
    // slither-disable-next-line unused-state
    uint256[50] private __gap;
}
