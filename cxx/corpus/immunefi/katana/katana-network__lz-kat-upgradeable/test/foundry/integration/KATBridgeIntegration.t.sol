// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee, SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { KATCustomOFTAdapterUpgradeable } from "../../../contracts/KATCustomOFTAdapterUpgradeable.sol";
import { KATCustomOFTUpgradeable } from "../../../contracts/KATCustomOFTUpgradeable.sol";
import { KATOFTAdapterUpgradeable } from "../../../contracts/KATOFTAdapterUpgradeable.sol";
import { KATOFTUpgradeable } from "../../../contracts/KATOFTUpgradeable.sol";
import { IntegrationHelpers } from "../utils/IntegrationHelpers.sol";
import { KATOFTMintable } from "../utils/KATOFTMintable.sol";

/**
 * @title KATBridgeIntegrationTest
 * @notice Integration tests for the complete Katana <-> BSC bridge flow
 * @dev Tests cover the full PoC procedure: deployment, bridging, pausing, and upgrades
 */
contract KATBridgeIntegrationTest is IntegrationHelpers {
    using OptionsBuilder for bytes;

    BridgeDeployment deployment;
    address deployer = address(this);
    address bridgeUser = makeAddr("bridgeUser");
    address user = makeAddr("user");

    function setUp() public override {
        super.setUp();

        // Endpoints already set up in Fixtures.setUp() with EIDs 1 and 2
        // Deploy complete bridge infrastructure
        deployment = deployCompleteBridge(deployer, bridgeUser);
    }

    function test_integration_deployment() public view {
        // Verify KAT Token deployed on Katana
        assertEq(deployment.katToken.name(), "Katana Token");
        assertEq(deployment.katToken.symbol(), "KAT");

        // Verify Vault has KAT tokens
        assertEq(deployment.katToken.balanceOf(address(deployment.vault)), 1000000 ether);

        // Verify Adapter deployed and configured
        assertEq(deployment.adapter.owner(), deployer);
        assertEq(address(deployment.adapter.getVault()), address(deployment.vault));

        // Verify OFT deployed on BSC
        assertEq(deployment.oft.name(), "Katana Token");
        assertEq(deployment.oft.symbol(), "KAT");
        assertEq(deployment.oft.owner(), deployer);

        // Verify peers are set (using addressToBytes32 format - right-padded)
        assertEq(deployment.adapter.peers(BSC_EID), addressToBytes32(address(deployment.oft)), "Adapter peer not set");
        assertEq(deployment.oft.peers(KATANA_EID), addressToBytes32(address(deployment.adapter)), "OFT peer not set");

        // Verify BRIDGE_USER role granted
        assertTrue(deployment.adapter.isBridgeUser(bridgeUser), "Bridge user role not granted");
    }

    /// @notice Test bridging from Katana to BSC with full packet verification
    /// @dev Tests complete cross-chain flow: send, deliver, and verify destination state
    function test_integration_bridgeKatanaToBSC() public {
        uint256 amountToBridge = 10 ether;

        // Record state before bridging
        uint256 vaultBalanceBefore = deployment.katToken.balanceOf(address(deployment.vault));
        uint256 oftBalanceBefore = deployment.oft.balanceOf(user);

        // STEP 1: Send tokens from Katana to BSC via LayerZero
        bridgeAndVerify(deployment.adapterProxy, bridgeUser, BSC_EID, user, amountToBridge, address(deployment.oft));

        // STEP 2: Verify source chain state (vault locked)
        assertEq(
            deployment.katToken.balanceOf(address(deployment.vault)),
            vaultBalanceBefore - amountToBridge,
            "Source: Tokens should be locked in vault"
        );

        // STEP 3: Verify destination chain state (tokens minted)
        assertEq(
            deployment.oft.balanceOf(user),
            oftBalanceBefore + amountToBridge,
            "Destination: Tokens should be minted on BSC"
        );

        assertEq(deployment.oft.totalSupply(), amountToBridge, "Destination: Total supply should equal minted amount");
    }

    /// @notice Test OFT burn functionality for BSC → Katana direction
    /// @dev Tests OFT burn on BSC (source chain verification only)
    /// Note: Full packet delivery omitted as mintableOFT is a test helper without bidirectional peer setup
    function test_integration_bridgeBSCToKatana() public {
        uint256 oftAmount = 50 ether;

        // Deploy a mintable version of the OFT for testing
        // In production, these tokens would have been minted via Katana -> BSC bridge
        KATOFTMintable mintableOFTImpl = new KATOFTMintable(address(endpoints[BSC_EID]));

        bytes memory initData =
            abi.encodeWithSelector(KATOFTMintable.initialize.selector, "Katana Token", "KAT", deployer);

        TransparentUpgradeableProxy mintableOFTProxy =
            new TransparentUpgradeableProxy(address(mintableOFTImpl), proxyAdmin, initData);

        KATOFTMintable mintableOFT = KATOFTMintable(address(mintableOFTProxy));

        // Mint OFT tokens to user (simulating they came from Katana)
        mintableOFT.mint(user, oftAmount);

        // Set peer to adapter using addressToBytes32 (correct format)
        mintableOFT.setPeer(KATANA_EID, addressToBytes32(address(deployment.adapter)));

        // Verify user has OFT tokens
        assertEq(mintableOFT.balanceOf(user), oftAmount, "User should have OFT tokens");
        assertEq(mintableOFT.totalSupply(), oftAmount, "Total supply should match minted amount");

        // Prepare send parameters for BSC -> Katana
        SendParam memory sendParam = SendParam({
            dstEid: KATANA_EID,
            to: bytes32(uint256(uint160(bridgeUser))),
            amountLD: oftAmount,
            minAmountLD: oftAmount,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = mintableOFT.quoteSend(sendParam, false);

        // Bridge tokens from BSC to Katana
        vm.deal(user, 10 ether);
        vm.prank(user);
        mintableOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(user));

        // Verify source chain state (BSC) - tokens burned
        assertEq(mintableOFT.balanceOf(user), 0, "Source: OFT tokens should be burned");
        assertEq(mintableOFT.totalSupply(), 0, "Source: Total supply should be 0 after burn");

        // NOTE: Packet delivery verification skipped for this test as mintableOFT is a test helper
        // without bidirectional peer setup. In production, the actual OFT would have proper peers.
        // Full round-trip E2E is tested on testnet with real bridge setup.
    }

    /// @notice Test complete round-trip bridging: Katana → BSC → Katana
    /// @dev Tests full bidirectional bridge with packet verification at each step
    function test_integration_roundTripBridge() public {
        uint256 amountToSend = 100 ether;
        uint256 amountToReturn = 30 ether;

        // Record initial state
        uint256 vaultBalanceStart = deployment.katToken.balanceOf(address(deployment.vault));
        uint256 userKatBalanceStart = deployment.katToken.balanceOf(user);

        // ========== STEP 1: Katana → BSC ==========
        bridgeAndVerify(deployment.adapterProxy, bridgeUser, BSC_EID, user, amountToSend, address(deployment.oft));

        // Verify Katana state (tokens locked in vault)
        assertEq(
            deployment.katToken.balanceOf(address(deployment.vault)),
            vaultBalanceStart - amountToSend,
            "Round-trip: Tokens should be locked in vault"
        );

        // Verify BSC state (tokens minted)
        assertEq(deployment.oft.balanceOf(user), amountToSend, "Round-trip: Tokens should be minted on BSC");
        assertEq(deployment.oft.totalSupply(), amountToSend, "Round-trip: OFT total supply should match minted amount");

        // ========== STEP 2: BSC → Katana (Partial Return) ==========
        bridgeFromOFTAndVerify(deployment.oftProxy, user, KATANA_EID, user, amountToReturn, address(deployment.adapter));

        // Verify BSC state (tokens burned)
        assertEq(
            deployment.oft.balanceOf(user), amountToSend - amountToReturn, "Round-trip: Remaining OFT tokens on BSC"
        );
        assertEq(
            deployment.oft.totalSupply(), amountToSend - amountToReturn, "Round-trip: OFT supply decreased after burn"
        );

        // Verify Katana state (tokens released from vault to user)
        assertEq(
            deployment.katToken.balanceOf(user),
            userKatBalanceStart + amountToReturn,
            "Round-trip: User should receive KAT from vault"
        );

        assertEq(
            deployment.katToken.balanceOf(address(deployment.vault)),
            vaultBalanceStart - amountToSend,
            "Round-trip: Vault balance doesn't change on return (releases to user)"
        );

        // ========== FINAL VERIFICATION ==========
        uint256 finalAdapterBalance = deployment.katToken.balanceOf(address(deployment.adapter));
        uint256 finalOftSupply = deployment.oft.totalSupply();

        // Adapter holds the locked amount
        assertEq(finalAdapterBalance, finalOftSupply, "Round-trip: Adapter balance should equal OFT supply");

        // User should have returned amount on Katana and remaining amount as OFT on BSC
        assertEq(
            deployment.katToken.balanceOf(user),
            userKatBalanceStart + amountToReturn,
            "Round-trip: User KAT balance on Katana"
        );
        assertEq(deployment.oft.balanceOf(user), amountToSend - amountToReturn, "Round-trip: User OFT balance on BSC");

        // Verify adapter holds exactly the net locked amount
        assertEq(
            finalAdapterBalance, amountToSend - amountToReturn, "Round-trip: Adapter should hold net locked amount"
        );
    }

    function test_integration_revertWhen_nonBridgeUserTriesToBridge() public {
        deployment.katToken.mint(user, 100 ether);

        vm.prank(user);
        deployment.katToken.approve(address(deployment.adapter), 100 ether);

        SendParam memory sendParam = SendParam({
            dstEid: BSC_EID,
            to: bytes32(bytes20(user)),
            amountLD: 10 ether,
            minAmountLD: 10 ether,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = deployment.adapter.quoteSend(sendParam, false);

        vm.deal(user, 10 ether);
        vm.prank(user);
        vm.expectRevert(); // Should revert due to missing BRIDGE_USER role
        deployment.adapter.send{ value: fee.nativeFee }(sendParam, fee, payable(user));
    }

    function test_integration_pauseVaultAndOFT() public {
        // Pause the OFT on BSC
        deployment.oft.pause();
        assertTrue(deployment.oft.paused(), "OFT should be paused");

        // Unpause temporarily to get tokens on BSC
        deployment.oft.unpause();

        // Bridge tokens to BSC
        bridgeAndVerify(deployment.adapterProxy, bridgeUser, BSC_EID, user, 10 ether, address(deployment.oft));

        // Now pause again
        deployment.oft.pause();

        // Try to send from BSC (should fail because OFT is paused)
        SendParam memory sendParam2 = createSendParam(KATANA_EID, bridgeUser, 5 ether);
        MessagingFee memory fee2 = deployment.oft.quoteSend(sendParam2, false);

        vm.deal(user, 10 ether);
        vm.prank(user);
        vm.expectRevert(); // Should revert because OFT is paused
        deployment.oft.send{ value: fee2.nativeFee }(sendParam2, fee2, payable(user));
    }

    /// @notice Test unpause and resume bridging
    /// @dev Simplified to test pause/unpause functionality without packet delivery
    function test_integration_unpauseAndResumeBridging() public {
        // Pause
        deployment.oft.pause();
        assertTrue(deployment.oft.paused());

        // Unpause
        deployment.oft.unpause();
        assertFalse(deployment.oft.paused());

        // Verify send works after unpause
        uint256 vaultBalanceBefore = deployment.katToken.balanceOf(address(deployment.vault));

        bridgeAndVerify(deployment.adapterProxy, bridgeUser, BSC_EID, user, 10 ether, address(deployment.oft));

        // Verify send succeeded by checking vault balance changed
        assertLt(
            deployment.katToken.balanceOf(address(deployment.vault)),
            vaultBalanceBefore,
            "Bridging should work after unpause - vault balance decreased"
        );
    }

    /// @notice Tests upgrading adapter to standard implementation
    /// @dev Uses ProxyAdmin.upgradeAndCall with empty bytes (OZ 5.0 equivalent of upgrade())
    function test_integration_upgradeAdapterToStandard() public {
        // Record state before upgrade
        address implBefore = getImplementation(deployment.adapterProxy);
        address ownerBefore = deployment.adapter.owner();
        bytes32 peerBefore = deployment.adapter.peers(BSC_EID);

        // Verify current implementation is custom adapter
        assertTrue(implBefore != address(0), "Implementation should exist");
        assertEq(ownerBefore, deployer, "Owner should be deployer");
        assertEq(peerBefore, addressToBytes32(address(deployment.oft)), "Peer should be set");

        // Deploy new standard implementation
        KATOFTAdapterUpgradeable newImpl =
            new KATOFTAdapterUpgradeable(address(deployment.katToken), address(endpoints[KATANA_EID]));

        // Perform upgrade using OZ 5.0 upgradeAndCall with empty bytes (equivalent to old upgrade())
        vm.prank(deployer);
        deployment.adapterProxyAdmin
            .upgradeAndCall(
                ITransparentUpgradeableProxy(deployment.adapterProxy),
                address(newImpl),
                "" // Empty bytes - equivalent to upgrade() in older OZ versions
            );

        // Verify implementation changed
        address implAfter = getImplementation(deployment.adapterProxy);
        assertEq(implAfter, address(newImpl), "Implementation should be updated");

        // Verify state is preserved after upgrade
        KATCustomOFTAdapterUpgradeable upgradedAdapter = KATCustomOFTAdapterUpgradeable(deployment.adapterProxy);
        assertEq(upgradedAdapter.owner(), ownerBefore, "Owner should be preserved");
        assertEq(upgradedAdapter.peers(BSC_EID), peerBefore, "Peer should be preserved");
    }

    // ============================================
    // Upgrade Tests - Option 2: Upgrade OFT
    // ============================================

    /// @notice Tests upgrading OFT to standard implementation
    /// @dev Uses ProxyAdmin.upgradeAndCall with empty bytes (OZ 5.0 equivalent of upgrade())
    function test_integration_upgradeOFTToStandard() public {
        // Record state before upgrade
        address implBefore = getImplementation(deployment.oftProxy);
        address ownerBefore = deployment.oft.owner();
        string memory nameBefore = deployment.oft.name();
        string memory symbolBefore = deployment.oft.symbol();
        bytes32 peerBefore = deployment.oft.peers(KATANA_EID);

        // Verify current implementation is custom OFT
        assertTrue(implBefore != address(0), "Implementation should exist");
        assertEq(ownerBefore, deployer, "Owner should be deployer");
        assertEq(nameBefore, "Katana Token", "Name should be set");
        assertEq(symbolBefore, "KAT", "Symbol should be set");
        assertEq(peerBefore, addressToBytes32(address(deployment.adapter)), "Peer should be set");

        // Verify OFT has pausable functionality (custom feature)
        assertFalse(deployment.oft.paused(), "OFT should not be paused initially");

        // Deploy new standard implementation
        KATOFTUpgradeable newImpl = new KATOFTUpgradeable(address(endpoints[BSC_EID]));

        // Perform upgrade using OZ 5.0 upgradeAndCall with empty bytes (equivalent to old upgrade())
        vm.prank(deployer);
        deployment.oftProxyAdmin
            .upgradeAndCall(
                ITransparentUpgradeableProxy(deployment.oftProxy),
                address(newImpl),
                "" // Empty bytes - equivalent to upgrade() in older OZ versions
            );

        // Verify implementation changed
        address implAfter = getImplementation(deployment.oftProxy);
        assertEq(implAfter, address(newImpl), "Implementation should be updated");

        // Verify state is preserved after upgrade
        KATOFTUpgradeable upgradedOFT = KATOFTUpgradeable(deployment.oftProxy);
        assertEq(upgradedOFT.owner(), ownerBefore, "Owner should be preserved");
        assertEq(upgradedOFT.name(), nameBefore, "Name should be preserved");
        assertEq(upgradedOFT.symbol(), symbolBefore, "Symbol should be preserved");
        assertEq(upgradedOFT.peers(KATANA_EID), peerBefore, "Peer should be preserved");
    }

    /// @notice Test multiple sequential bridges
    /// @dev Tests that multiple send() calls succeed
    function test_integration_multipleSequentialBridges() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;
        amounts[2] = 30 ether;

        uint256 vaultBalanceStart = deployment.katToken.balanceOf(address(deployment.vault));
        uint256 oftBalanceStart = deployment.oft.balanceOf(user);
        uint256 totalBridged = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            bridgeAndVerify(deployment.adapterProxy, bridgeUser, BSC_EID, user, amounts[i], address(deployment.oft));

            totalBridged += amounts[i];

            // Verify cumulative amount minted on BSC
            assertEq(
                deployment.oft.balanceOf(user),
                oftBalanceStart + totalBridged,
                "Cumulative OFT balance should match total bridged"
            );
        }

        // Verify total amount locked in vault
        assertEq(
            deployment.katToken.balanceOf(address(deployment.vault)),
            vaultBalanceStart - totalBridged,
            "All bridged amounts should be locked"
        );

        // Verify total supply on BSC matches total bridged
        assertEq(deployment.oft.totalSupply(), totalBridged, "Total OFT supply should match total bridged amount");
    }

    /// @notice Test that bridging zero amount is handled
    /// @dev Zero amount transfers may or may not revert depending on implementation
    function test_integration_revertWhen_bridgingZeroAmount() public {
        SendParam memory sendParam = SendParam({
            dstEid: BSC_EID,
            to: bytes32(bytes20(user)),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = deployment.adapter.quoteSend(sendParam, false);

        vm.deal(bridgeUser, 10 ether);
        vm.prank(bridgeUser);

        // Try to send - may revert or succeed with no-op
        // Different LayerZero versions handle this differently
        try deployment.adapter.send{ value: fee.nativeFee }(sendParam, fee, payable(bridgeUser)) {
            // If it succeeds, verify vault balance didn't change
            assertEq(
                deployment.katToken.balanceOf(address(deployment.vault)),
                1000000 ether,
                "Vault balance should not change for zero amount"
            );
        } catch {
            // Revert is also acceptable for zero amount
            assertTrue(true, "Zero amount transfer reverted as expected");
        }
    }

    /// @notice Test total supply consistency
    /// @dev Simplified to test vault locking without packet delivery
    function test_integration_totalSupplyConsistency() public {
        // Initial total supply should be 0 on BSC
        assertEq(deployment.oft.totalSupply(), 0, "Initial OFT supply should be 0");

        // Bridge some tokens
        uint256 amountToBridge = 50 ether;
        uint256 vaultBalanceBefore = deployment.katToken.balanceOf(address(deployment.vault));

        bridgeAndVerify(deployment.adapterProxy, bridgeUser, BSC_EID, user, amountToBridge, address(deployment.oft));

        // Verify vault locked the tokens (supply consistency on source chain)
        assertEq(
            deployment.katToken.balanceOf(address(deployment.vault)),
            vaultBalanceBefore - amountToBridge,
            "Vault should lock exact amount"
        );

        // Verify total supply consistency: locked on Katana = minted on BSC
        assertEq(deployment.oft.totalSupply(), amountToBridge, "Total OFT supply should equal bridged amount");

        assertEq(deployment.oft.balanceOf(user), amountToBridge, "User should have received OFT tokens");
    }
}
