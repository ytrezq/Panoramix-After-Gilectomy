// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./Base.s.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import { FlashParallelToken } from "contracts/flashloan/FlashParallelToken.sol";

contract SetFlashParallelTokenRoles is BaseScript {
    address flashParallelToken = 0x46B053Ce47F16390574Bb8f54cAccd04C1E3Faf2;

    function run() public broadcast {
        bytes4[] memory governorSelectors = new bytes4[](4);
        governorSelectors[0] = FlashParallelToken.setFlashLoanParameters.selector;
        governorSelectors[1] = FlashParallelToken.toggleActiveToken.selector;
        governorSelectors[2] = FlashParallelToken.setFlashLoanFeeRecipient.selector;    
        governorSelectors[3] = UUPSUpgradeable.upgradeToAndCall.selector;
        accessManager.setTargetFunctionRole(flashParallelToken, governorSelectors, Roles.GOVERNOR_ROLE);

        accessManager.grantRole(Roles.USDp_MINTER_ROLE, address(flashParallelToken), 0);
    }
}
