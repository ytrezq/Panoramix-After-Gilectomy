// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "./EventUtils.sol";

interface ICallbackReceiver {
    // @dev there is a limit on the number of fields a struct can have when being passed
    // or returned as a memory variable which can cause "Stack too deep" errors
    // use sub-structs to avoid this issue
    // @param addresses address values
    // @param numbers number values
    // @param flags boolean values
    struct DepositProps {
        DepositAddresses addresses;
        DepositNumbers numbers;
        Flags flags;
    }

    // @dev there is a limit on the number of fields a struct can have when being passed
    // or returned as a memory variable which can cause "Stack too deep" errors
    // use sub-structs to avoid this issue
    // @param addresses address values
    // @param numbers number values
    // @param flags boolean values
    struct WithdrawalProps {
        WithdrawalAddresses addresses;
        WithdrawalNumbers numbers;
        Flags flags;
    }

    // @param account the account depositing liquidity
    // @param receiver the address to send the liquidity tokens to
    // @param callbackContract the callback contract
    // @param uiFeeReceiver the ui fee receiver
    // @param market the market to deposit to
    struct DepositAddresses {
        address account;
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialLongToken;
        address initialShortToken;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
    }

    // @param initialLongTokenAmount the amount of long tokens to deposit
    // @param initialShortTokenAmount the amount of short tokens to deposit
    // @param minMarketTokens the minimum acceptable number of liquidity tokens
    // @param updatedAtBlock the block that the deposit was last updated at
    // sending funds back to the user in case the deposit gets cancelled
    // @param executionFee the execution fee for keepers
    // @param callbackGasLimit the gas limit for the callbackContract
    struct DepositNumbers {
        uint256 initialLongTokenAmount;
        uint256 initialShortTokenAmount;
        uint256 minMarketTokens;
        uint256 updatedAtBlock;
        uint256 updatedAtTime;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }

    // @param account The account to withdraw for.
    // @param receiver The address that will receive the withdrawn tokens.
    // @param callbackContract The contract that will be called back.
    // @param uiFeeReceiver The ui fee receiver.
    // @param market The market on which the withdrawal will be executed.
    struct WithdrawalAddresses {
        address account;
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
    }

    // @param marketTokenAmount The amount of market tokens that will be withdrawn.
    // @param minLongTokenAmount The minimum amount of long tokens that must be withdrawn.
    // @param minShortTokenAmount The minimum amount of short tokens that must be withdrawn.
    // @param updatedAtBlock The block at which the withdrawal was last updated.
    // @param executionFee The execution fee for the withdrawal.
    // @param callbackGasLimit The gas limit for calling the callback contract.
    struct WithdrawalNumbers {
        uint256 marketTokenAmount;
        uint256 minLongTokenAmount;
        uint256 minShortTokenAmount;
        uint256 updatedAtBlock;
        uint256 updatedAtTime;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }

    // @param shouldUnwrapNativeToken whether to unwrap the native token when
    struct Flags {
        bool shouldUnwrapNativeToken;
    }
    // @dev called after a deposit execution
    // @param key the key of the deposit
    // @param deposit the deposit that was executed
    function afterDepositExecution(bytes32 key, DepositProps memory deposit, EventUtils.EventLogData memory eventData) external;

    // @dev called after a deposit cancellation
    // @param key the key of the deposit
    // @param deposit the deposit that was cancelled
    function afterDepositCancellation(bytes32 key, DepositProps memory deposit, EventUtils.EventLogData memory eventData) external;

    // @dev called after a withdrawal execution
    // @param key the key of the withdrawal
    // @param withdrawal the withdrawal that was executed
    function afterWithdrawalExecution(bytes32 key, WithdrawalProps memory withdrawal, EventUtils.EventLogData memory eventData) external;

    // @dev called after a withdrawal cancellation
    // @param key the key of the withdrawal
    // @param withdrawal the withdrawal that was cancelled
    function afterWithdrawalCancellation(bytes32 key, WithdrawalProps memory withdrawal, EventUtils.EventLogData memory eventData) external;
}