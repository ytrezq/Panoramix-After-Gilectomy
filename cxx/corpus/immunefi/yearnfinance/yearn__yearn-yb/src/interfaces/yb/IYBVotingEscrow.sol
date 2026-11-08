// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Clearance checker for ve-transfer rules.
interface ITransferClearanceChecker {
    function ve_transfer_allowed(address user) external view returns (bool);
}

/// @notice Voting Escrow interface (Yield Basis ve-style: ERC721 + IVotes + time-weighted locks).
interface IYBVotingEscrow {
    // =========================
    // Structs
    // =========================

    struct Point {
        int256 bias;
        int256 slope;
        uint256 ts;
    }

    struct UntimedPoint {
        uint256 bias;
        uint256 slope;
    }

    struct LockedBalance {
        int256 amount;
        uint256 end;
    }

    // =========================
    // Events
    // =========================

    event Deposit(
        address indexed _from,
        address indexed _for,
        uint256 value,
        uint256 indexed locktime,
        uint8 type_, // LockActions enum encoded as uint8
        uint256 ts
    );

    event Withdraw(
        address indexed _from,
        address indexed _for,
        uint256 value,
        uint256 ts
    );

    event Supply(
        uint256 prevSupply,
        uint256 supply
    );

    event SetTransferClearanceChecker(address clearance_checker);

    // =========================
    // ERC20 / Core Views
    // =========================

    function TOKEN() external view returns (address);

    function supply() external view returns (uint256);

    function locked(address account) external view returns (int256 amount, uint256 end);

    // =========================
    // Checkpointing / History
    // =========================

    function epoch() external view returns (uint256);

    function point_history(uint256 index)
        external
        view
        returns (int256 bias, int256 slope, uint256 ts);

    function user_point_history(address account, uint256 index)
        external
        view
        returns (int256 bias, int256 slope, uint256 ts);

    function user_point_epoch(address account) external view returns (uint256);

    function slope_changes(uint256 timestamp) external view returns (int256);

    // =========================
    // Transfer Clearance
    // =========================

    function transfer_clearance_checker() external view returns (ITransferClearanceChecker);

    // =========================
    // ERC165
    // =========================

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    // =========================
    // IVotes-style
    // =========================

    function delegates(address account) external view returns (address);

    function delegate(address delegatee) external;

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function getVotes(address account) external view returns (uint256);

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);

    function totalVotes() external view returns (uint256);

    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);

    // =========================
    // EIP-6372 (clock)
    // =========================

    function clock() external view returns (uint48);

    function CLOCK_MODE() external view returns (string memory);

    // =========================
    // Locking API
    // =========================

    function create_lock(uint256 _value, uint256 _unlock_time) external;

    /// @notice Increase amount for a lock; `_for` mirrors Vyper default arg (msg.sender if omitted).
    function increase_amount(uint256 _value) external;

    function increase_unlock_time(uint256 _unlock_time) external;

    function infinite_lock_toggle() external;

    /// @notice Withdraw for `_for` (Vyper default: msg.sender).
    function withdraw(address _for) external;

    // =========================
    // Admin / Config
    // =========================

    function set_transfer_clearance_checker(ITransferClearanceChecker checker) external;

    // =========================
    // ERC721 Standard (exported via erc721 mixin)
    // =========================

    function balanceOf(address owner) external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function tokenURI(uint256 tokenId) external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function tokenByIndex(uint256 index) external view returns (uint256);

    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    function approve(address to, uint256 tokenId) external;

    function setApprovalForAll(address operator, bool approved) external;

    function getApproved(uint256 tokenId) external view returns (address);

    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function transferFrom(address from, address to, uint256 tokenId) external;

    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    // =========================
    // Extra View Helpers
    // =========================

    function get_last_user_slope(address addr) external view returns (int256);

    function get_last_user_point(address addr) external view returns (uint256 bias, uint256 slope);

    function locked__end(address addr) external view returns (uint256);
}