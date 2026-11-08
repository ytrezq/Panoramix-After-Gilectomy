// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ITranche } from "../ITranche.sol";
import { ICooldown } from "./ICooldown.sol";
import { IStrataCDO } from "../IStrataCDO.sol";

interface ISharesCooldown is ICooldown {

    struct TRequest {
        uint64 unlockAt;
        uint192 shares;
        address token;
    }
    struct TClaimableToken {
        address token;
        uint256 shares;
    }

    struct TExitParams {
        uint32 feePpm;
        uint32 sharesLock;
    }

    /// @notice Defines exit mode upper bounds for coverage-based fee and lockup parameters.
    /// @dev Structure is gas and storage optimized by packing all fields into a single 256-bit slot.
    ///      Coverage ratios (p0, p1) and exit parameters (r0, r1, r2) are stored as uint32 values.
    ///      The coverage ratio determines which range applies:
    ///      - coverage < p0: use r0 (typically highest fees/longest locks)
    ///      - p0 <= coverage < p1: use r1 (typically medium fees/locks)
    ///      - coverage >= p1: use r2 (lowest fees/shortest locks, typically zero)
    /// @param p0 First breakpoint in parts per million (upper bound for range0)
    /// @param p1 Second breakpoint in parts per million (upper bound for range1)
    /// @param r0 Exit parameters (fee in ppm, shares lock in seconds) for coverage < p0
    /// @param r1 Exit parameters for p0 <= coverage < p1
    /// @param r2 Exit parameters for coverage >= p1 (default)
    struct TExitUpperBounds {
        uint32 p0;
        uint32 p1;
        TExitParams r0;
        TExitParams r1;
        TExitParams r2;
    }

    struct TFinalizeWithFeeGuard {
        uint192 shares;
        uint256 daysLeft;
    }
    struct TCancelGuard {
        uint192 shares;
    }


    event VaultCooldownUpdated(address indexed vault, uint256 cooldownSeconds);
    event RequestCanceled(address indexed vault, address user, uint256 shares);
    event RequestedCooldown(address indexed vault, address token, address initialFrom, address to, uint256 shares, uint64 unlockAt);
    event VaultCooldownBoundsUpdated(address indexed vault,TExitUpperBounds bounds);
    event VaultEarlyExitFeeSet(address indexed vault, uint256 earlyExitFee);
    event ExitFeeAccrued(address indexed vault, address user, uint256 sharesFee, uint256 sharesUser);

    function finalize(ITranche vault, address token, address user) external returns (uint256 claimed);
    function finalize(ITranche vault, address token, address user, uint256 at) external returns (uint256 claimed);
    function finalizeWithFee(ITranche vault, address token, address user, uint256 i, TFinalizeWithFeeGuard calldata guard) external returns (uint256 claimed);
    function cancel(IERC20 vault, address user, uint256 i, TCancelGuard calldata guard) external;

    function requestRedeem(
        ITranche vault,
        address token,
        address initialFrom,
        address to,
        uint256 shares,
        uint256 exitFee,
        uint32  exitSharesLock
    ) external;

    function setVaultExitBounds(address vault, TExitUpperBounds calldata bounds)external;
    function calculateExitParams (address vault, uint32 coveragePpm) external view returns (TExitParams memory);
}
