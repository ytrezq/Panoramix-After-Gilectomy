// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { KATCustomOFTAdapterUpgradeable } from "../../../contracts/KATCustomOFTAdapterUpgradeable.sol";
import { KATCustomOFTUpgradeable } from "../../../contracts/KATCustomOFTUpgradeable.sol";
import { KATOFTAdapterUpgradeable } from "../../../contracts/KATOFTAdapterUpgradeable.sol";
import { KATOFTUpgradeable } from "../../../contracts/KATOFTUpgradeable.sol";
import { MyERC20Mock } from "../../../contracts/mocks/MyERC20Mock.sol";
import { Fixtures } from "./Fixtures.sol";
import { KATVaultMock } from "./KATVaultMock.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee, SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title IntegrationHelpers
 * @notice Helper functions for integration testing the complete bridge flow
 * @dev Provides deployment, upgrade, and utility functions for cross-chain bridge testing
 */
contract IntegrationHelpers is Fixtures {
    using OptionsBuilder for bytes;

    // Chain identifiers
    uint8 constant KATANA_EID = 1;
    uint8 constant BSC_EID = 2;

    // Role constants
    bytes32 constant BRIDGE_USER_ROLE = keccak256("BRIDGE_USER");
    bytes32 constant LZ_BRIDGE_ROLE = keccak256("LZ_BRIDGE_ROLE");

    struct BridgeDeployment {
        MyERC20Mock katToken;
        KATVaultMock vault;
        KATCustomOFTAdapterUpgradeable adapter;
        KATCustomOFTUpgradeable oft;
        address adapterProxy;
        address oftProxy;
        ProxyAdmin adapterProxyAdmin;
        ProxyAdmin oftProxyAdmin;
    }

    /**
     * @notice Deploy the complete bridge infrastructure
     * @param deployer The address deploying the contracts
     * @param bridgeUser The address that will bridge tokens
     * @return deployment Struct containing all deployed contract addresses
     */
    function deployCompleteBridge(address deployer, address bridgeUser)
        internal
        returns (BridgeDeployment memory deployment)
    {
        // Step 1: Deploy KAT Token on Katana
        deployment.katToken = new MyERC20Mock("Katana Token", "KAT");

        // Step 2: Deploy Locked KAT Vault on Katana
        deployment.vault = new KATVaultMock();
        deployment.vault.setToken(address(deployment.katToken));

        // Step 3: Mint KAT tokens to the Vault
        deployment.katToken.mint(address(deployment.vault), 1000000 ether);

        // Step 4: Deploy Custom Adapter on Katana (with proxy)
        // Note: In OZ 5.0, TransparentUpgradeableProxy creates its own ProxyAdmin internally
        KATCustomOFTAdapterUpgradeable adapterImpl =
            new KATCustomOFTAdapterUpgradeable(address(deployment.katToken), address(endpoints[KATANA_EID]));

        bytes memory adapterInitData =
            abi.encodeWithSelector(KATCustomOFTAdapterUpgradeable.initialize.selector, deployer);

        deployment.adapterProxy = address(
            new TransparentUpgradeableProxy(
                address(adapterImpl),
                deployer,
                adapterInitData // deployer becomes owner of internally-created ProxyAdmin
            )
        );

        deployment.adapter = KATCustomOFTAdapterUpgradeable(deployment.adapterProxy);

        // Get the actual ProxyAdmin created by the proxy
        deployment.adapterProxyAdmin = ProxyAdmin(getProxyAdmin(deployment.adapterProxy));

        // Step 5: Deploy Custom OFT on BSC (with proxy)
        // Note: In OZ 5.0, TransparentUpgradeableProxy creates its own ProxyAdmin internally
        KATCustomOFTUpgradeable oftImpl = new KATCustomOFTUpgradeable(address(endpoints[BSC_EID]));

        bytes memory oftInitData =
            abi.encodeWithSelector(KATCustomOFTUpgradeable.initialize.selector, "Katana Token", "KAT", deployer);

        deployment.oftProxy = address(new TransparentUpgradeableProxy(address(oftImpl), deployer, oftInitData)); // deployer becomes owner of internally-created ProxyAdmin

        deployment.oft = KATCustomOFTUpgradeable(deployment.oftProxy);

        // Get the actual ProxyAdmin created by the proxy
        deployment.oftProxyAdmin = ProxyAdmin(getProxyAdmin(deployment.oftProxy));

        // Step 6: Wire peers
        // Use addressToBytes32 helper to ensure correct format (right-padded)
        deployment.adapter.setPeer(BSC_EID, addressToBytes32(deployment.oftProxy));
        deployment.oft.setPeer(KATANA_EID, addressToBytes32(deployment.adapterProxy));

        // Step 7: Set Vault on Adapter
        deployment.adapter.setVault(address(deployment.vault));

        // Step 8: Grant LZ_BRIDGE_ROLE to adapter proxy (for vault interaction)
        // In real implementation, this would be done on the vault contract
        // Here we're simulating it via the mock

        // Step 9: Grant BRIDGE_USER role to the bridge user
        deployment.adapter.grantBridgeUser(bridgeUser);

        return deployment;
    }

    /**
     * @notice Upgrade Custom Adapter to Standard Adapter on Katana (Option 1)
     * @param deployment The existing bridge deployment
     */
    function upgradeAdapterToStandard(BridgeDeployment memory deployment) internal {
        // Deploy new standard implementation
        KATOFTAdapterUpgradeable newImpl =
            new KATOFTAdapterUpgradeable(address(deployment.katToken), address(endpoints[KATANA_EID]));

        // For transparent proxies in OZ 5.0, we upgrade directly via the proxy
        // ProxyAdmin.upgradeAndCall delegates to implementation's upgradeToAndCall which doesn't exist in transparent proxies
        // Instead, we call upgradeToAndCall directly on the proxy (which the proxy will handle)
        vm.prank(address(deployment.adapterProxyAdmin));
        ITransparentUpgradeableProxy(deployment.adapterProxy).upgradeToAndCall(address(newImpl), bytes(""));
    }

    /**
     * @notice Upgrade Custom OFT to Standard OFT on BSC (Option 2)
     * @param deployment The existing bridge deployment
     */
    function upgradeOFTToStandard(BridgeDeployment memory deployment) internal {
        // Deploy new standard implementation
        KATOFTUpgradeable newImpl = new KATOFTUpgradeable(address(endpoints[BSC_EID]));

        // For transparent proxies in OZ 5.0, we upgrade directly via the proxy
        // ProxyAdmin.upgradeAndCall delegates to implementation's upgradeToAndCall which doesn't exist in transparent proxies
        // Instead, we call upgradeToAndCall directly on the proxy (which the proxy will handle)
        vm.prank(address(deployment.oftProxyAdmin));
        ITransparentUpgradeableProxy(deployment.oftProxy).upgradeToAndCall(address(newImpl), bytes(""));
    }

    /**
     * @notice Get the implementation address of a proxy
     * @param proxy The proxy address
     * @return impl The implementation address
     */
    function getImplementation(address proxy) internal view returns (address impl) {
        bytes32 implementationRaw = vm.load(proxy, IMPLEMENTATION_SLOT);
        impl = address(uint160(uint256(implementationRaw)));
    }

    /**
     * @notice Get the ProxyAdmin address of a transparent proxy
     * @param proxy The proxy address
     * @return admin The ProxyAdmin address
     */
    function getProxyAdmin(address proxy) internal view returns (address admin) {
        // ERC-1967 admin slot
        bytes32 ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 adminRaw = vm.load(proxy, ADMIN_SLOT);
        admin = address(uint160(uint256(adminRaw)));
    }

    /**
     * @notice Check if an address has a specific role on a contract
     * @param contractAddr The contract address
     * @param role The role to check
     * @param account The account to check
     * @return hasRole Whether the account has the role
     */
    function hasRole(address contractAddr, bytes32 role, address account) internal view returns (bool) {
        (bool success, bytes memory data) =
            contractAddr.staticcall(abi.encodeWithSignature("hasRole(bytes32,address)", role, account));
        if (success && data.length > 0) {
            return abi.decode(data, (bool));
        }
        return false;
    }

    /**
     * @notice Helper to create standard SendParam struct
     * @param dstEid Destination endpoint ID
     * @param to Recipient address (as address type)
     * @param amount Amount to send
     * @return sendParam Configured SendParam struct
     */
    function createSendParam(uint32 dstEid, address to, uint256 amount)
        internal
        pure
        returns (SendParam memory sendParam)
    {
        return SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(to))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            composeMsg: "",
            oftCmd: ""
        });
    }

    /**
     * @notice Helper to execute a bridge transaction from adapter
     * @param adapter The adapter contract
     * @param sender The address sending the transaction
     * @param sendParam The send parameters
     * @return success Whether the transaction succeeded
     */
    function executeBridge(address adapter, address sender, SendParam memory sendParam)
        internal
        returns (bool success)
    {
        KATCustomOFTAdapterUpgradeable adapterContract = KATCustomOFTAdapterUpgradeable(adapter);
        MessagingFee memory fee = adapterContract.quoteSend(sendParam, false);

        vm.deal(sender, 10 ether);
        vm.prank(sender);

        try adapterContract.send{ value: fee.nativeFee }(sendParam, fee, payable(sender)) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Helper to execute a bridge transaction from OFT
     * @param oft The OFT contract
     * @param sender The address sending the transaction
     * @param sendParam The send parameters
     * @return success Whether the transaction succeeded
     */
    function executeBridgeFromOFT(address oft, address sender, SendParam memory sendParam)
        internal
        returns (bool success)
    {
        KATCustomOFTUpgradeable oftContract = KATCustomOFTUpgradeable(oft);
        MessagingFee memory fee = oftContract.quoteSend(sendParam, false);

        vm.deal(sender, 10 ether);
        vm.prank(sender);

        try oftContract.send{ value: fee.nativeFee }(sendParam, fee, payable(sender)) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Helper to bridge tokens and verify packet delivery
     * @param adapter The adapter contract
     * @param sender The address sending the transaction
     * @param dstEid Destination endpoint ID
     * @param recipient Recipient address
     * @param amount Amount to bridge
     */
    function bridgeAndVerify(
        address adapter,
        address sender,
        uint32 dstEid,
        address recipient,
        uint256 amount,
        address dstContract
    ) internal {
        SendParam memory sendParam = createSendParam(dstEid, recipient, amount);

        KATCustomOFTAdapterUpgradeable adapterContract = KATCustomOFTAdapterUpgradeable(adapter);
        MessagingFee memory fee = adapterContract.quoteSend(sendParam, false);

        vm.deal(sender, 10 ether);
        vm.prank(sender);
        adapterContract.send{ value: fee.nativeFee }(sendParam, fee, payable(sender));

        // Verify packet delivery
        verifyPackets(dstEid, addressToBytes32(dstContract));
    }

    /**
     * @notice Helper to bridge tokens from OFT and verify packet delivery
     * @param oft The OFT contract
     * @param sender The address sending the transaction
     * @param dstEid Destination endpoint ID
     * @param recipient Recipient address
     * @param amount Amount to bridge
     */
    function bridgeFromOFTAndVerify(
        address oft,
        address sender,
        uint32 dstEid,
        address recipient,
        uint256 amount,
        address dstContract
    ) internal {
        SendParam memory sendParam = createSendParam(dstEid, recipient, amount);

        KATCustomOFTUpgradeable oftContract = KATCustomOFTUpgradeable(oft);
        MessagingFee memory fee = oftContract.quoteSend(sendParam, false);

        vm.deal(sender, 10 ether);
        vm.prank(sender);
        oftContract.send{ value: fee.nativeFee }(sendParam, fee, payable(sender));

        // Verify packet delivery
        verifyPackets(dstEid, addressToBytes32(dstContract));
    }
}

