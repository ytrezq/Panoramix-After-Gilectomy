// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICooldown {
     struct TBalanceState {
        uint256 pending;
        uint256 claimable;
        uint256 nextUnlockAt;
        uint256 nextUnlockAmount;
        uint256 totalRequests;
    }

    event TransferRequested(IERC20 indexed token, address indexed from, address indexed to, uint256 amount, uint256 unlockAt);
    event Finalized(IERC20 indexed token, address indexed user, uint256 amount);

    error InvalidTime ();
    error UnsupportedToken(address token);
    error NothingToFinalize ();
    error ExternalReceiverRequestLimitReached(IERC20 token, address from, address to, uint256 amount);

    function finalize(IERC20 token, address user) external returns (uint256 claimed);
    function finalize(IERC20 token, address user, uint256 at) external returns (uint256 claimed);

    function balanceOf (IERC20 token, address user) external view returns (TBalanceState memory);
    function balanceOf (IERC20 token, address user, uint256 at) external view returns (TBalanceState memory);
}


interface IERC20Cooldown is ICooldown {
    function transfer(IERC20 token, address initialFrom, address to, uint256 amount, uint256 cooldownSeconds) external;
    function setCooldownDisabled(IERC20 token, bool isCooldownDisabled) external;
}

interface IUnstakeCooldown is ICooldown {
    function transfer(IERC20 token, address initialFrom, address to, uint256 amount) external;
}
