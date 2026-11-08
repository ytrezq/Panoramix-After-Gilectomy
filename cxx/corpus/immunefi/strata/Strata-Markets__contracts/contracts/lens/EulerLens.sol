// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract EulerLens {

    string public name = "Euler Lens";

    /**
     * @notice Returns Euler's Vault balance for primary and sub-accounts.
     */
    function balanceOf(IERC4626 vault, address owner) external view returns (uint256) {
        uint balance = 0;
        for (uint i = 0; i < 256; i++) {
            address account = address(uint160(owner) ^ uint160(i));
            uint shares = vault.balanceOf(account);
            if (shares > 0) {
                balance += vault.convertToAssets(shares);
            }
        }
        return balance;
    }
}
