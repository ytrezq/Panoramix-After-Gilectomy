// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { SavingsVaultIntents } from "../src/SavingsVaultIntents.sol";

library SavingsVaultIntentsDeploy {
    
    function deployFull(
        address admin,
        address relayer,
        uint256 maxDeadlineDuration
    )   
        internal
        returns (address savingsVaultIntents)
    {
        savingsVaultIntents = address(new SavingsVaultIntents(admin, relayer, maxDeadlineDuration));
    }

}
