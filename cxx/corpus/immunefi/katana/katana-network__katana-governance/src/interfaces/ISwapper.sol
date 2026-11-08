// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

interface ISwapper {
    error ActionsFailed();
    error NoBalanceChange();
    error ZeroAddress();
    error LengthMismatch();
    error PctTooBig();
    error RewardDistributorCallForbidden();

    /// @notice Emitted when `claimAndSwap` is executed.
    /// @param user The account that initiated the function.
    /// @param tokens The token addresses that will be claimed.
    /// @param claimAmounts The amounts that will be claimed.
    /// @param pct The percentage of total amount that goes to escrow.
    /// @param locked The tokenId that will be created on escrow with an amount.
    /// @param actions The array of actions executed.
    /// @param execResults The array with the results of the executed actions.
    event ClaimAndSwapped(
        address indexed user,
        address[] tokens,
        uint256[] claimAmounts,
        uint256 pct,
        Locked locked,
        Action[] actions,
        bytes[] execResults
    );

    struct Claim {
        address[] tokens;
        uint256[] amounts;
        bytes32[][] proofs;
    }

    struct Locked {
        uint256 tokenId;
        uint256 amount;
    }

    /// @notice Claims reward tokens and optionally swaps some/all to KAT, then locks a percentage.
    /// @dev Claims tokens from Merkle distributor, executes optional swaps to KAT, and locks % of
    ///      resulting KAT in escrow. Not all claimed tokens need to be swapped.
    /// @param _claim Tokens to claim with amounts and Merkle proofs
    /// @param _actions Swap actions to execute (optional, can be partial)
    /// @param _pct Percentage (0-100) of KAT to lock in escrow
    /// @return tokenAmountGained Total KAT gained from claims and swaps
    /// @return tokenId Escrow lock NFT ID if _pct > 0, else 0
    function claimAndSwap(
        Claim calldata _claim,
        Action[] calldata _actions,
        uint256 _pct
    )
        external
        payable
        returns (uint256 tokenAmountGained, uint256 tokenId);
}
