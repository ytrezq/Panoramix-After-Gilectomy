// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {StdChains} from "forge-std/StdChains.sol";
import {ScriptBase} from "forge-std/Base.sol";

import {ChainsLib} from "../lib/ChainsLib.sol";

abstract contract Chains is StdChains, ScriptBase {
    string public constant ANVIL_ALIAS = "anvil";
    string public constant MAINNET_ALIAS = "mainnet";
    string public constant GOERLI_ALIAS = "goerli";
    string public constant SEPOLIA_ALIAS = "sepolia";
    string public constant OPTIMISM_ALIAS = "optimism";
    string public constant OPTIMISM_GOERLI_ALIAS = "optimism_goerli";
    string public constant ARBITRUM_ONE_ALIAS = "arbitrum_one";
    string public constant ARBITRUM_ONE_GOERLI_ALIAS = "arbitrum_one_goerli";
    string public constant ARBITRUM_NOVE_ALIAS = "arbitrum_nova";
    string public constant POLYGON_ALIAS = "polygon";
    string public constant POLYGON_MUMBAI_ALIAS = "polygon_mumbai";
    string public constant AVALANCHE_ALIAS = "avalanche";
    string public constant AVALANCHE_FUJI_ALIAS = "avalanche_fuji";
    string public constant BNB_SMART_CHAIN_ALIAS = "bnb_smart_chain";
    string public constant BNB_SMART_CHAIN_TESTNET_ALIAS = "bnb_smart_chain_testnet";
    string public constant GNOSIS_CHAIN_ALIAS = "gnosis_chain";

    /// @notice Resolves a chain RPC URL
    function getChainRpcUrl(string memory _alias) public virtual returns (string memory) {
        return getChain(_alias).rpcUrl;
    }

    /// @notice Resolves a chain alias
    function getChainAlias() public virtual returns (string memory) {
        return ChainsLib.chainAlias();
    }

    /// @notice Verifies if the current chain has the same alias as provided as an input parameter
    /// @param _chainAlias Chain alias to verify
    function isChain(string memory _chainAlias) public virtual returns (bool) {
        return keccak256(bytes(getChainAlias())) == keccak256(bytes(_chainAlias));
    }

    /// @notice Resolves a chain identifier
    /// @return id The chain identifier
    function getChainId() public view returns (uint256 id) {
        assembly {
            id := chainid()
        } // solhint-disable-line no-inline-assembly
    }

    /// @notice Resolves a chain identifier
    /// @return chainIdAsString The chain identifier
    function getChainIdAsString() public view returns (string memory chainIdAsString) {
        uint256 currentChainID;
        assembly {
            currentChainID := chainid()
        } // solhint-disable-line no-inline-assembly
        chainIdAsString = vm.toString(currentChainID);
    }
}
