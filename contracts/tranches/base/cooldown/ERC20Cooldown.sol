// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICooldown, IERC20Cooldown } from "../../interfaces/cooldown/ICooldown.sol";
import { CooldownBase } from "./CooldownBase.sol";
/**
 * @title Strata Cooldown Vault for generic IERC20 tokens
 * @notice The Silo allows storing ERC20 tokens during the cooldown process.
 */
contract ERC20Cooldown is IERC20Cooldown, CooldownBase {

    struct TRequest {
        uint64 unlockAt;
        uint192 amount;
    }

    mapping(address token => mapping(address account => TRequest[] requests)) public activeRequests;
    mapping(address token => bool isCooldownDisabled) public cooldownDisabled;

    function transfer(IERC20 token, address initialFrom, address to, uint256 amount, uint256 cooldownSeconds) external onlyRole(COOLDOWN_WORKER_ROLE) {
        address worker = msg.sender;
        if (amount == 0) {
            return;
        }
        if (cooldownSeconds == 0) {
            SafeERC20.safeTransferFrom(token, worker, to, amount);
            emit Finalized(token, to, amount);
            return;
        }

        TRequest[] storage requests = activeRequests[address(token)][to];

        uint256 requestsCount = requests.length;
        if (initialFrom != to && requestsCount >= PUBLIC_REQUEST_SLOTS_CAP) {
            revert ExternalReceiverRequestLimitReached(token, initialFrom, to, amount);
        }

        uint64 unlockAt = uint64(block.timestamp + cooldownSeconds);
        if (requestsCount < MAX_ACTIVE_REQUEST_SLOTS) {
            if (requestsCount > 0 && requests[requestsCount - 1].unlockAt == unlockAt) {
                // is requested within current block
                TRequest storage last = requests[requestsCount - 1];
                last.amount += uint192(amount);
            } else {
                requests.push(TRequest(unlockAt, uint192(amount)));
            }
        } else {
            TRequest storage last = requests[requestsCount - 1];
            last.amount += uint192(amount);
            if (last.unlockAt < unlockAt) {
                last.unlockAt = unlockAt;
            }
        }

        SafeERC20.safeTransferFrom(token, worker, address(this), amount);
        emit TransferRequested(token, initialFrom, to, amount, unlockAt);
    }

    function finalize(IERC20 token, address user) external returns (uint256 claimed) {
        return finalize(token, user, block.timestamp);
    }
    function finalize(IERC20 token, address user, uint256 at) public returns (uint256 claimed) {
        if (at > block.timestamp) {
            revert InvalidTime();
        }
        TRequest[] storage requests = activeRequests[address(token)][user];
        bool isCooldownActive = cooldownDisabled[address(token)] == false;

        uint256 len = requests.length;
        for (uint256 i; i < len;) {
            TRequest memory req = requests[i];
            if (isCooldownActive && req.unlockAt > at) {
                // still pending
                unchecked { i++; }
                continue;
            }
            claimed += req.amount;

            if (i < len - 1) {
                requests[i] = requests[len - 1];
            }
            requests.pop();
            unchecked { len--; }
        }
        if (claimed == 0) {
            revert NothingToFinalize();
        }

        SafeERC20.safeTransfer(token, user, claimed);
        emit Finalized(token, user, claimed);
        return claimed;
    }

    function balanceOf (IERC20 token, address user) external view returns (ICooldown.TBalanceState memory) {
        return balanceOf(token, user, block.timestamp);
    }

    function balanceOf (IERC20 token, address user, uint256 at) public view returns (ICooldown.TBalanceState memory) {
        TRequest[] storage requests = activeRequests[address(token)][user];
        bool isCooldownActive = cooldownDisabled[address(token)] == false;

        uint256 l = requests.length;
        uint256 pending;
        uint256 claimable;
        uint256 nextUnlockAt;
        uint256 nextUnlockAmount;

        for (uint256 i; i < l; i++) {
            TRequest memory req = requests[i];
            if (isCooldownActive && req.unlockAt > at) {
                pending += req.amount;
                if (nextUnlockAt == 0 || req.unlockAt < nextUnlockAt) {
                    nextUnlockAt = req.unlockAt;
                    nextUnlockAmount = req.amount;
                    continue;
                }
                if (req.unlockAt == nextUnlockAt) {
                    nextUnlockAmount += req.amount;
                }
                continue;
            }
            claimable += req.amount;
        }
        return TBalanceState({
            pending: pending,
            claimable: claimable,
            nextUnlockAt: nextUnlockAt,
            nextUnlockAmount: nextUnlockAmount,
            totalRequests: l
        });
    }

    /**
    * @notice Toggles cooldown for a token, allowing immediate withdrawals in emergencies
    * @dev For emergency exits, cooldown worker (Strategy) can disable cooldowns
    * @param token The ERC20 token to set cooldown state
    * @param isCooldownDisabled True to disable cooldown, false to enable (default behavior)
    */
    function setCooldownDisabled(IERC20 token, bool isCooldownDisabled) external onlyRole(COOLDOWN_WORKER_ROLE) {
        cooldownDisabled[address(token)] = isCooldownDisabled;
    }

}
