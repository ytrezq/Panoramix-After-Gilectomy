// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Policy} from "@chainlink/policy-management/core/Policy.sol";
import {AllowPolicy} from "@chainlink/policy-management/policies/AllowPolicy.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {
    ChainlinkAceSharesTransferValidator
} from "src/components/shares-transfer-validators/ChainlinkAceSharesTransferValidator.sol";
import {
    ChainlinkAceSharesTransferExtractor
} from "src/components/shares-transfer-validators/ChainlinkAceSharesTransferExtractor.sol";
import {ComponentBeaconFactory} from "src/factories/ComponentBeaconFactory.sol";
import {ISharesTransferValidator} from "src/interfaces/ISharesTransferValidator.sol";
import {Global} from "src/global/Global.sol";
import {Shares} from "src/shares/Shares.sol";

import {TestHelpers} from "test/utils/TestHelpers.sol";

contract ChainlinkAceSharesTransferE2ETest is TestHelpers {
    Shares shares;
    ChainlinkAceSharesTransferValidator validator;
    address engine;
    AllowPolicy allowPolicy;

    address policyOwner = makeAddr("allowPolicyOwner");
    address engineOwner = makeAddr("policyEngineOwner");
    address holder = makeAddr("holder");
    address allowed = makeAddr("allowedRecipient");
    address blocked = makeAddr("blockedRecipient");

    function setUp() public {
        shares = createShares();

        // `AllowPolicy.run` returns `Continue` (not `Allowed`) on success — see chainlink-ace's
        // AllowPolicy. So the engine must default-allow for non-rejected calls to pass through;
        // rejection still comes from `AllowPolicy` reverting `PolicyRejected` for non-allowlisted addresses.
        engine = deployPolicyEngine({_defaultAllow: true});

        // Engine must exist before the validator: `init` sets the engine once and calls `attach()` on it.
        validator =
            ChainlinkAceSharesTransferValidator(deployChainlinkAceSharesTransferValidator(address(shares), engine));

        vm.prank(shares.owner());
        shares.setSharesTransferValidator(address(validator));

        address impl = address(new AllowPolicy());
        bytes memory initData = abi.encodeCall(Policy.initialize, (engine, policyOwner, ""));
        allowPolicy = AllowPolicy(address(new ERC1967Proxy(impl, initData)));

        ChainlinkAceSharesTransferExtractor extractor = new ChainlinkAceSharesTransferExtractor();
        bytes32[] memory params = new bytes32[](1);
        params[0] = extractor.PARAM_TO();

        // The validator forwards a single `validateSharesTransfer`-shaped payload for both
        // `transfer` and `transferFrom`, so only one (selector, extractor, policy) wiring is needed.
        vm.startPrank(engineOwner);
        IPolicyEngine(engine).setExtractor(ISharesTransferValidator.validateSharesTransfer.selector, address(extractor));
        IPolicyEngine(engine)
            .addPolicy(
                address(validator),
                ISharesTransferValidator.validateSharesTransfer.selector,
                address(allowPolicy),
                params
            );
        vm.stopPrank();

        vm.prank(policyOwner);
        allowPolicy.allowAddress(allowed);

        deal({token: address(shares), to: holder, give: 1_000 ether, adjust: true});
    }

    function test_transfer_succeeds_whenRecipientAllowed() public {
        vm.prank(holder);
        shares.transfer(allowed, 100 ether);
        assertEq(shares.balanceOf(allowed), 100 ether);
    }

    function test_transfer_reverts_whenRecipientNotAllowed() public {
        // For transfer(), the originator is the holder itself; the payload sender is the Shares contract,
        // which invokes the validator hook
        IPolicyEngine.Payload memory expectedPayload = IPolicyEngine.Payload({
            selector: ISharesTransferValidator.validateSharesTransfer.selector,
            sender: address(shares),
            data: abi.encode(holder, holder, blocked, 100 ether),
            context: bytes("")
        });

        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolicyEngine.PolicyRunRejected.selector,
                address(allowPolicy),
                "address is not on allow list",
                expectedPayload
            )
        );
        shares.transfer(blocked, 100 ether);
    }

    function test_transferFrom_succeeds_whenRecipientAllowed() public {
        address spender = makeAddr("spender");
        vm.prank(holder);
        shares.approve(spender, 100 ether);

        vm.prank(spender);
        shares.transferFrom(holder, allowed, 100 ether);
        assertEq(shares.balanceOf(allowed), 100 ether);
    }

    function test_transferFrom_reverts_whenRecipientNotAllowed() public {
        address spender = makeAddr("spender");
        vm.prank(holder);
        shares.approve(spender, 100 ether);

        // For transferFrom(), the originator is the spender; the payload sender is the Shares contract,
        // which invokes the validator hook
        IPolicyEngine.Payload memory expectedPayload = IPolicyEngine.Payload({
            selector: ISharesTransferValidator.validateSharesTransfer.selector,
            sender: address(shares),
            data: abi.encode(spender, holder, blocked, 100 ether),
            context: bytes("")
        });

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolicyEngine.PolicyRunRejected.selector,
                address(allowPolicy),
                "address is not on allow list",
                expectedPayload
            )
        );
        shares.transferFrom(holder, blocked, 100 ether);
    }
}
