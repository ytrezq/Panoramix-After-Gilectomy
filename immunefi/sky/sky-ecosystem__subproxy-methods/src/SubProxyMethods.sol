// SPDX-FileCopyrightText: © 2026 Sky Ecosystem
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
pragma solidity ^0.8.34;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SubProxyMethods: stateless actions to be called with `delegatecall` from a `SubProxy`.
 * @notice This contract is meant to be executed exclusively through `SubProxy.exec(target, args)`, which
 * `delegatecall`s into it. In that context, it can perform actions on behalf of the `SubProxy`, such as
 * transferring ERC20 tokens from the `SubProxy`'s balance.
 */
contract SubProxyMethods {
    using SafeERC20 for IERC20;

    /**
     * @notice Transfers `amount` of `token` to `to` from the caller's context.
     * @dev When called via `SubProxy.exec` (`delegatecall`), the caller's context is the `SubProxy`, so the
     * tokens are sent from the `SubProxy`'s balance. This reverts if the token transfer fails.
     * Uses `SafeERC20` so it also supports tokens that do not return a boolean.
     * @param token The address of the ERC20 token.
     * @param to The recipient of the tokens.
     * @param amount The amount of tokens to transfer.
     */
    function transfer(address token, address to, uint256 amount) external {
        IERC20(token).safeTransfer(to, amount);
    }
}
