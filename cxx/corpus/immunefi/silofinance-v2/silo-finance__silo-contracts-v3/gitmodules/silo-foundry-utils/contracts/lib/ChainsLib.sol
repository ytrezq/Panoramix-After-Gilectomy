// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

library ChainsLib {
    uint256 public constant ANVIL_CHAIN_ID = 31337;
    uint256 public constant MAINNET_CHAIN_ID = 1;
    uint256 public constant GOERLI_CHAIN_ID = 5;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant OPTIMISM_CHAIN_ID = 10;
    uint256 public constant OPTIMISM_GOERLI_CHAIN_ID = 420;
    uint256 public constant ARBITRUM_ONE_CHAIN_ID = 42161;
    uint256 public constant ARBITRUM_ONE_GOERLI_CHAIN_ID = 421613;
    uint256 public constant ARBITRUM_NOVA_CHAIN_ID = 42170;
    uint256 public constant POLYGON_CHAIN_ID = 137;
    uint256 public constant POLYGON_MUMBAI_CHAIN_ID = 80001;
    uint256 public constant AVALANCHE_CHAIN_ID = 43114;
    uint256 public constant AVALANCHE_FUJI_CHAIN_ID = 43113;
    uint256 public constant BNB_CHAIN_ID = 56;
    uint256 public constant BNB_TESTNET_CHAIN_ID = 97;
    uint256 public constant GNOSIS_CHAIN_ID = 100;
    uint256 public constant SONIC_CHAIN_ID = 146;
    uint256 public constant INK_CHAIN_ID = 57073;
    uint256 public constant XDC_CHAIN_ID = 50;
    uint256 public constant XDC_APOTHEM_CHAIN_ID = 51;
    uint256 public constant INJECTIVE_CHAIN_ID = 1776;
    uint256 public constant OKX_CHAIN_ID = 196;
    uint256 public constant BASE_CHAIN_ID = 8453;
    uint256 public constant MEGAETH_CHAIN_ID = 4326;
    uint256 public constant MANTLE_CHAIN_ID = 5000;
    uint256 public constant PHAROS_CHAIN_ID = 1672;

    string public constant ANVIL_ALIAS = "anvil";
    string public constant MAINNET_ALIAS = "mainnet";
    string public constant GOERLI_ALIAS = "goerli";
    string public constant SEPOLIA_ALIAS = "sepolia";
    string public constant OPTIMISM_ALIAS = "optimism";
    string public constant OPTIMISM_GOERLI_ALIAS = "optimism_goerli";
    string public constant ARBITRUM_ONE_ALIAS = "arbitrum_one";
    string public constant ARBITRUM_ONE_GOERLI_ALIAS = "arbitrum_one_goerli";
    string public constant ARBITRUM_NOVA_ALIAS = "arbitrum_nova";
    string public constant POLYGON_ALIAS = "polygon";
    string public constant POLYGON_MUMBAI_ALIAS = "polygon_mumbai";
    string public constant AVALANCHE_ALIAS = "avalanche";
    string public constant AVALANCHE_FUJI_ALIAS = "avalanche_fuji";
    string public constant BNB_ALIAS = "bnb";
    string public constant BNB_TESTNET_ALIAS = "bnb_testnet";
    string public constant GNOSIS_CHAIN_ALIAS = "gnosis_chain";
    string public constant SONIC_ALIAS = "sonic";
    string public constant INK_ALIAS = "ink";
    string public constant XDC_ALIAS = "xdc";
    string public constant XDC_APOTHEM_ALIAS = "xdc_apothem";
    string public constant INJECTIVE_ALIAS = "injective";
    string public constant OKX_ALIAS = "okx";
    string public constant BASE_ALIAS = "base";
    string public constant MEGAETH_ALIAS = "megaeth";
    string public constant MANTLE_ALIAS = "mantle";
    string public constant PHAROS_ALIAS = "pharos";

    function chainAlias() internal view returns (string memory) {
        uint256 chainId = getChainId();

        return chainAlias(chainId);
    }

    function chainAlias(uint256 _chainId) internal pure returns (string memory) {
        string memory result;

        if (_chainId == ANVIL_CHAIN_ID) {
            result = ANVIL_ALIAS;
        } else if (_chainId == MAINNET_CHAIN_ID) {
            result = MAINNET_ALIAS;
        } else if (_chainId == GOERLI_CHAIN_ID) {
            result = GOERLI_ALIAS;
        } else if (_chainId == SEPOLIA_CHAIN_ID) {
            result = SEPOLIA_ALIAS;
        } else if (_chainId == OPTIMISM_CHAIN_ID) {
            result = OPTIMISM_ALIAS;
        } else if (_chainId == OPTIMISM_GOERLI_CHAIN_ID) {
            result = OPTIMISM_GOERLI_ALIAS;
        } else if (_chainId == ARBITRUM_ONE_CHAIN_ID) {
            result = ARBITRUM_ONE_ALIAS;
        } else if (_chainId == ARBITRUM_ONE_GOERLI_CHAIN_ID) {
            result = ARBITRUM_ONE_GOERLI_ALIAS;
        } else if (_chainId == ARBITRUM_NOVA_CHAIN_ID) {
            result = ARBITRUM_NOVA_ALIAS;
        } else if (_chainId == POLYGON_CHAIN_ID) {
            result = POLYGON_ALIAS;
        } else if (_chainId == POLYGON_MUMBAI_CHAIN_ID) {
            result = POLYGON_MUMBAI_ALIAS;
        } else if (_chainId == AVALANCHE_CHAIN_ID) {
            result = AVALANCHE_ALIAS;
        } else if (_chainId == AVALANCHE_FUJI_CHAIN_ID) {
            result = AVALANCHE_FUJI_ALIAS;
        } else if (_chainId == BNB_CHAIN_ID) {
            result = BNB_ALIAS;
        } else if (_chainId == BNB_TESTNET_CHAIN_ID) {
            result = BNB_TESTNET_ALIAS;
        } else if (_chainId == GNOSIS_CHAIN_ID) {
            result = GNOSIS_CHAIN_ALIAS;
        } else if (_chainId == SONIC_CHAIN_ID) {
            result = SONIC_ALIAS;
        } else if (_chainId == INK_CHAIN_ID) {
            result = INK_ALIAS;
        } else if (_chainId == XDC_CHAIN_ID) {
            result = XDC_ALIAS;
        } else if (_chainId == XDC_APOTHEM_CHAIN_ID) {
            result = XDC_APOTHEM_ALIAS;
        } else if (_chainId == INJECTIVE_CHAIN_ID) {
            result = INJECTIVE_ALIAS;
        } else if (_chainId == OKX_CHAIN_ID) {
            result = OKX_ALIAS;
        } else if (_chainId == BASE_CHAIN_ID) {
            result = BASE_ALIAS;
        } else if (_chainId == MEGAETH_CHAIN_ID) {
            result = MEGAETH_ALIAS;
        } else if (_chainId == MANTLE_CHAIN_ID) {
            result = MANTLE_ALIAS;
        } else if (_chainId == PHAROS_CHAIN_ID) {
            result = PHAROS_ALIAS;
        }

        return result;
    }

    /// @notice Resolves a chain identifier
    /// @return id The chain identifier
    function getChainId() internal view returns (uint256 id) {
        assembly {
            id := chainid()
        } // solhint-disable-line no-inline-assembly
    }
}
