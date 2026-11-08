// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";

/**
 * @title IgnitionDeployments
 * @notice Helper contract to load addresses deployed by Hardhat Ignition
 * @dev Reads from an Ignition deployed_addresses.json file
 *
 * Usage:
 * 1. Keep `ignition/deployments/chain-30/deployed_addresses.json` up to date
 * 2. In your test, inherit from this and call _loadDeployedAddresses()
 * 3. Optional: override path with IGNITION_DEPLOYED_ADDRESSES_PATH
 *
 * Example:
 * ```solidity
 * contract MyTest is IgnitionDeployments {
 *     function setUp() public {
 *         _loadDeployedAddresses();
 *         address swapper = getDeployedAddress("Swappers_MocSwapperV3MultihopProxy");
 *     }
 * }
 * ```
 */
abstract contract IgnitionDeployments is Test {
    /// @notice Default path to the deployed addresses JSON file (mainnet deployment)
    string constant DEFAULT_DEPLOYED_ADDRESSES_PATH = "ignition/deployments/chain-30/deployed_addresses.json";

    /// @notice Ignition module prefix used in raw deployed_addresses.json keys
    string constant MODULE_PREFIX = "FullMultiCollateralUpgrade#";

    /// @notice Mapping of contract ID to deployed address
    mapping(string => address) public deployedAddresses;

    /// @notice Array of all loaded contract IDs
    string[] public loadedContracts;

    /// @notice Whether addresses have been loaded
    bool public addressesLoaded;

    /// @notice Load deployed addresses from JSON file
    /// @dev Uses Forge's vm.parseJson to read the file
    function _loadDeployedAddresses() internal {
        if (addressesLoaded) return;

        string memory deployedAddressesPath = vm.envOr(
            "IGNITION_DEPLOYED_ADDRESSES_PATH",
            string(DEFAULT_DEPLOYED_ADDRESSES_PATH)
        );

        // Check if file exists by trying to read it
        try vm.readFile(deployedAddressesPath) returns (string memory json) {
            bytes memory jsonBytes = bytes(json);
            if (jsonBytes.length == 0 || keccak256(jsonBytes) == keccak256(bytes("{}"))) {
                emit log("Warning: Deployed addresses file is empty");
                return;
            }

            // Parse known contract IDs from FullMultiCollateralUpgrade
            _parseDeployedAddresses(json);
            addressesLoaded = true;
        } catch {
            emit log("Warning: Could not load deployed addresses from Ignition");
            emit log_named_string("Tried path", deployedAddressesPath);
            emit log("Set IGNITION_DEPLOYED_ADDRESSES_PATH if your deployment JSON is in a different location");
        }
    }

    /// @notice Parse the JSON and populate deployedAddresses mapping
    /// @param json The raw JSON string
    function _parseDeployedAddresses(string memory json) internal {
        // === MocSwappers ===
        _tryParseAddress(json, "Swappers_InterimGovernor");
        _tryParseAddress(json, "Swappers_MocSwapperV3MultihopImplementation");
        _tryParseAddress(json, "Swappers_MocSwapperV3MultihopProxy");
        _tryParseAddress(json, "Swappers_MocSwapperV3Multihop");
        _tryParseAddress(json, "Swappers_RifToDocMaxAmountProvider");

        // === FeeFlow ===
        _tryParseAddress(json, "FeeFlow_FeesSplitterImplementation");
        _tryParseAddress(json, "FeeFlow_FeesSplitterProxy");
        _tryParseAddress(json, "FeeFlow_ReverseAuctionDOCtoMOC");
        _tryParseAddress(json, "FeeFlow_ReverseAuctionMOCtoDOC");
        _tryParseAddress(json, "FeeFlow_RocrRewardsBuffer");

        // === DocBucket ===
        _tryParseAddress(json, "DocBucket_DocBucketImplementation");
        _tryParseAddress(json, "DocBucket_DocBucketProxy");
        _tryParseAddress(json, "DocBucket_DocBucketTCImplementation");
        _tryParseAddress(json, "DocBucket_DocBucketTCProxy");
        _tryParseAddress(json, "DocBucket_DocBucketQueueImplementation");
        _tryParseAddress(json, "DocBucket_DocBucketQueueProxy");
        _tryParseAddress(json, "DocBucket_MocCoreExpansion");

        // === MultiCollateralUpgrade (RIF Bucket) ===
        _tryParseAddress(json, "MultiCollateral_MocMultiCollateralGuardImplementation");
        _tryParseAddress(json, "MultiCollateral_MocMultiCollateralGuardProxy");
        _tryParseAddress(json, "MultiCollateral_MocQueueImplementation");
        _tryParseAddress(json, "MultiCollateral_MocQueueProxy");
        _tryParseAddress(json, "MultiCollateral_MocRifImplementation");
        _tryParseAddress(json, "MultiCollateral_USDRifImplementation");
        _tryParseAddress(json, "MultiCollateral_MocCoreExpansion");
        _tryParseAddress(json, "MultiCollateral_MultiCollateralUpgradeChanger");
        _tryParseAddress(json, "MultiCollateral_RifPriceProvider");
        _tryParseAddress(json, "MultiCollateral_RifToRbtcPriceProvider");
    }

    /// @notice Try to parse an address from JSON for a given key
    /// @param json The raw JSON string
    /// @param key The key to look for
    function _tryParseAddress(string memory json, string memory key) internal {
        string memory selector = string.concat(".", key);
        try vm.parseJsonAddress(json, selector) returns (address addr) {
            if (addr != address(0)) {
                deployedAddresses[key] = addr;
                loadedContracts.push(key);
                return;
            }
        } catch {
            // Try raw Ignition key format: "ModuleName#FutureId"
        }

        string memory prefixedSelector = string.concat(".", MODULE_PREFIX, key);
        try vm.parseJsonAddress(json, prefixedSelector) returns (address prefixedAddr) {
            if (prefixedAddr != address(0)) {
                deployedAddresses[key] = prefixedAddr;
                loadedContracts.push(key);
            }
        } catch {
            // Key doesn't exist, that's OK
        }
    }

    /// @notice Get a deployed address by contract ID
    /// @param contractId The contract ID (e.g., "Swappers_MocSwapperV3MultihopProxy")
    /// @return The deployed address, or address(0) if not found
    function getDeployedAddress(string memory contractId) public view returns (address) {
        return deployedAddresses[contractId];
    }

    /// @notice Get a deployed address by contract ID, reverting if not found
    /// @param contractId The contract ID
    /// @return The deployed address
    function getDeployedAddressOrRevert(string memory contractId) public view returns (address) {
        address addr = deployedAddresses[contractId];
        require(addr != address(0), string.concat("Contract not deployed: ", contractId));
        return addr;
    }

    /// @notice Check if a contract was deployed
    /// @param contractId The contract ID
    /// @return True if the contract was deployed
    function isDeployed(string memory contractId) public view returns (bool) {
        return deployedAddresses[contractId] != address(0);
    }

    /// @notice Get the number of loaded contracts
    /// @return The count
    function getLoadedContractsCount() public view returns (uint256) {
        return loadedContracts.length;
    }

    // /// @notice Log all loaded addresses (for debugging)
    // function logLoadedAddresses() public view {
    //     emit log("=== Loaded Deployed Addresses ===");
    //     for (uint256 i = 0; i < loadedContracts.length; i++) {
    //         string memory id = loadedContracts[i];
    //         emit log_named_address(id, deployedAddresses[id]);
    //     }
    //     emit log("=================================");
    // }
}
