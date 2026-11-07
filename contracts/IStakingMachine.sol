// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import {IERC20} from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import {IDelayMachine} from "./IDelayMachine.sol";
import {IOracleManager} from "./IOracleManager.sol";

interface IStakingMachine {
    /// @notice Used by the voting machine to lock the current balance of MOCs.
    /// @param mocHolder the moc holder whose mocs will be locked.
    /// @param untilTimestamp timestamp until which the mocs will be locked.
    function lockMocs(address mocHolder, uint256 untilTimestamp) external;

    /// @notice Accept a deposit from an account.
    /// Delegate to the Supporters smart contract.
    /// @param mocs token quantity
    function deposit(uint256 mocs) external;

    /// @notice Accept a deposit from an account.
    /// Delegate to the Supporters smart contract.
    /// @param mocs token quantity
    /// @param destination must be always msg.sender.
    function deposit(uint256 mocs, address destination) external;

    /// @notice Accept a deposit from an account, can be only called by the delayMachine    .
    /// @param mocs token quantity
    /// @param destination the destination account of this deposit.
    /// @param source the address that approved the transfer
    function depositFrom(uint256 mocs, address destination, address source) external;

    /// @notice Withdraw stake, send it to the delay machine.
    /// @param mocs token quantity
    function withdraw(uint256 mocs) external;

    /// @notice Withdraw all the stake and send it to the delay machine.
    function withdrawAll() external;

    /// @notice Reports the balance of MOCs for a specific user.
    /// @param user user address
    function getBalance(address user) external view returns (uint256);

    /// @notice Reports the balance of tokens for a specific user.
    /// @param user user address
    function getTokenBalance(address user) external view returns (uint256);

    /// @notice Reports the locked balance of MOCs for a specific user.
    /// @param user user address
    function getLockedBalance(address user) external view returns (uint256);

    /// @notice Reports the balance of locked MOCs for a specific user.
    /// Delegates to the Supporters smart contract.
    /// @param user user address
    /// @return amount the amount of mocs locked
    /// @return untilTimestamp the timestamp that corresponds to the locking date.
    function getLockingInfo(address user) external view returns (uint256 amount, uint256 untilTimestamp);

    // Public variable
    function getSupporters() external view returns (address);

    // Public variable
    function getOracleManager() external view returns (IOracleManager);

    // Public variable
    function getMocToken() external view returns (IERC20);

    // Public variable
    function getDelayMachine() external view returns (IDelayMachine);

    // Public variable
    function getWithdrawLockTime() external view returns (uint256);
}

interface IStakingMachineOracles {
    /// @notice Register an oracle
    /// @param oracleAddr address of the oracle (from which we publish prices)
    /// @param url url used by the oracle server
    function registerOracle(address oracleAddr, string calldata url) external;

    /// @notice Change the oracle "internet" name (URI)
    /// @param url The new url to set.
    function setOracleName(string calldata url) external;

    /// @notice Change the oracle address
    /// @param oracleAddr The new oracle address
    function setOracleAddress(address oracleAddr) external;

    /// @notice Return true if the oracle is registered.
    /// @param oracleAddr addr The address of the Oracle check for.
    function isOracleRegistered(address oracleAddr) external view returns (bool);

    /// @notice Returns true if an oracle satisfies conditions to be removed from system.
    /// @param oracleAddr the oracle address to lookup.
    function canRemoveOracle(address oracleAddr) external view returns (bool);

    /// @notice Remove an oracle.
    function removeOracle() external;

    /// @notice Returns the count of registered coin pairs.
    /// Keep in mind that Deleted coin-pairs will contain zeroed addresses.
    function getCoinPairCount() external view returns (uint256);

    /// @notice Returns the coin pair at index.
    /// @param i index to query.
    function getCoinPairAtIndex(uint256 i) external view returns (bytes32);

    /// @notice Return the contract address for a specified registered coin pair.
    /// @param coinpair Coin-pair string to lookup (e.g: BTCUSD)
    /// @return address Address of contract or zero if does not exist or was deleted.
    function getContractAddress(bytes32 coinpair) external view returns (address);

    /// @notice Searches a coinpair in coinPairList
    /// @param coinPair The bytes32-encoded coinpair string (e.g. BTCUSD)
    /// @param hint Optional hint to start traversing the coinPairList array, zero is to search all the array.
    function getCoinPairIndex(bytes32 coinPair, uint256 hint) external view returns (uint256);

    /// @notice Subscribe an oracle to a coin pair.
    /// @param coinPair coin pair to subscribe, for example BTCUSD
    function subscribeToCoinPair(bytes32 coinPair) external;

    /// @notice Unsubscribe an oracle from a coin pair.
    /// @param coinPair coin pair to unsubscribe, for example BTCUSD
    function unSubscribeFromCoinPair(bytes32 coinPair) external;

    /// @notice Returns true if an oracle is subscribed to a coin pair
    /// @param oracleAddr address of the oracle
    /// @param coinPair coin pair to unsubscribe, for example BTCUSD
    function isSubscribed(address oracleAddr, bytes32 coinPair) external view returns (bool);

    /// @notice Returns the amount of owners registered.
    /// Delegates to the Oracle Manager smart contract.
    function getRegisteredOraclesLen() external view returns (uint256);

    /// @notice Returns the oracle name and address at index.
    /// Delegates to the Oracle Manager smart contract.
    /// @param idx index to query.
    function getRegisteredOracleAtIndex(
        uint256 idx
    ) external view returns (address ownerAddr, address oracleAddr, string memory url);
}
