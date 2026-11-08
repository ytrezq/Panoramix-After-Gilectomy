// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { VotingEscrowV1_2_0 as Escrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import { ISwapper } from "src/interfaces/ISwapper.sol";
import { IRewardsDistributor } from "src/interfaces/IRewardsDistributor.sol";

contract Swapper is ISwapper, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    /// @notice Basis points for percentage calculations (100% = 10000 basis points)
    uint256 private constant BASIS_POINTS = 10_000;

    /// @notice The address of the rewards distributor where swapper can claim tokens.
    address public immutable rewardDistributor;

    /// @notice The escrow contract address
    Escrow public immutable escrow;

    /// @notice The ERC20 token address escrow uses
    IERC20 public immutable escrowToken;

    constructor(address _rewardDistributor, address _escrow) {
        rewardDistributor = _rewardDistributor;
        escrow = Escrow(_escrow);
        escrowToken = IERC20(escrow.token());
    }

    receive() external payable { }

    /// @inheritdoc ISwapper
    function claimAndSwap(
        Claim calldata _claim,
        Action[] calldata _actions,
        uint256 _pct
    )
        public
        payable
        virtual
        nonReentrant
        returns (uint256 tokenAmountGained, uint256 tokenId)
    {
        // make sure percentage is never more than 100% (10000 basis points).
        if (_pct > BASIS_POINTS) {
            revert PctTooBig();
        }

        address[] memory users = new address[](_claim.tokens.length);
        for (uint256 i = 0; i < _claim.tokens.length; i++) {
            users[i] = msg.sender;
        }

        // If `_tokens`, `_amounts` and `_proofs` have incorrect size, below reverts.
        // The `user` must have set this contract as a recipient
        // for the `token` prior to calling this.
        // At this point, this contract holds balances on `_tokens`.
        IRewardsDistributor(rewardDistributor).claim(users, _claim.tokens, _claim.amounts, _claim.proofs);

        bytes[] memory execResults = _executeActions(_actions);

        // Actions may swap claimed tokens to KAT. Only KAT balance on this contract
        // determines compounding amount; other tokens are handled by actions directly.
        tokenAmountGained = escrowToken.balanceOf(address(this));
        Locked memory lock;
        if (tokenAmountGained > 0) {
            lock = _compoundEscrowToken(_pct, tokenAmountGained);
        }

        // send any remaining eth to the sender.
        _withdrawNative();

        emit ClaimAndSwapped(msg.sender, _claim.tokens, _claim.amounts, _pct, lock, _actions, execResults);

        return (tokenAmountGained, lock.tokenId);
    }

    function _compoundEscrowToken(
        uint256 _pct,
        uint256 _tokenAmountGained
    )
        internal
        virtual
        returns (Locked memory lock)
    {
        // If tokenAmountGained > 0, then kat token balance was increased on this contract.
        // If pct > 0, create a lock with percentage and send rest to sender.
        // If pct = 0, send whole amount to sender.
        uint256 remaining = _tokenAmountGained;
        if (_pct > 0) {
            // If _tokenAmountGained or _pct is too small, lock.amount may fall
            // below escrow’s minDeposit and fail. Failing early avoids confusion.
            // otherwise, the user might expect a partial lock while all funds return.
            // User can retry with a higher _pct for a valid lock.
            lock.amount = (_tokenAmountGained * _pct) / BASIS_POINTS;
            remaining = _tokenAmountGained - lock.amount;

            // approve should not revert even for non-compliant ERC20s as
            // it only approves the exact amount that will be transfered
            // from this contract, automatically setting allowance back to 0.
            // we trust that escrow's createLockFor will transfer the whole lock.amount.
            escrowToken.approve(address(escrow), lock.amount);
            lock.tokenId = escrow.createLockFor(lock.amount, msg.sender);
        }

        if (remaining > 0) {
            escrowToken.safeTransfer(msg.sender, remaining);
        }
    }

    /// @notice Internal helper function to execute user actions and return execution results.
    function _executeActions(Action[] memory _actions) internal virtual returns (bytes[] memory execResults) {
        uint256 len = _actions.length;

        if (len == 0) return execResults;

        // If there're actions, execute them and record
        // the execution result data for each.
        execResults = new bytes[](len);
        for (uint256 i = 0; i < len; i++) {
            address target = _actions[i].to;
            // For extra safety measures, don't allow actions to call rewardsDistributor
            // Prior this, claim is already called on it which should be enough.
            if (target == rewardDistributor) {
                revert RewardDistributorCallForbidden();
            }

            (bool success, bytes memory returnData) = target.call{ value: _actions[i].value }(_actions[i].data);
            execResults[i] = returnData;
            target.verifyCallResultFromTarget(success, returnData, "ActionFailed");
        }
    }

    /// @notice If there is any eth, transfer to the sender.
    /// @dev If sender is a contract and doesn't have receive/fallback,
    ///      eth stays in swapper and next user can withdraw.
    function _withdrawNative() internal virtual {
        msg.sender.call{ value: address(this).balance }("");
    }
}
