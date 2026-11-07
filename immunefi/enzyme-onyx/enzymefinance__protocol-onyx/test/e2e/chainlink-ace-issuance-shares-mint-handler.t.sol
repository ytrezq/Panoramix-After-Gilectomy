// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {VolumePolicy} from "@chainlink/policy-management/policies/VolumePolicy.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {
    ChainlinkAceSharesMintHandlerPreMintValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceSharesMintHandlerPreMintValidator.sol";
import {
    ChainlinkAceSharesMintHandlerPreMintExtractor
} from "src/components/issuance/hooks/chainlink-ace/extractors/ChainlinkAceSharesMintHandlerPreMintExtractor.sol";
import {ISharesMintHandlerPreMintHook} from "src/components/issuance/interfaces/ISharesMintHandlerPreMintHook.sol";
import {SharesMintHandler} from "src/components/issuance/deposit-handlers/SharesMintHandler.sol";

import {SharesMintHandlerHarness} from "test/harnesses/SharesMintHandlerHarness.sol";
import {ChainlinkAceIssuanceE2ETestBase} from "test/utils/ChainlinkAceIssuanceE2ETestBase.sol";

/// @dev Proves the full preMint flow: SharesMintHandler ->
/// ChainlinkAceSharesMintHandlerPreMintValidator -> engine -> extractor + VolumePolicy on `sharesAmount`.
contract ChainlinkAceIssuanceSharesMintHandlerE2ETest is ChainlinkAceIssuanceE2ETestBase {
    address mintRecipient = makeAddr("mintRecipient");

    SharesMintHandlerHarness sharesMintHandler;
    ChainlinkAceSharesMintHandlerPreMintValidator preMintValidator;

    // VolumePolicy operates on the raw shares amount (18 decimals).
    uint256 constant MAX_MINT_SHARES_AMOUNT = 400e18;

    function setUp() public override {
        super.setUp();

        sharesMintHandler = new SharesMintHandlerHarness(address(shares));
        vm.prank(admin);
        shares.addDepositHandler(address(sharesMintHandler));

        // Engine must exist before the validator: `init` attaches to it.
        preMintValidator = ChainlinkAceSharesMintHandlerPreMintValidator(
            deployChainlinkAceSharesMintHandlerPreMintValidator(address(shares), address(sharesMintHandler), engine)
        );
        vm.prank(admin);
        sharesMintHandler.setPreMintHook(address(preMintValidator));

        ChainlinkAceSharesMintHandlerPreMintExtractor extractor = new ChainlinkAceSharesMintHandlerPreMintExtractor();

        bytes32[] memory params = new bytes32[](1);
        params[0] = extractor.PARAM_SHARES_AMOUNT();

        vm.startPrank(engineOwner);
        IPolicyEngine(engine).setExtractor(ISharesMintHandlerPreMintHook.preMint.selector, address(extractor));
        IPolicyEngine(engine)
            .addPolicy(
                address(preMintValidator),
                ISharesMintHandlerPreMintHook.preMint.selector,
                __deployPolicy(address(new VolumePolicy()), abi.encode(uint256(0), MAX_MINT_SHARES_AMOUNT)),
                params
            );
        vm.stopPrank();
    }

    function test_mint_succeeds_whenAmountWithinLimit() public {
        uint256 sharesAmount = 100e18; // <= MAX_MINT_SHARES_AMOUNT

        SharesMintHandler.MintInput[] memory inputs = new SharesMintHandler.MintInput[](1);
        inputs[0] = SharesMintHandler.MintInput({to: mintRecipient, sharesAmount: sharesAmount});

        vm.prank(admin);
        sharesMintHandler.mint(inputs);

        assertEq(shares.balanceOf(mintRecipient), sharesAmount, "shares not minted");
    }

    function test_mint_reverts_whenAmountExceedsLimit() public {
        uint256 sharesAmount = 500e18; // > MAX_MINT_SHARES_AMOUNT

        SharesMintHandler.MintInput[] memory inputs = new SharesMintHandler.MintInput[](1);
        inputs[0] = SharesMintHandler.MintInput({to: mintRecipient, sharesAmount: sharesAmount});

        vm.expectPartialRevert(IPolicyEngine.PolicyRunRejected.selector);
        vm.prank(admin);
        sharesMintHandler.mint(inputs);
    }
}
