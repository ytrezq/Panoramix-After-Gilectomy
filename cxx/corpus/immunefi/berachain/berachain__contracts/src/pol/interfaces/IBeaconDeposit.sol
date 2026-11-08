// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPOLErrors } from "./IPOLErrors.sol";

/// @title IBeaconDeposit
/// @author Berachain Team.
interface IBeaconDeposit is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        EVENTS                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Emitted when a deposit is made, which could mean a new validator or a top up of an existing one.
     * @param pubkey the public key of the validator.
     * @param credentials is the withdrawal credentials of the validator.
     * @param amount the amount of stake being deposited, in Gwei.
     * @param signature the signature of the deposit message.
     * @param index the index of the deposit.
     */
    event Deposit(bytes pubkey, bytes credentials, uint64 amount, bytes signature, uint64 index);

    /**
     * @notice Emitted when the operator change of a validator is queued.
     * @param pubkey The pubkey of the validator.
     * @param queuedOperator The new queued operator address.
     * @param currentOperator The current operator address.
     * @param queuedTimestamp The timestamp when the change was queued.
     */
    event OperatorChangeQueued(
        bytes indexed pubkey, address queuedOperator, address currentOperator, uint256 queuedTimestamp
    );

    /**
     * @notice Emitted when the operator change of a validator is cancelled.
     * @param pubkey The pubkey of the validator.
     */
    event OperatorChangeCancelled(bytes indexed pubkey);

    /**
     * @notice Emitted when the operator of a validator is updated.
     * @param pubkey The pubkey of the validator.
     * @param newOperator The new operator address.
     * @param previousOperator The previous operator address.
     */
    event OperatorUpdated(bytes indexed pubkey, address newOperator, address previousOperator);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            VIEWS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Get the operator address for a given pubkey.
     * @dev Returns zero address if the pubkey is not registered.
     * @param pubkey The pubkey of the validator.
     * @return The operator address for the given pubkey.
     */
    function getOperator(bytes calldata pubkey) external view returns (address);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            WRITES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Submit a deposit message to the Beaconchain.
     * @notice This will be used to create a new validator or to top up an existing one, increasing stake.
     * @param pubkey is the consensus public key of the validator.
     * @param credentials is the withdrawal credentials of the validator.
     * @param signature is the signature used only on the first deposit.
     * @param operator is the address of the operator used for `POL` mechanics.
     * @dev emits the Deposit event upon successful deposit.
     * @dev Reverts if the operator is already set and caller passed non-zero operator.
     */
    function deposit(
        bytes calldata pubkey,
        bytes calldata credentials,
        bytes calldata signature,
        address operator
    )
        external
        payable;

    /**
     * @notice Request to change the operator of a validator.
     * @dev Only the current operator can request a change.
     * @param pubkey The pubkey of the validator.
     * @param newOperator The new operator address.
     */
    function requestOperatorChange(bytes calldata pubkey, address newOperator) external;

    /**
     * @notice Cancel the operator change of a validator.
     * @dev Only the current operator can cancel the change.
     * @param pubkey The pubkey of the validator.
     */
    function cancelOperatorChange(bytes calldata pubkey) external;

    /**
     * @notice Accept the operator change of a validator.
     * @dev Only the new operator can accept the change.
     * @dev Reverts if the queue delay has not passed.
     * @param pubkey The pubkey of the validator.
     */
    function acceptOperatorChange(bytes calldata pubkey) external;
}
