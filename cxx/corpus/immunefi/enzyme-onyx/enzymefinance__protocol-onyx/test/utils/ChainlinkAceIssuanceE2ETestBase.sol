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

import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";

import {ValuationHandlerHarness} from "test/harnesses/ValuationHandlerHarness.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

/// @notice Shared scaffold for the per-handler ACE issuance e2e suites (`test/e2e/chainlink-ace-issuance-*`).
/// Stands up the Shares vault, deposit asset, valuation, and a default-allow policy engine; each concrete
/// suite wires only its own handler, validator, extractor (if its policy consumes params), and policy.
/// @dev Abstract: Forge never runs it standalone.
abstract contract ChainlinkAceIssuanceE2ETestBase is TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");

    ValuationHandlerHarness valuationHandler;
    address depositAsset;
    uint8 constant ASSET_DECIMALS = 6;

    address engine;
    address policyOwner = makeAddr("policyOwner");
    // Matches the `initialOwner` set by `deployPolicyEngine`.
    address engineOwner = makeAddr("policyEngineOwner");

    function setUp() public virtual {
        vm.warp(100);

        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        depositAsset = address(new MockERC20(ASSET_DECIMALS));

        valuationHandler = new ValuationHandlerHarness(address(shares));
        vm.prank(admin);
        shares.setValuationHandler(address(valuationHandler));

        // Share price + asset rate so deposits mint non-zero shares and redeems pay non-zero assets.
        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});
        vm.prank(admin);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({asset: depositAsset, rate: 5e18, expiry: uint40(type(uint40).max)})
        );

        // Every policy used by these suites returns `Continue` on pass, so the engine must
        // default-allow; a rejection still comes from the policy reverting `PolicyRejected`.
        engine = deployPolicyEngine({_defaultAllow: true});
    }

    /// @dev Deploys any ACE policy behind an ERC1967 proxy. All catalog policies share the
    /// `Policy.initialize(engine, owner, config)` signature; only the config encoding differs.
    function __deployPolicy(address _impl, bytes memory _config) internal returns (address policy_) {
        return address(new ERC1967Proxy(_impl, abi.encodeCall(Policy.initialize, (engine, policyOwner, _config))));
    }
}
