// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test }   from "../lib/forge-std/src/Test.sol";
import { VmSafe } from "../lib/forge-std/src/Vm.sol";

import { IAccessControl } from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Ethereum } from "../lib/spark-address-registry/src/Ethereum.sol";
import { XLayer }   from "../lib/spark-address-registry/src/XLayer.sol";

import { ISavingsVaultIntents } from "../src/interfaces/ISavingsVaultIntents.sol";
import { SavingsVaultIntents }  from "../src/SavingsVaultIntents.sol";

contract PostDeployMainnetProductionTests is Test {

    address internal constant DEPLOYER = 0xc1499cFb7d1CD5CB61a4C736dc14329DB87Dc46B;

    address internal constant SAVINGS_VAULT_INTENTS = 0x592B7DB9906E6f8924C4D74c2A0aB86CE44fDDDf;

    address internal constant ADMIN   = Ethereum.SPARK_PROXY;
    address internal constant RELAYER = Ethereum.ALM_RELAYER_MULTISIG;

    uint256 internal constant MAX_DEADLINE_DURATION = 7 days;

    SavingsVaultIntents internal savingsVaultIntents;

    function setUp() public {
        vm.createSelectFork(getChain("mainnet").rpcUrl, _getBlock());

        savingsVaultIntents = SavingsVaultIntents(SAVINGS_VAULT_INTENTS);
    }

    function _getBlock() internal pure returns (uint256) {
        return 24684236; // Mar-18-2026
    }

    function test_postDeploy_mainnetProduction() external {
        // Deployer has no roles
        assertEq(savingsVaultIntents.hasRole(savingsVaultIntents.DEFAULT_ADMIN_ROLE(), DEPLOYER), false);
        assertEq(savingsVaultIntents.hasRole(savingsVaultIntents.RELAYER(),            DEPLOYER), false);

        // Admin and Relayer roles added to ADMIN and RELAYER respectively
        assertEq(savingsVaultIntents.hasRole(savingsVaultIntents.DEFAULT_ADMIN_ROLE(), ADMIN),   true);
        assertEq(savingsVaultIntents.hasRole(savingsVaultIntents.RELAYER(),            RELAYER), true);

        // Only one member per role
        assertEq(savingsVaultIntents.getRoleMemberCount(savingsVaultIntents.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(savingsVaultIntents.getRoleMemberCount(savingsVaultIntents.RELAYER()),            1);

        assertEq(savingsVaultIntents.maxDeadlineDuration(), MAX_DEADLINE_DURATION);

        // Role admin hierarchy
        assertEq(savingsVaultIntents.getRoleAdmin(savingsVaultIntents.RELAYER()), savingsVaultIntents.DEFAULT_ADMIN_ROLE());

        // Vault configs

        bool    whitelisted;
        uint256 minIntentAssets;
        uint256 maxIntentAssets;

        // spUSDC
        ( whitelisted, minIntentAssets, maxIntentAssets ) =
            savingsVaultIntents.vaultConfig(Ethereum.SPARK_VAULT_V2_SPUSDC);

        assertEq(whitelisted,     true);
        assertEq(minIntentAssets, 5_000_000e6);
        assertEq(maxIntentAssets, 500_000_000e6);

        // spETH
        ( whitelisted, minIntentAssets, maxIntentAssets ) =
            savingsVaultIntents.vaultConfig(Ethereum.SPARK_VAULT_V2_SPETH);

        assertEq(whitelisted,     true);
        assertEq(minIntentAssets, 1_250e18);
        assertEq(maxIntentAssets, 250_000e18);

        // spPYUSD
        ( whitelisted, minIntentAssets, maxIntentAssets ) =
            savingsVaultIntents.vaultConfig(Ethereum.SPARK_VAULT_V2_SPPYUSD);

        assertEq(whitelisted,     true);
        assertEq(minIntentAssets, 5_000_000e6);
        assertEq(maxIntentAssets, 500_000_000e6);

        // spUSDT
        ( whitelisted, minIntentAssets, maxIntentAssets ) =
            savingsVaultIntents.vaultConfig(Ethereum.SPARK_VAULT_V2_SPUSDT);

        assertEq(whitelisted,     true);
        assertEq(minIntentAssets, 5_000_000e6);
        assertEq(maxIntentAssets, 500_000_000e6);

        // Assert all the events emitted during deployment
        _assertPostDeploymentEvents();

    }

    function _assertPostDeploymentEvents() internal {

        VmSafe.EthGetLogs[] memory roleGrantedLogs = _getEvents(
            block.chainid,
            SAVINGS_VAULT_INTENTS,
            IAccessControl.RoleGranted.selector
        );

        VmSafe.EthGetLogs[] memory vaultConfigUpdatedLogs = _getEvents(
            block.chainid,
            SAVINGS_VAULT_INTENTS,
            ISavingsVaultIntents.VaultConfigUpdated.selector
        );

        VmSafe.EthGetLogs[] memory roleRevokedLogs = _getEvents(
            block.chainid,
            SAVINGS_VAULT_INTENTS,
            IAccessControl.RoleRevoked.selector
        );

        assertEq(roleGrantedLogs.length,        3);
        assertEq(vaultConfigUpdatedLogs.length, 4);
        assertEq(roleRevokedLogs.length,        1);

        bytes32 defaultAdminRole = savingsVaultIntents.DEFAULT_ADMIN_ROLE();
        bytes32 relayerRole      = savingsVaultIntents.RELAYER();

        // Constructor: RoleGranted(DEFAULT_ADMIN_ROLE, DEPLOYER, DEPLOYER)
        assertEq(roleGrantedLogs[0].topics[0],             IAccessControl.RoleGranted.selector);
        assertEq(roleGrantedLogs[0].topics[1],             defaultAdminRole);
        assertEq(_toAddress(roleGrantedLogs[0].topics[2]), DEPLOYER);
        assertEq(_toAddress(roleGrantedLogs[0].topics[3]), DEPLOYER);

        // Constructor: RoleGranted(RELAYER, RELAYER_ADDR, DEPLOYER)
        assertEq(roleGrantedLogs[1].topics[0],             IAccessControl.RoleGranted.selector);
        assertEq(roleGrantedLogs[1].topics[1],             relayerRole);
        assertEq(_toAddress(roleGrantedLogs[1].topics[2]), RELAYER);
        assertEq(_toAddress(roleGrantedLogs[1].topics[3]), DEPLOYER);

        // Admin transfer: RoleGranted(DEFAULT_ADMIN_ROLE, ADMIN, DEPLOYER)
        assertEq(roleGrantedLogs[2].topics[0],             IAccessControl.RoleGranted.selector);
        assertEq(roleGrantedLogs[2].topics[1],             defaultAdminRole);
        assertEq(_toAddress(roleGrantedLogs[2].topics[2]), ADMIN);
        assertEq(_toAddress(roleGrantedLogs[2].topics[3]), DEPLOYER);

        // Init: VaultConfigUpdated for each vault

        ( uint256 minIntentAssets, uint256 maxIntentAssets ) = abi.decode(
            vaultConfigUpdatedLogs[0].data,
            (uint256, uint256)
        );

        assertEq(vaultConfigUpdatedLogs[0].topics[0],             ISavingsVaultIntents.VaultConfigUpdated.selector);
        assertEq(_toAddress(vaultConfigUpdatedLogs[0].topics[1]), Ethereum.SPARK_VAULT_V2_SPUSDC);
        assertEq(_toBool(vaultConfigUpdatedLogs[0].topics[2]),    true);
        assertEq(minIntentAssets,                                 5_000_000e6);
        assertEq(maxIntentAssets,                                 500_000_000e6);

        ( minIntentAssets, maxIntentAssets ) = abi.decode(
            vaultConfigUpdatedLogs[1].data,
            (uint256, uint256)
        );

        assertEq(vaultConfigUpdatedLogs[1].topics[0],             ISavingsVaultIntents.VaultConfigUpdated.selector);
        assertEq(_toAddress(vaultConfigUpdatedLogs[1].topics[1]), Ethereum.SPARK_VAULT_V2_SPETH);
        assertEq(_toBool(vaultConfigUpdatedLogs[1].topics[2]),    true);
        assertEq(minIntentAssets,                                 1_250e18);
        assertEq(maxIntentAssets,                                 250_000e18);

        ( minIntentAssets, maxIntentAssets ) = abi.decode(
            vaultConfigUpdatedLogs[2].data,
            (uint256, uint256)
        );

        assertEq(vaultConfigUpdatedLogs[2].topics[0],             ISavingsVaultIntents.VaultConfigUpdated.selector);
        assertEq(_toAddress(vaultConfigUpdatedLogs[2].topics[1]), Ethereum.SPARK_VAULT_V2_SPPYUSD);
        assertEq(_toBool(vaultConfigUpdatedLogs[2].topics[2]),    true);
        assertEq(minIntentAssets,                                 5_000_000e6);
        assertEq(maxIntentAssets,                                 500_000_000e6);

        ( minIntentAssets, maxIntentAssets ) = abi.decode(
            vaultConfigUpdatedLogs[3].data,
            (uint256, uint256)
        );

        assertEq(vaultConfigUpdatedLogs[3].topics[0],             ISavingsVaultIntents.VaultConfigUpdated.selector);
        assertEq(_toAddress(vaultConfigUpdatedLogs[3].topics[1]), Ethereum.SPARK_VAULT_V2_SPUSDT);
        assertEq(_toBool(vaultConfigUpdatedLogs[3].topics[2]),    true);
        assertEq(minIntentAssets,                                 5_000_000e6);
        assertEq(maxIntentAssets,                                 500_000_000e6);

        // Deployer revocation: RoleRevoked(DEFAULT_ADMIN_ROLE, DEPLOYER, DEPLOYER)

        assertEq(roleRevokedLogs[0].topics[0],             IAccessControl.RoleRevoked.selector);
        assertEq(roleRevokedLogs[0].topics[1],             defaultAdminRole);
        assertEq(_toAddress(roleRevokedLogs[0].topics[2]), DEPLOYER);
        assertEq(_toAddress(roleRevokedLogs[0].topics[3]), DEPLOYER);
    }

    /**********************************************************************************************/
    /*** Get events helpers                                                                     ***/
    /**********************************************************************************************/

    function _getEvents(uint256 chainId, address target, bytes32 topic0) internal returns (VmSafe.EthGetLogs[] memory logs) {
        return _getEvents(chainId, target, topic0, 0);
    }

    function _getEvents(uint256 chainId, address target, bytes32 topic0, uint256 retryCount) internal returns (VmSafe.EthGetLogs[] memory logs) {
        string memory apiKey = vm.envString("ETHERSCAN_API_KEY");

        require(retryCount < 4, "Etherscan API returned non-success status");

        string memory url = string(
            abi.encodePacked(
                "https://api.etherscan.io/v2/api?",
                "chainid=",
                vm.toString(chainId),
                "&module=logs&action=getLogs",
                "&fromBlock=0",
                "&toBlock=latest",
                "&address=",
                vm.toString(target),
                "&page=1",
                "&offset=1000",
                "&apikey=",
                apiKey
            )
        );

        if (topic0 != 0) {
            url = string(abi.encodePacked(url, "&topic0=", vm.toString(topic0)));
        }

        string[] memory inputs = new string[](8);
        inputs[0] = "curl";
        inputs[1] = "-s";
        inputs[2] = "--request";
        inputs[3] = "GET";
        inputs[4] = "--url";
        inputs[5] = url;
        inputs[6] = "--header";
        inputs[7] = "accept: application/json";

        string memory response;

        for (uint256 i; i < 10; i++) {
            response = string(vm.ffi(inputs));

            if (_isEqual(vm.parseJsonString(response, string(abi.encodePacked(".message"))), "NOTOK")) {
                vm.sleep(1000);  // Prevent rate limiting from Etherscan (5 calls/second)
                continue;
            }

            break;
        }

        // Get Result Array Length
        uint256 i = 0;
        for(; i < 1000; i++) {
            try vm.parseJsonAddress(response, string(abi.encodePacked(".result[", vm.toString(i), "].address"))) {
            } catch {
                logs = new VmSafe.EthGetLogs[](i);
                break;
            }
        }

        for(uint256 j; j < i; ++j) {
            // Set unused fields to 0 to save computation
            logs[j] = VmSafe.EthGetLogs({
                emitter:          vm.parseJsonAddress(response,      string(abi.encodePacked(".result[", vm.toString(j), "].address"))),
                topics:           vm.parseJsonBytes32Array(response, string(abi.encodePacked(".result[", vm.toString(j), "].topics"))),
                data:             vm.parseJsonBytes(response,        string(abi.encodePacked(".result[", vm.toString(j), "].data"))),
                blockNumber:      uint64(0),
                blockHash:        bytes32(0),
                transactionHash:  bytes32(0),
                transactionIndex: uint64(0),
                logIndex:         uint8(0),
                removed:          false
            });
        }
    }

    function _isEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _toAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }

    function _toBool(bytes32 b) internal pure returns (bool) {
        require(uint256(b) <= 1, "PostDeployMainnetProductionTests/to-bool-failed");

        return uint256(b) == uint256(1);
    }

}

contract PostDeployXLayerProductionTests is Test {

    address internal constant DEPLOYER = 0x23d43f3189Ab9CEBfFcC0352C0490387e3105FB3;

    address internal constant SAVINGS_VAULT_INTENTS = 0x5bCD2f30FA1Bf675d5d6E793DAD7DdD487D21865;

    address internal constant ADMIN   = XLayer.SPARK_EXECUTOR;
    address internal constant RELAYER = XLayer.ALM_RELAYER_MULTISIG;

    uint256 internal constant MAX_DEADLINE_DURATION = 7 days;

    SavingsVaultIntents internal savingsVaultIntents;

    function setUp() public {
        vm.createSelectFork("https://rpc.xlayer.tech");

        savingsVaultIntents = SavingsVaultIntents(SAVINGS_VAULT_INTENTS);
    }

    function test_postDeploy_xlayerProduction() external view {
        // Deployer has no roles
        assertEq(savingsVaultIntents.hasRole(savingsVaultIntents.DEFAULT_ADMIN_ROLE(), DEPLOYER), false);
        assertEq(savingsVaultIntents.hasRole(savingsVaultIntents.RELAYER(),            DEPLOYER), false);

        // Admin and Relayer roles added to ADMIN and RELAYER respectively
        assertEq(savingsVaultIntents.hasRole(savingsVaultIntents.DEFAULT_ADMIN_ROLE(), ADMIN),   true);
        assertEq(savingsVaultIntents.hasRole(savingsVaultIntents.RELAYER(),            RELAYER), true);

        // Only one member per role
        assertEq(savingsVaultIntents.getRoleMemberCount(savingsVaultIntents.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(savingsVaultIntents.getRoleMemberCount(savingsVaultIntents.RELAYER()),            1);

        assertEq(savingsVaultIntents.maxDeadlineDuration(), MAX_DEADLINE_DURATION);

        // Role admin hierarchy
        assertEq(savingsVaultIntents.getRoleAdmin(savingsVaultIntents.RELAYER()), savingsVaultIntents.DEFAULT_ADMIN_ROLE());

        // Vault configs

        bool    whitelisted;
        uint256 minIntentAssets;
        uint256 maxIntentAssets;

        // spUSDT
        ( whitelisted, minIntentAssets, maxIntentAssets ) =
            savingsVaultIntents.vaultConfig(XLayer.SPARK_VAULT_V2_SPUSDT);

        assertEq(whitelisted,     true);
        assertEq(minIntentAssets, 1_000_000e6);
        assertEq(maxIntentAssets, 500_000_000e6);

    }

}
