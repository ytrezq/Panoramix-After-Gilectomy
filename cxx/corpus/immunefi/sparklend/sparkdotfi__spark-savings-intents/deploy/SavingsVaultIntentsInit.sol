// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { SavingsVaultIntents } from "../src/SavingsVaultIntents.sol";

library SavingsVaultIntentsInit {

    /**********************************************************************************************/
    /*** Structs and constants                                                                  ***/
    /**********************************************************************************************/

    struct CheckDeployParams {
        address admin;
        address relayer;
        uint256 maxDeadlineDuration;
    }

    struct ConfigVaultParams {
        address vault;
        bool    whitelist;
        uint256 minIntentAssets;
        uint256 maxIntentAssets;
    }

    bytes32 constant internal DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant internal RELAYER            = keccak256("RELAYER");

    /**********************************************************************************************/
    /*** Internal init function                                                                 ***/
    /**********************************************************************************************/

    function initSavingsVaultIntents(
        address                    savingsVaultIntents,
        ConfigVaultParams[] memory configVaultParams,
        CheckDeployParams   memory checkDeployParams
    )
        internal
    {
        SavingsVaultIntents instance = SavingsVaultIntents(savingsVaultIntents);

        // Step 1: Sanity checks

        require(
            instance.hasRole(DEFAULT_ADMIN_ROLE, checkDeployParams.admin),
            "SavingsVaultIntentsInit/incorrect-admin"
        );

        require(
            instance.hasRole(RELAYER, checkDeployParams.relayer),
            "SavingsVaultIntentsInit/incorrect-relayer"
        );

        require(
            instance.maxDeadlineDuration() == checkDeployParams.maxDeadlineDuration,
            "SavingsVaultIntentsInit/incorrect-max-deadline-duration"
        );

        // Step 2: Whitelist vaults with configs

        for (uint256 i; i < configVaultParams.length; ++i) {
            instance.updateVaultConfig({
                vault            : configVaultParams[i].vault,
                whitelisted_     : configVaultParams[i].whitelist,
                minIntentAssets_ : configVaultParams[i].minIntentAssets,
                maxIntentAssets_ : configVaultParams[i].maxIntentAssets
            });
        }
    }

}
