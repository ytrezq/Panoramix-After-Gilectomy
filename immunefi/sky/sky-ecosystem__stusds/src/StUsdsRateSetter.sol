// SPDX-FileCopyrightText: 2025 Dai Foundation <www.daifoundation.org>
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

pragma solidity ^0.8.21;

interface JugLike {
    function ilks(bytes32) external view returns (uint256, uint256);
    function file(bytes32, bytes32, uint256) external;
    function drip(bytes32) external;
}

interface StUsdsLike {
    function jug() external view returns (address);
    function ilk() external view returns (bytes32);
    function str() external view returns (uint256);
    function file(bytes32, uint256) external;
    function drip() external;
}

interface ConvLike {
    function btor(uint256) external pure returns (uint256);
    function rtob(uint256) external pure returns (uint256);
}

contract StUsdsRateSetter {
    // --- Storage Variables ---
    mapping(address => uint256) public wards;
    mapping(address => uint256) public buds;
    Cfg     public strCfg;
    Cfg     public dutyCfg;
    uint256 public maxLine; // [rad]
    uint256 public maxCap;  // [wad]
    uint8   public bad; // Circuit breaker flag
    uint64  public tau; // Cooldown period between rate changes in seconds
    uint128 public toc; // Last time when rates were updated (Unix timestamp)

    // --- Structs ---
    // All values are in basis points (1 bp = 0.01%)
    struct Cfg {
        uint16 min;  // Minimum allowed rate
        uint16 max;  // Maximum allowed rate
        uint16 step; // Maximum allowed rate change per update
    }

    // --- Constants ---
    uint256 private constant RAY = 10 ** 27;
    uint256 private constant RAD = 10 ** 45;

    // --- Immutables ---
    JugLike    public immutable jug;
    StUsdsLike public immutable stusds;
    ConvLike   public immutable conv;
    bytes32    public immutable ilk;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed id, bytes32 indexed what, uint256 data);
    event Set(uint256 strBps, uint256 dutyBps, uint256 line, uint256 cap);

    // --- Modifiers ---
    modifier auth() {
        require(wards[msg.sender] == 1, "StUsdsRateSetter/not-authorized");
        _;
    }

    modifier toll() {
        require(buds[msg.sender] == 1, "StUsdsRateSetter/not-facilitator");
        _;
    }

    modifier good() {
        require(bad == 0, "StUsdsRateSetter/module-halted");
        _;
    }

    constructor(address _stusds, address _conv) {
        stusds = StUsdsLike(_stusds);
        conv   = ConvLike(_conv);
        jug    = JugLike(stusds.jug());
        ilk    = stusds.ilk();

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function kiss(address usr) external auth {
        buds[usr] = 1;
        emit Kiss(usr);
    }

    function diss(address usr) external auth {
        buds[usr] = 0;
        emit Diss(usr);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "bad") {
            require(data == 0 || data == 1, "StUsdsRateSetter/invalid-bad-value");
            bad = uint8(data);
        } else if (what == "tau") {
            require(data <= type(uint64).max, "StUsdsRateSetter/invalid-tau-value");
            tau = uint64(data);
        } else if (what == "toc") {
            require(data <= type(uint128).max, "StUsdsRateSetter/invalid-toc-value");
            toc = uint128(data);
        } else if (what == "maxLine") {
            require(data == 0 || data >= RAD, "StUsdsRateSetter/maxLine-irrelevant-value");
            maxLine = data;
        } else if (what == "maxCap") {
            require(data < RAD, "StUsdsRateSetter/maxCap-insane-value");
            maxCap = data;
        } else revert("StUsdsRateSetter/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 id, bytes32 what, uint256 data) external auth {
        Cfg storage cfg;
        if      (id == "STR") cfg = strCfg;
        else if (id == ilk)   cfg = dutyCfg;
        else revert("StUsdsRateSetter/file-unrecognized-id");

        require(data <= type(uint16).max, "StUsdsRateSetter/invalid-value");
        if (what == "min") {
            require(data <= cfg.max, "StUsdsRateSetter/min-too-high");
            cfg.min = uint16(data);
        } else if (what == "max") {
            require(data >= cfg.min, "StUsdsRateSetter/max-too-low");
            cfg.max = uint16(data);
        } else if (what == "step") {
            cfg.step = uint16(data);
        } else revert("StUsdsRateSetter/file-unrecognized-param");
        emit File(id, what, data);
    }

    function _calcRate(uint256 bps, uint256 oldBps, Cfg memory cfg) internal view returns (uint256 ray) {
        require(cfg.step > 0,   "StUsdsRateSetter/rate-not-configured");
        require(bps >= cfg.min, "StUsdsRateSetter/below-min");
        require(bps <= cfg.max, "StUsdsRateSetter/above-max");

        if (oldBps < cfg.min) {
            oldBps = cfg.min;
        } else if (oldBps > cfg.max) {
            oldBps = cfg.max;
        }

        // Calculates absolute difference between the old and the new rate
        uint256 delta = bps > oldBps ? bps - oldBps : oldBps - bps;
        require(delta <= cfg.step, "StUsdsRateSetter/delta-above-step");

        ray = conv.btor(bps);
        require(ray >= RAY, "StUsdsRateSetter/invalid-rate-conv");
    }

    // Notes:
    // - It is intended to rewrite the same values, emit the event, and reset the toc count, even if there is no change.
    function set(uint256 strBps, uint256 dutyBps, uint256 line, uint256 cap) external toll good {
        require(block.timestamp >= tau + toc, "StUsdsRateSetter/too-early");
        toc = uint128(block.timestamp);

        require(line <= maxLine, "StUsdsRateSetter/line-too-high");
        stusds.file("line", line); // New line will be immediately taken into account as stusds.drip will be called few lines below

        require(cap <= maxCap, "StUsdsRateSetter/cap-too-high");
        stusds.file("cap", cap);

        uint256 ray = _calcRate({
            bps    : strBps,
            oldBps : conv.rtob(stusds.str()),
            cfg    : strCfg
        });
        stusds.drip();
        stusds.file("str", ray);

        (uint256 duty,) = jug.ilks(ilk);
        ray = _calcRate({
            bps    : dutyBps,
            oldBps : conv.rtob(duty),
            cfg    : dutyCfg
        });
        jug.drip(ilk);
        jug.file(ilk, "duty", ray);

        emit Set(strBps, dutyBps, line, cap);
    }
}
