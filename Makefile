-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil submodules remove update build

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]"
	@echo "  example: make deploy ARGS=\"--network latestnet\""

# remove everything, re-install, update, build
all: clean remove install build

# Clean Foundry Artifacts
clean:
	forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

# Install Dependencies
install :; forge install OpenZeppelin/openzeppelin-contracts@v4.9.0 --no-commit && forge install foundry-rs/forge-std@v1.8.2 --no-commit && forge install smartcontractkit/chainlink@v2.5.0 --no-commit &&  forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v4.9.0 --no-commit	

# Update Dependencies If Needed
update:
	forge update

# Build Project
build:
	forge build

# Test Project
test:
	forge test

# Snapshot (for differential testing)
snapshot:
	forge snapshot

# Coverage
coverage:
	forge coverage --no-match-coverage ".*mocks.*"

# Format Solidity Code
format:
	forge fmt

# Start Local Anvil Chain with a Deterministic Mnemonic
anvil:
	anvil -m "test test test test test test test test test test test junk" --steps-tracing

forked-ethereum:
	anvil -m "test test test test test test test test test test test junk" --steps-tracing --fork-url $(ETHEREUM_RPC_URL) --chain-id 7400

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network latestnet,$(ARGS)),--network latestnet)
	NETWORK_ARGS := --rpc-url $(LATESTNET_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) --broadcast --with-gas-price 1000000007 --priority-gas-price 1000000000
	VERIFY_ARGS := --verify --chain-id 418 --verifier blockscout --verifier-url $(LATESTNET_VERIFIER_URL) 

else ifeq ($(findstring --network lachain,$(ARGS)),--network lachain)
	NETWORK_ARGS := --rpc-url $(LACHAIN_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) --broadcast --with-gas-price 1000000007 --priority-gas-price 1000000000
	VERIFY_ARGS := --verify --chain-id 274 --verifier blockscout --verifier-url $(LACHAIN_VERIFIER_URL) 

else ifeq ($(findstring --network ethereum,$(ARGS)),--network ethereum)
	NETWORK_ARGS := --rpc-url $(ETHEREUM_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) --broadcast --with-gas-price 1450000000
	VERIFY_ARGS := --verify --chain-id 1 --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY)

else ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) --broadcast --with-gas-price 10000000
	VERIFY_ARGS := --verify --chain-id 11155111 --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY)

else ifeq ($(findstring --network forked-ethereum,$(ARGS)),--network forked-ethereum)
	NETWORK_ARGS := --rpc-url $(FORKED_ETHEREUM_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) --broadcast --with-gas-price 1000000000
	VERIFY_ARGS := 

else
	VERIFY_ARGS :=
endif

# Extract wallet address from private key
ifneq ($(KEYSTORE_PATH),)
WALLET_ADDRESS := $(shell cast wallet address \
  --keystore $(KEYSTORE_PATH) \
  --password $(KEYSTORE_PASSWORD))
endif

# Full Deployment (all steps)
deploy-capyfi-protocol:
	@forge script script/DeployCapyfiProtocolAll.s.sol:DeployCapyfiProtocolAll $(NETWORK_ARGS)

# Deploy Core Protocol (Unitroller, Comptroller, Oracle)
deploy-core-protocol:
	@forge script script/capyfi/DeployCapyfiProtocol.s.sol:DeployCapyfiProtocol $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

# Deploy Interest Rate Models
deploy-irm:
	@forge script script/capyfi/DeployInterestRateModels.s.sol:DeployInterestRateModels $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

# Deploy Individual Interest Rate Model
deploy-individual-irm:
	@forge script script/capyfi/DeployIndividualInterestRateModel.s.sol:DeployIndividualInterestRateModel $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address,string)" $(WALLET_ADDRESS) $(TOKEN_SYMBOL)

# Deploy Mock Tokens (only for testnets when needed)
deploy-mock-tokens:
	@forge script script/capyfi/DeployMockTokens.s.sol:DeployMockTokens $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

# Step 4: Deploy CTokens
deploy-ctokens:
	@forge script script/capyfi/DeployCTokens.s.sol:DeployCTokens $(NETWORK_ARGS) $(VERIFY_ARGS)

# Step 5: Deploy CEther
deploy-ceth:
	@forge script script/capyfi/DeployCEther.s.sol:DeployCEther $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

# Alternative: Deploy CLac separately
deploy-cLac:
	@forge script script/capyfi/DeployCLac.s.sol:DeployCLac $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

# Deploy whitelist with UUPS proxy
deploy-whitelist:
	@forge script script/capyfi/DeployWhitelist.s.sol:DeployWhitelist $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

# Upgrade whitelist implementation
# Usage: make upgrade-whitelist WHITELIST_PROXY_ADDRESS=0x... ARGS="--network ethereum"
upgrade-whitelist:
	@if [ -z "$(WHITELIST_PROXY_ADDRESS)" ]; then \
		echo "Error: WHITELIST_PROXY_ADDRESS parameter is required. Example: make upgrade-whitelist WHITELIST_PROXY_ADDRESS=0x... ARGS=\"--network ethereum\""; \
		exit 1; \
	fi
	@echo "Upgrading Whitelist proxy at: $(WHITELIST_PROXY_ADDRESS)"
	@WHITELIST_PROXY_ADDRESS=$(WHITELIST_PROXY_ADDRESS) forge script script/capyfi/UpgradeWhitelist.s.sol:UpgradeWhitelist $(NETWORK_ARGS) $(VERIFY_ARGS)

