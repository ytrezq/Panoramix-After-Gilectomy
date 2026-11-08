// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal interface for the VotingEscrow used by the GaugeController.
interface IYBVotingEscrowForGaugeController {
    struct Point {
        uint256 bias;
        uint256 slope;
    }

    function get_last_user_slope(address addr) external view returns (int256);
    function get_last_user_point(address addr) external view returns (uint256 bias, uint256 slope);
    function locked__end(address addr) external view returns (uint256);
    function transfer_clearance_checker() external view returns (address);
}

/// @notice Minimal interface for gauge contracts that expose an adjustment factor.
interface IYBGauge {
    function get_adjustment() external view returns (uint256);
}

/// @notice Minimal interface for the governance/emissions token used by the GaugeController.
/// @dev In the original Vyper, the function is named `emit`. That collides with the `emit` keyword in Solidity.
///      If you need to call it from Solidity, you'll generally do a low-level call with the correct selector.
interface IYBGovernanceToken {
    //function emit(address owner, uint256 rate_factor) external returns (uint256);
    function preview_emissions(uint256 t, uint256 rate_factor) external view returns (uint256);
    function transfer(address _to, uint256 _amount) external returns (bool);
}

/// @notice Gauge Controller interface (Yield Basis style).
interface IYBGaugeController {
    // =========================
    // Structs
    // =========================

    struct Point {
        uint256 bias;
        uint256 slope;
    }

    struct VotedSlope {
        uint256 slope;
        uint256 bias;
        uint256 power;
        uint256 end;
    }

    // =========================
    // Events
    // =========================

    event VoteForGauge(
        uint256 time,
        address user,
        address gauge_addr,
        uint256 weight
    );

    event NewGauge(address addr);

    event SetKilled(address gauge, bool is_killed);

    // =========================
    // Core Immutable Addresses
    // =========================

    function TOKEN() external view returns (IYBGovernanceToken);
    function VOTING_ESCROW() external view returns (IYBVotingEscrowForGaugeController);

    // =========================
    // Gauge Registry / State
    // =========================

    function n_gauges() external view returns (uint256);
    function gauges(uint256 index) external view returns (address);
    function is_killed(address gauge) external view returns (bool);

    // user -> gauge -> VotedSlope
    function vote_user_slopes(address user, address gauge)
        external
        view
        returns (uint256 slope, uint256 bias, uint256 power, uint256 end);

    // total vote power used by user (in bps, max 10000)
    function vote_user_power(address user) external view returns (uint256);

    // last vote timestamp per (user, gauge)
    function last_user_vote(address user, address gauge) external view returns (uint256);

    // =========================
    // Weights & Emissions Storage Views
    // =========================

    function point_weight(address gauge)
        external
        view
        returns (uint256 bias, uint256 slope);

    function time_weight(address gauge) external view returns (uint256);

    function gauge_weight(address gauge) external view returns (uint256);
    function gauge_weight_sum() external view returns (uint256);

    function adjusted_gauge_weight(address gauge) external view returns (uint256);
    function adjusted_gauge_weight_sum() external view returns (uint256);

    function specific_emissions() external view returns (uint256);
    function specific_emissions_per_gauge(address gauge) external view returns (uint256);
    function weighted_emissions_per_gauge(address gauge) external view returns (uint256);
    function sent_emissions_per_gauge(address gauge) external view returns (uint256);

    // =========================
    // Admin (Ownable)
    // =========================

    function owner() external view returns (address);
    function transfer_ownership(address new_owner) external;

    // =========================
    // Gauge Management
    // =========================

    function add_gauge(address gauge) external;

    function set_killed(address gauge, bool is_killed) external;

    // =========================
    // Voting
    // =========================

    /// @notice Allocate voting power for changing pool weights.
    /// @param _gauge_addrs Gauge addresses to vote for.
    /// @param _user_weights Weights in bps (0–10000) per gauge.
    function vote_for_gauge_weights(
        address[] calldata _gauge_addrs,
        uint256[] calldata _user_weights
    ) external;

    // =========================
    // Read Helpers
    // =========================

    /// @notice Get current gauge weight.
    function get_gauge_weight(address addr) external view returns (uint256);

    /// @notice Get relative gauge weight normalized to 1e18.
    function gauge_relative_weight(address gauge) external view returns (uint256);

    /// @notice Whether a ve-transfer is allowed for a given user (no active voting power).
    function ve_transfer_allowed(address user) external view returns (bool);

    /// @notice Preview emissions for a given gauge at a specific timestamp.
    function preview_emissions(address gauge, uint256 at_time) external view returns (uint256);

    // =========================
    // Checkpoint & Emissions
    // =========================

    /// @notice Checkpoint a gauge (updates weights/emissions).
    function checkpoint(address gauge) external;

    /// @notice Claim emissions for the calling gauge.
    /// @dev In Vyper this is `emit() -> uint256`. Name collides with Solidity keyword; if needed,
    ///      you may have to interact via low-level calls using the known selector.
    //function emit() external returns (uint256);
}