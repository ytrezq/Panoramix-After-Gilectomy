// SPDX-FileCopyrightText: © 2025 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.24;

interface SubProxyLike {
    /**
     * @notice Executes a calldata-encoded call `args` in the context of `target`
     * @param target The target contract
     * @param args The calldata-encoded call
     * @return out The result of the execution
     */
    function exec(address target, bytes calldata args) external payable returns (bytes memory out);
    /**
     * @notice Check owner access
     * @param usr The address to check
     * @return allowed The result of the check
     */
    function wards(address usr) external view returns (uint256 allowed);
}

interface StarSpellLike {
    /**
     * @notice Executes actions performed on behalf of the `SubProxy` – i.e. the actual payload
     * @dev Required, will be called by the StarGuard during permissionless execution
     */
    function execute() external;
    /**
     * @notice Checks if the star payload is executable in the current block
     * @dev Required, useful for implementing "earliest launch date" or "office hours" strategy
     * @return result The result of the check (true = executable, false = not)
     */
    function isExecutable() external view returns (bool result);
}

contract StarGuard {
    // --- structs ---

    /**
     * @notice Star payload data
     * @param addr The payload address
     * @param tag The keccak hash of the bytecode
     * @param deadline The timestamp after which the spell is no longer executable
     */
    struct SpellData {
        address addr;
        bytes32 tag;
        uint256 deadline;
    }

    // --- storage variables ---

    /// @notice Addresses with owner access on this contract
    mapping(address usr => uint256 allowed) public wards;

    /// @notice Maximum delay in seconds between whitelisting and execution
    uint256 public maxDelay;

    /// @notice "Whitelisted" star payload data
    SpellData public spellData;

    // --- immutables ---

    /// @notice Star admin contract (instance of `SubProxy`)
    SubProxyLike public immutable subProxy;

    // --- events ---

    /**
     * @notice `usr` was granted owner access
     * @param usr The user address
     */
    event Rely(address indexed usr);

    /**
     * @notice `usr` owner access was revoked
     * @param usr The user address
     */
    event Deny(address indexed usr);

    /**
     * @notice A contract parameter was updated
     * @param what The changed parameter name
     * @param data The new value of the parameter
     */
    event File(bytes32 indexed what, uint256 data);

    /**
     * @notice A payload has been whitelisted
     * @param addr The payload address
     * @param tag The payload codehash
     * @param deadline The timestamp after which the spell is no longer executable
     */
    event Plot(address indexed addr, bytes32 tag, uint256 deadline);

    /**
     * @notice A previously "whitelisted" payload has been dropped
     * @param addr The payload address
     */
    event Drop(address indexed addr);

    /**
     * @notice A previously whitelisted payload has been executed
     * @param addr The payload address
     */
    event Exec(address indexed addr);

    // --- modifiers ---

    /**
     * @notice Check if sender is authorized
     */
    modifier auth() {
        require(wards[msg.sender] == 1, "StarGuard/not-authorized");
        _;
    }

    // --- constructor ---

    constructor(address subProxy_) {
        subProxy = SubProxyLike(subProxy_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- administration ---

    /**
     * @notice Grants `usr` admin access to this contract
     * @param usr The user address
     */
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    /**
     * @notice Revokes `usr` admin access from this contract
     * @param usr The user address
     */
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    /**
     * @notice Updates mutable variables
     * @param what Name of the mutable variable
     * @param data New value of the variable
     */
    function file(bytes32 what, uint256 data) external auth {
        if (what == "maxDelay") {
            maxDelay = data;
        } else {
            revert("StarGuard/file-unrecognized-param");
        }
        emit File(what, data);
    }

    // --- operations ---

    /**
     * @notice "Whitelists" the payload for the future execution
     * @param addr_ The Star payload to be whitelisted
     * @param tag_ The keccak hash of the bytecode
     */
    function plot(address addr_, bytes32 tag_) external auth {
        require(addr_ != address(0), "StarGuard/zero-spell-address");
        if (spellData.addr != address(0)) emit Drop(spellData.addr);
        spellData.addr = addr_;
        spellData.tag = tag_;
        spellData.deadline = block.timestamp + maxDelay;
        emit Plot(addr_, tag_, spellData.deadline);
    }

    /**
     * @notice Removes the payload from the "whitelist"
     */
    function drop() external auth {
        if (spellData.addr == address(0)) return;
        emit Drop(spellData.addr);
        delete spellData;
    }

    /**
     * @notice Checks if the plotted payload is executable in the current block
     * @return result The result of the check (true = executable, false = reverts)
     */
    function prob() external view returns (bool) {
        return (
            spellData.addr != address(0) && spellData.tag == spellData.addr.codehash
                && block.timestamp <= spellData.deadline && StarSpellLike(spellData.addr).isExecutable()
        );
    }

    /**
     * @notice Executes previously scheduled payload
     * @return addr Executed payload address
     */
    function exec() external returns (address addr) {
        SpellData memory spellDataCopy = spellData;
        require(spellDataCopy.addr != address(0), "StarGuard/unplotted-spell");
        require(spellDataCopy.tag == spellDataCopy.addr.codehash, "StarGuard/wrong-codehash");
        require(block.timestamp <= spellDataCopy.deadline, "StarGuard/expired-spell");
        require(StarSpellLike(spellDataCopy.addr).isExecutable(), "StarGuard/not-yet-executable");

        delete spellData;
        subProxy.exec(spellDataCopy.addr, abi.encodePacked(StarSpellLike.execute.selector));

        require(subProxy.wards(address(this)) == 1, "StarGuard/subProxy-owner-change");
        emit Exec(spellDataCopy.addr);
        return spellDataCopy.addr;
    }
}
