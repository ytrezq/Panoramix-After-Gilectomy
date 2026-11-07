// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

// OApp imports
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { AccessManager, IAccessManaged } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { CommonErrorsLib } from "contracts/libraries/CommonErrorsLib.sol";

import { BridgeableTokenP_ErrorsLib } from "contracts/tokens/BridgeableTokenP/ErrorsLib.sol";
import { BridgeableTokenP_EventsLib } from "contracts/tokens/BridgeableTokenP/EventsLib.sol";
import { BridgeableTokenP } from "contracts/tokens/BridgeableTokenP/BridgeableTokenP.sol";

import { TokenP_ErrorsLib } from "contracts/tokens/TokenP/ErrorsLib.sol";
import { TokenP_EventsLib } from "contracts/tokens/TokenP/EventsLib.sol";
import { TokenP } from "contracts/tokens/TokenP/TokenP.sol";

import { FlashLoan_ErrorsLib } from "contracts/flashloan/ErrorsLib.sol";
import { FlashLoan_EventsLib } from "contracts/flashloan/EventsLib.sol";
import { FlashParallelToken } from "contracts/flashloan/FlashParallelToken.sol";

import { SigUtils } from "./SigUtils.sol";
import "./Constants.sol";
import "./AccessManagerSelectors.sol";

import {console2} from "@forge-std/console2.sol";

abstract contract Deploys is TestHelperOz5, AccessManagerSelectors {
    using OptionsBuilder for bytes;

    SigUtils internal sigUtils;

    AccessManager accessManager;
    TokenP aEURp;
    TokenP bEURp;
    BridgeableTokenP aBridgeableTokenp;
    BridgeableTokenP bBridgeableTokenp;
    FlashParallelToken flashParallelToken;


    function _deployAccessManager(address _initialAdmin, address _governor, address _guardian) internal {
        accessManager = new AccessManager(_initialAdmin);
        vm.label({ account: address(accessManager), newLabel: "AccessManager" });
        // Set the roles
        vm.startPrank(_initialAdmin);
        accessManager.grantRole(GOVERNOR_ROLE, _governor, 0);
        accessManager.grantRole(GUARDIAN_ROLE, _guardian, 0);
        vm.stopPrank();
    }


    function _deployTokenP(string memory name, string memory symbol) internal returns (TokenP) {
        TokenP tokenPImpl = new TokenP();
        TokenP tokenP = TokenP(address(new ERC1967Proxy(address(tokenPImpl), abi.encodeWithSelector(TokenP.initialize.selector, name, symbol, address(accessManager)))));
        vm.label({ account: address(tokenP), newLabel: name });
        return tokenP;
    }

    function _deployFlashParallelToken(address _accessManager, address _flashLoanFeeRecipient) internal {
        FlashParallelToken flashParallelTokenImpl = new FlashParallelToken();
        flashParallelToken = FlashParallelToken(address(new ERC1967Proxy(address(flashParallelTokenImpl), abi.encodeWithSelector(FlashParallelToken.initialize.selector, _accessManager, _flashLoanFeeRecipient))));
        vm.label({ account: address(flashParallelToken), newLabel: "FlashParallelToken" });
    }

    function _deployBridgeableTokenP(
        string memory _name,
        string memory _symbol,
        address _principalToken,
        address _lzEndpoint,
        address _delegate,
        BridgeableTokenP.ConfigParams memory _configParams
    ) internal returns (BridgeableTokenP) {
        address bridgeableTokenp = 
            _deployOApp(
                    type(BridgeableTokenP).creationCode,
                    abi.encode(_name, _symbol, _principalToken, _lzEndpoint, _delegate, _configParams));
        vm.label({ account: bridgeableTokenp, newLabel: _name });
        return BridgeableTokenP(bridgeableTokenp);
    }
}