# Deploy Chainlink Price Oracle
deploy-chainlink-oracle:
	@forge script script/capyfi/DeployChainlinkOracle.s.sol:DeployChainlinkOracle $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

# Deploy an individual cToken by specifying the token symbol
# Usage: make deploy-individual-ctoken TOKEN_SYMBOL=WETH ARGS="--network sepolia"
deploy-individual-ctoken:
	@if [ -z "$(TOKEN_SYMBOL)" ]; then \
		echo "Error: TOKEN_SYMBOL parameter is required. Example: make deploy-individual-ctoken TOKEN_SYMBOL=WETH ARGS=\"--network ethereum\""; \
		exit 1; \
	fi
	@echo "Deploying c$(TOKEN_SYMBOL) token on network: $(findstring --network,$(NETWORK_ARGS))"
	@TOKEN_SYMBOL=$(TOKEN_SYMBOL) forge script script/capyfi/DeployIndividualCToken.s.sol:DeployIndividualCToken $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

# Configure a cToken
# Usage: make configure-ctoken TOKEN_SYMBOL=WETH ARGS="--network ethereum"
configure-ctoken:
	@if [ -z "$(TOKEN_SYMBOL)" ]; then \
		echo "Error: TOKEN_SYMBOL parameter is required. Example: make configure-ctoken TOKEN_SYMBOL=WETH ARGS=\"--network ethereum\""; \
		exit 1; \
	fi
	@echo "Configuring token: $(TOKEN_SYMBOL)"
	@forge script script/capyfi/ConfigureCToken.s.sol:ConfigureCToken $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address,string)" $(WALLET_ADDRESS) $(TOKEN_SYMBOL)

# Individual cToken configuration actions
# Usage: make support-market TOKEN_SYMBOL=WETH ARGS="--network ethereum"
support-market:
	@if [ -z "$(TOKEN_SYMBOL)" ]; then \
		echo "Error: TOKEN_SYMBOL parameter is required. Example: make support-market TOKEN_SYMBOL=WETH ARGS=\"--network ethereum\""; \
		exit 1; \
	fi
	@echo "Supporting market for token: $(TOKEN_SYMBOL)"
	@forge script script/capyfi/setCTokenConfig/SupportMarket.s.sol:SupportMarket $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address,string)" $(WALLET_ADDRESS) $(TOKEN_SYMBOL)

# Usage: make set-collateral-factor TOKEN_SYMBOL=WETH ARGS="--network ethereum"
# This will use the collateral factor value from the Config file
set-collateral-factor:
	@if [ -z "$(TOKEN_SYMBOL)" ]; then \
		echo "Error: TOKEN_SYMBOL parameter is required. Example: make set-collateral-factor TOKEN_SYMBOL=WETH ARGS=\"--network ethereum\""; \
		exit 1; \
	fi
	@echo "Setting collateral factor for token: $(TOKEN_SYMBOL)"
	@forge script script/capyfi/setCTokenConfig/SetCollateralFactor.s.sol:SetCollateralFactor $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address,string)" $(WALLET_ADDRESS) $(TOKEN_SYMBOL)

# Usage: make add-chainlink-oracle TOKEN_SYMBOL=WETH ARGS="--network ethereum"
# This will use the configuration from the Config file
add-chainlink-oracle:
	@if [ -z "$(TOKEN_SYMBOL)" ]; then \
		echo "Error: TOKEN_SYMBOL parameter is required. Example: make add-chainlink-oracle TOKEN_SYMBOL=WETH ARGS=\"--network ethereum\""; \
		exit 1; \
	fi
	@echo "Adding Chainlink oracle config for token: $(TOKEN_SYMBOL)"
	@forge script script/capyfi/setCTokenConfig/AddChainlinkPriceOracle.s.sol:AddChainlinkPriceOracle $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address,string)" $(WALLET_ADDRESS) $(TOKEN_SYMBOL)

# Usage: make set-reserve-factor TOKEN_SYMBOL=WETH ARGS="--network ethereum"
# This will use the reserve factor value from the Config file
set-reserve-factor:
	@if [ -z "$(TOKEN_SYMBOL)" ]; then \
		echo "Error: TOKEN_SYMBOL parameter is required. Example: make set-reserve-factor TOKEN_SYMBOL=WETH ARGS=\"--network ethereum\""; \
		exit 1; \
	fi
	@echo "Setting reserve factor for token: $(TOKEN_SYMBOL)"
	@forge script script/capyfi/setCTokenConfig/SetReserveFactor.s.sol:SetReserveFactor $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address,string)" $(WALLET_ADDRESS) $(TOKEN_SYMBOL)

# Deploy Capyfi Aggregator V3
deploy-capyfi-aggregator-v3:
	@forge script script/capyfi/DeployCapyfiAggregatorV3.s.sol:DeployCapyfiAggregatorV3 $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

# Query Deployment State
deploy-compound-lens:
	@forge script script/capyfi/query/DeployCompoundLens.s.sol:DeployCompoundLens $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

query-deployment:
	@forge script script/capyfi/query/QueryDeploymentState.s.sol:QueryDeploymentState $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(COMPOUND_LENS_ADDRESS)

# cast wallet import --interactive key.json --keystore-dir keys