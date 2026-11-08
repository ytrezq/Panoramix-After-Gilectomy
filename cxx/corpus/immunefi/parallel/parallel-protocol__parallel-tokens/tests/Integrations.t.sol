// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { SendParam, OFTReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";

import "tests/Base.t.sol";

/// @notice Common logic needed by all integration tests, both concrete and fuzz tests.
abstract contract Integrations_Test is Base_Test {
    using OptionsBuilder for bytes;

    BridgeableTokenP.ConfigParams defaultConfigParams;

    function setUp() public virtual override {
        Base_Test.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        _deployFlashParallelToken(address(accessManager), users.feesRecipient.addr);
        vm.startPrank(users.admin.addr);
        accessManager.setTargetFunctionRole(address(flashParallelToken), getGovernorFlashParallelTokenSelectorAccess(), GOVERNOR_ROLE);
        accessManager.grantRole(MINTER_ROLE_aEURp, address(flashParallelToken),0);
        vm.stopPrank();

        defaultConfigParams = BridgeableTokenP.ConfigParams({
            dailyCreditLimit: DEFAULT_DAILY_CREDIT_LIMIT,
            globalCreditLimit: DEFAULT_GLOBAL_CREDIT_LIMIT,
            dailyDebitLimit: DEFAULT_DAILY_DEBIT_LIMIT,
            globalDebitLimit: DEFAULT_GLOBAL_DEBIT_LIMIT,
            feesRecipient: users.feesRecipient.addr,
            feesRate: DEFAULT_FEE_RATE,
            isIsolateMode: false
        });

        aBridgeableTokenp = _deployBridgeableTokenP(
            "aLzEURp",
            "aLzEURp",
            address(aEURp),
            address(endpoints[aEid]),
            address(users.admin.addr),
            defaultConfigParams
        );

        
        bBridgeableTokenp = _deployBridgeableTokenP(
            "bLzEURp",
            "bLzEURp",
            address(bEURp),
            address(endpoints[bEid]),
            address(users.admin.addr),
            defaultConfigParams
        );

        vm.startPrank(users.admin.addr);
        accessManager.grantRole(MINTER_ROLE_aEURp, address(aBridgeableTokenp),0);
        accessManager.grantRole(MINTER_ROLE_bEURp, address(bBridgeableTokenp),0);
        accessManager.setTargetFunctionRole(address(aBridgeableTokenp), getGovernorBridgeableTokenPSelectorAccess(), GOVERNOR_ROLE);
        accessManager.setTargetFunctionRole(address(aBridgeableTokenp), getGuardianBridgeableTokenPSelectorAccess(), GUARDIAN_ROLE);
        accessManager.setTargetFunctionRole(address(bBridgeableTokenp), getGovernorBridgeableTokenPSelectorAccess(), GOVERNOR_ROLE);
        accessManager.setTargetFunctionRole(address(bBridgeableTokenp), getGuardianBridgeableTokenPSelectorAccess(), GUARDIAN_ROLE);


        // config and wire the ofts
        address[] memory bridgeableTokens = new address[](2);
        bridgeableTokens[0] = address(aBridgeableTokenp);
        bridgeableTokens[1] = address(bBridgeableTokenp);
        wireOApps(bridgeableTokens);

        vm.startPrank(users.admin.addr);
        aBridgeableTokenp.transferOwnership(address(accessManager));
        bBridgeableTokenp.transferOwnership(address(accessManager));
        vm.stopPrank();

        vm.startPrank(users.alice.addr);
        aEURp.approve(address(aBridgeableTokenp), INITIAL_BALANCE);
        bEURp.approve(address(bBridgeableTokenp), INITIAL_BALANCE);

  

    }

    function _sendToken(
        BridgeableTokenP bridgeableTokenSending,
        address bridgeableTokenReceiver,
        uint32 eidReceiver,
        bool isPrincipalTokenSent,
        uint256 sendAmount,
        address msgSender
    ) internal {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            eidReceiver,
            addressToBytes32(msgSender),
            sendAmount,
            sendAmount,
            options,
            abi.encode(isPrincipalTokenSent),
            ""
        );
        MessagingFee memory fees = bridgeableTokenSending.quoteSend(sendParam, false);
        bridgeableTokenSending.send{ value: fees.nativeFee }(sendParam, fees, payable(msgSender));
        verifyPackets(eidReceiver, bridgeableTokenReceiver);
    }

    function _sendTokenWithPermit(
        BridgeableTokenP bridgeableTokenSending,
        address bridgeableTokenReceiver,
        uint32 eidReceiver,
        bool isPrincipalTokenSent,
        uint256 sendAmount,
        address msgSender,
        BridgeableTokenP.PermitCalldata memory permitCalldata
    ) internal {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            eidReceiver,
            addressToBytes32(msgSender),
            sendAmount,
            sendAmount,
            options,
            abi.encode(isPrincipalTokenSent),
            ""
        );
        MessagingFee memory fees = bridgeableTokenSending.quoteSend(sendParam, false);
        aBridgeableTokenp.sendWithPermit{ value: fees.nativeFee }(sendParam, fees, permitCalldata, payable(users.alice.addr));
        verifyPackets(eidReceiver, bridgeableTokenReceiver);
    }
}
