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

pragma solidity ^0.8.24;

interface ERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address usr, uint256 wad) external returns (bool);
}

interface DaiJoinLike {
    function dai() external view returns (address);
    function join(address usr, uint256 wad) external;
}

interface UsdsJoinLike is DaiJoinLike {
    function usds() external view returns (address);
}

/// @title DssBlow2
/// @notice This contract acts as a bridge to incorporate any available Dai or USDS
///         balances into the protocol's Surplus Buffer by invoking the appropriate join adapters.
/// @dev The contract automatically approves the maximum token amount for both join adapters during construction.
contract DssBlow2 {
    /// @notice The address of the Vow contract that receives tokens.
    address public immutable vow;

    /// @notice The ERC20 token representing Dai.
    ERC20Like public immutable dai;

    /// @notice The ERC20 token representing USDS.
    ERC20Like public immutable usds;

    /// @notice The adapter for joining Dai into the protocol.
    DaiJoinLike public immutable daiJoin;

    /// @notice The adapter for joining USDS into the protocol.
    UsdsJoinLike public immutable usdsJoin;

    /// @notice Emitted when tokens are transferred into the protocol.
    /// @param token The address of the token (Dai or USDS) that was transferred.
    /// @param amount The amount of tokens that was transferred.
    event Blow(address indexed token, uint256 amount);

    /// @notice Initializes the DssBlow2 contract.
    /// @param daiJoin_ The address of the DaiJoin contract.
    /// @param usdsJoin_ The address of the UsdsJoin contract.
    /// @param vow_ The address of the Vow contract.
    constructor(address daiJoin_, address usdsJoin_, address vow_) {
        daiJoin = DaiJoinLike(daiJoin_);
        dai = ERC20Like(daiJoin.dai());
        usdsJoin = UsdsJoinLike(usdsJoin_);
        usds = ERC20Like(usdsJoin.usds());
        vow = vow_;

        // Approve the maximum uint256 amount for both join adapters.
        dai.approve(daiJoin_, type(uint256).max);
        usds.approve(usdsJoin_, type(uint256).max);
    }

    /// @notice Transfers any available Dai and USDS balances from this contract to the protocol's Surplus Buffer.
    /// @dev For each token, if the balance is greater than zero, the respective join adapter's join function is called.
    function blow() public {
        uint256 daiBalance = dai.balanceOf(address(this));
        if (daiBalance > 0) {
            daiJoin.join(vow, daiBalance);
            emit Blow(address(dai), daiBalance);
        }

        uint256 usdsBalance = usds.balanceOf(address(this));
        if (usdsBalance > 0) {
            usdsJoin.join(vow, usdsBalance);
            emit Blow(address(usds), usdsBalance);
        }
    }
}
