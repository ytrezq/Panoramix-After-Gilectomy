// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./Base.s.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFTCore,OAppPreCrimeSimulator,OAppOptionsType3} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import { OAppCore } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppCore.sol";


import { BridgeableTokenP } from "contracts/tokens/BridgeableTokenP/BridgeableTokenP.sol";

contract SetBridgebleTokenPRoles is BaseScript {
    address bridgeableTokenP = 0x9E79eC4BC3574f2865636aECFF44B60A723A9eE7;

    function run() public broadcast {
        bytes4[] memory guardianSelectors = new bytes4[](10);
        guardianSelectors[0] = BridgeableTokenP.toggleIsolateMode.selector;
        guardianSelectors[1] = BridgeableTokenP.setFeesRate.selector;
        guardianSelectors[2] = BridgeableTokenP.setDailyCreditLimit.selector;
        guardianSelectors[3] = BridgeableTokenP.setDailyDebitLimit.selector;
        guardianSelectors[4] = BridgeableTokenP.setGlobalCreditLimit.selector;
        guardianSelectors[5] = BridgeableTokenP.setGlobalDebitLimit.selector;
        guardianSelectors[6] = BridgeableTokenP.emergencyRescue.selector;
        guardianSelectors[7] = BridgeableTokenP.pause.selector;
        guardianSelectors[8] = BridgeableTokenP.unpause.selector;
        guardianSelectors[9] = BridgeableTokenP.setFeesRecipient.selector;
        accessManager.setTargetFunctionRole(bridgeableTokenP, guardianSelectors, Roles.GUARDIAN_ROLE);

        bytes4[] memory governorSelectors = new bytes4[](7);
        governorSelectors[0] = Ownable.transferOwnership.selector;
        governorSelectors[1] = Ownable.renounceOwnership.selector;
        governorSelectors[2] = OFTCore.setMsgInspector.selector;
        governorSelectors[3] = OAppPreCrimeSimulator.setPreCrime.selector;
        governorSelectors[4] = OAppOptionsType3.setEnforcedOptions.selector;
        governorSelectors[5] = OAppCore.setPeer.selector;
        governorSelectors[6] = OAppCore.setDelegate.selector;
        accessManager.setTargetFunctionRole(bridgeableTokenP, governorSelectors, Roles.GOVERNOR_ROLE);

        accessManager.grantRole(Roles.USDp_MINTER_ROLE, address(bridgeableTokenP), 0);
    }
}
