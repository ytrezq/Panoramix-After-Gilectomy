// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OFTCore,OAppPreCrimeSimulator,OAppOptionsType3} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import { OAppCore } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppCore.sol";

import { TokenP } from "contracts/tokens/TokenP/TokenP.sol";
import { BridgeableTokenP } from "contracts/tokens/BridgeableTokenP/BridgeableTokenP.sol";
import { FlashParallelToken } from "contracts/flashloan/FlashParallelToken.sol";
contract AccessManagerSelectors {
    function getGovernorTokenPSelectorAccess() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UUPSUpgradeable.upgradeToAndCall.selector;
        return selectors;
    }

    function getMinterTokenPSelectorAccess() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenP.mint.selector;
        selectors[1] = TokenP.burnFrom.selector;
        selectors[2] = TokenP.burnSelf.selector;
        return selectors;
    }

    function getGovernorBridgeableTokenPSelectorAccess() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = Ownable.transferOwnership.selector;
        selectors[1] = Ownable.renounceOwnership.selector;
        selectors[2] = OFTCore.setMsgInspector.selector;
        selectors[3] = OAppPreCrimeSimulator.setPreCrime.selector;
        selectors[4] = OAppOptionsType3.setEnforcedOptions.selector;
        selectors[5] = OAppCore.setPeer.selector;
        selectors[6] = OAppCore.setDelegate.selector;
        return selectors;
    }

    function getGuardianBridgeableTokenPSelectorAccess() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = BridgeableTokenP.toggleIsolateMode.selector;
        selectors[1] = BridgeableTokenP.setFeesRate.selector;
        selectors[2] = BridgeableTokenP.setDailyCreditLimit.selector;
        selectors[3] = BridgeableTokenP.setDailyDebitLimit.selector;
        selectors[4] = BridgeableTokenP.setGlobalCreditLimit.selector;
        selectors[5] = BridgeableTokenP.setGlobalDebitLimit.selector;
        selectors[6] = BridgeableTokenP.emergencyRescue.selector;
        selectors[7] = BridgeableTokenP.pause.selector;
        selectors[8] = BridgeableTokenP.unpause.selector;
        selectors[9] = BridgeableTokenP.setFeesRecipient.selector;
        return selectors;
    }

    function getGovernorFlashParallelTokenSelectorAccess() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = FlashParallelToken.setFlashLoanParameters.selector;
        selectors[1] = FlashParallelToken.toggleActiveToken.selector;
        selectors[2] = FlashParallelToken.setFlashLoanFeeRecipient.selector;    
        selectors[3] = UUPSUpgradeable.upgradeToAndCall.selector;
        return selectors;
    }
}
