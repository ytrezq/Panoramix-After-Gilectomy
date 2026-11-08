# To avoid make printing out commands and potentially exposing private keys, prepend an "@" to the command.
# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
update:; forge update

# Build & test
build  :; forge build --sizes --via-ir
test   :; forge test -vvv

# ---------------------------------------------- BASE SCRIPT CONFIGURATION ---------------------------------------------

BASE_LEDGER = --legacy --mnemonics foo --ledger --mnemonic-indexes $(MNEMONIC_INDEX) --sender $(LEDGER_SENDER)
BASE_KEY = --private-key ${PRIVATE_KEY}
BASE_KEY_LOCAL = --private-key ${PRIVATE_KEY_LOCAL}

custom_ethereum := --with-gas-price 45000000000 # 53 gwei
custom_polygon := --with-gas-price 190000000000 # 560 gwei
custom_binance := --with-gas-price 45000000000 # 53 gwei
custom_avalanche := --with-gas-price 27000000000 # 27 gwei
custom_metis-testnet := --legacy --verifier-url https://goerli.explorer.metisdevops.link/api/
custom_metis := --verifier-url  https://api.routescan.io/v2/network/mainnet/evm/1088/etherscan
custom_scroll-testnet := --legacy --with-gas-price 1000000000 # 1 gwei

# params:
#  1 - path/file_name
#  2 - network name
#  3 - script to call if not the same as network name (optional)
#  to define custom params per network add vars custom_network-name
#  to use ledger, set LEDGER=true to env
#  default to testnet deployment, to run production, set PROD=true to env
define deploy_single_fn
forge script \
 scripts/$(1).s.sol:$(if $(3),$(3),$(shell UP=$(if $(PROD),$(2),$(2)_testnet); echo $${UP} | perl -nE 'say ucfirst')) \
 --rpc-url $(if $(PROD),$(2),$(2)-testnet) --broadcast --verify --slow -vvvv \
 $(if $(LEDGER),$(BASE_LEDGER),$(BASE_KEY)) \
 $(custom_$(if $(PROD),$(2),$(2)-testnet))

endef

define deploy_fn
 $(foreach network,$(2),$(call deploy_single_fn,$(1),$(network),$(3)))
endef

# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------- PRODUCTION DEPLOYMENT SCRIPTS ---------------------------------------------------------

# deploy emergency registry
deploy-emergency-registry:
	$(call deploy_fn,Deploy_EmergencyRegistry,ethereum)

# Deploy Proxy Factories on all networks
deploy-proxy-factory:
	$(call deploy_fn,InitialDeployments,ethereum avalanche polygon optimism arbitrum metis base binance gnosis zkevm)

# Deploy Cross Chain Infra on all networks
deploy-cross-chain-infra:
	$(call deploy_fn,CCC/Deploy_CCC,ethereum avalanche polygon optimism arbitrum metis base binance gnosis zkevm)

## Deploy CCIP bridge adapters on all networks
deploy-ccip-bridge-adapters:
	$(call deploy_fn,Adapters/DeployCCIP,ethereum avalanche binance polygon binance gnosis)

## Deploy LayerZero bridge adapters on all networks
deploy-lz-bridge-adapters:
	$(call deploy_fn,Adapters/DeployLZ,ethereum avalanche binance polygon binance gnosis)

## Deploy HyperLane bridge adapters on all networks
deploy-hl-bridge-adapters:
	$(call deploy_fn,Adapters/DeployHL,ethereum avalanche binance polygon binance gnosis)

## Deploy SameChain adapters on ethereum
deploy-same-chain-adapters:
	$(call deploy_fn,Adapters/DeploySameChainAdapter,ethereum)

deploy-optimism-adapters:
	$(call deploy_fn,Adapters/DeployOpAdapter,ethereum optimism)

deploy-arbitrum-adapters:
	$(call deploy_fn,Adapters/DeployArbAdapter,ethereum arbitrum)

deploy-metis-adapters:
	$(call deploy_fn,Adapters/DeployMetisAdapter,ethereum metis)

deploy-polygon-adapters:
	$(call deploy_fn,Adapters/DeployPolygon,ethereum polygon)

deploy-base-adapters:
	$(call deploy_fn,Adapters/DeployCBaseAdapter,ethereum base)

deploy-gnosis-adapters:
	$(call deploy_fn,Adapters/DeployGnosisChain,ethereum gnosis)

deploy-scroll-adapters:
	$(call deploy_fn,Adapters/DeployScrollAdapter,ethereum scroll)

deploy-zkevm-adapters:
	$(call deploy_fn,Adapters/DeployZkEVMAdapter,ethereum zkevm)

deploy-wormhole-adapters:
	$(call deploy_fn,Adapters/DeployWormholeAdapter,ethereum celo)

## Set sender bridge dapters. Only eth pol avax are needed as other networks will only receive
set-ccf-sender-adapters:
	$(call deploy_fn,CCC/Set_CCF_Sender_Adapters,ethereum)

# Set the bridge adapters allowed to receive messages
set-ccr-receiver-adapters:
	$(call deploy_fn,CCC/Set_CCR_Receivers_Adapters,ethereum polygon avalanche binance arbitrum optimism base metis gnosis zkevm)

# Sets the required confirmations
set-ccr-confirmations:
	$(call deploy_fn,CCC/Set_CCR_Confirmations,ethereum polygon avalanche optimism arbitrum metis base binance gnosis zkevm)

# Generate Addresses Json
write-json-addresses :; forge script scripts/WriteAddresses.s.sol:WriteDeployedAddresses -vvvv

# Funds CCC
fund-crosschain:
	$(call deploy_fn,CCC/FundCCC,ethereum polygon avalanche arbitrum)

## Deploy and configure all contracts
deploy-full:
		make deploy-proxy-factory
		make deploy-cross-chain-infra
		make deploy-ccip-bridge-adapters
		make deploy-lz-bridge-adapters
		make deploy-hl-bridge-adapters
		make deploy-same-chain-adapters
		make deploy-optimism-adapters
		make deploy-arbitrum-adapters
		make deploy-metis-adapters
		make deploy-polygon-adapters
		make set-ccf-approved-senders
		make set-ccf-sender-adapters
		make set-ccr-receiver-adapters
		make set-ccr-confirmations
		make fund-crosschain
		make write-json-addresses



# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------- TESTNET DEPLOYMENT SCRIPTS ---------------------------------------------------------

# Deploy Proxy Factories on all networks
deploy-proxy-factory-test:
	$(call deploy_fn,InitialDeployments,polygon avalanche binance)

# Deploy Cross Chain Infra on all networks
deploy-cross-chain-infra-test:
	$(call deploy_fn,CCC/Deploy_CCC,ethereum)

## Deploy CCIP bridge adapters on all networks
deploy-ccip-bridge-adapters-test:
	$(call deploy_fn,Adapters/DeployCCIP,ethereum polygon)

## Deploy LayerZero bridge adapters on all networks
deploy-lz-bridge-adapters-test:
	$(call deploy_fn,Adapters/DeployLZ,ethereum polygon)

## Deploy HyperLane bridge adapters on all networks
deploy-hl-bridge-adapters-test:
	$(call deploy_fn,Adapters/DeployHL,ethereum polygon)

## Deploy SameChain adapters on ethereum
deploy-same-chain-adapters-test:
	$(call deploy_fn,Adapters/DeploySameChainAdapter,ethereum)

deploy-scroll-adapters-test:
	$(call deploy_fn,Adapters/DeployScrollAdapter,ethereum scroll)

deploy-wormhole-adapters-test:
	$(call deploy_fn,Adapters/DeployWormholeAdapter,ethereum celo)

## Set sender bridge dapters. Only eth pol avax are needed as other networks will only receive
set-ccf-sender-adapters-test:
	$(call deploy_fn,CCC/Set_CCF_Sender_Adapters,ethereum polygon)

# Set the bridge adapters allowed to receive messages
set-ccr-receiver-adapters-test:
	$(call deploy_fn,CCC/Set_CCR_Receivers_Adapters,ethereum polygon)

# Sets the required confirmations
set-ccr-confirmations-test:
	$(call deploy_fn,CCC/Set_CCR_Confirmations,ethereum polygon)

# Funds CCC
fund-crosschain-test:
	$(call deploy_fn,CCC/FundCCC,ethereum)

## Deploy and configure all contracts
deploy-full-test:
		#make deploy-proxy-factory-test
		make deploy-cross-chain-infra-test
		make deploy-ccip-bridge-adapters-test
		make deploy-lz-bridge-adapters-test
		make deploy-hl-bridge-adapters-test
		make deploy-same-chain-adapters-test
		make set-ccf-sender-adapters-test
		make set-ccr-receiver-adapters-test
		make set-ccr-confirmations-test
		make fund-crosschain-test
		make write-json-addresses

# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------- LIDO MAINNER DEPLOYMENT SCRIPTS --------------------------------------------

burn-deployer-nonce:
	$(call deploy_fn,Lido/helpers/Burn_Deployer_Nonce,binance)

deploy-lido-cross-chain-infra:
	$(call deploy_fn,Lido/CCC/Deploy_CCC,ethereum binance)

deploy-lido-ccip-bridge-adapters:
	$(call deploy_fn,Lido/Adapters/Deploy_CCIP,ethereum binance)

deploy-lido-lz-bridge-adapters:
	$(call deploy_fn,Lido/Adapters/Deploy_LZ,ethereum binance)

deploy-lido-hl-bridge-adapters:
	$(call deploy_fn,Lido/Adapters/Deploy_HL,ethereum binance)

deploy-lido-wormhole-adapters:
	$(call deploy_fn,Lido/Adapters/Deploy_Wormhole,ethereum binance)

deploy-lido-cross-chain-executor:
	$(call deploy_fn,Lido/CCC/Deploy_CCE,binance)

set-lido-ccf-approved-senders:
	$(call deploy_fn,Lido/CCC/Set_CCF_Approved_Senders,ethereum)

set-lido-ccf-sender-adapters:
	$(call deploy_fn,Lido/CCC/Set_CCF_Sender_Adapters,ethereum)

set-lido-ccr-receiver-adapters:
	$(call deploy_fn,Lido/CCC/Set_CCR_Receivers_Adapters,binance)

set-lido-ccr-confirmations:
	$(call deploy_fn,Lido/CCC/Set_CCR_Confirmations,binance)

fund-lido-cross-chain:
	$(call deploy_fn,Lido/CCC/Fund_CCC,ethereum)

finalize-lido:
	$(call deploy_fn,Lido/CCC/Finalize,ethereum binance)

write-lido-json-addresses :; forge script scripts/Lido/WriteAddresses.s.sol:WriteDeployedAddresses -vvvv

deploy-lido-bridge-adapters:
	make deploy-lido-ccip-bridge-adapters
	make deploy-lido-lz-bridge-adapters
	make deploy-lido-hl-bridge-adapters
	make deploy-lido-wormhole-adapters

set-lido-ccf:
	make set-lido-ccf-approved-senders
	make set-lido-ccf-sender-adapters

set-lido-ccr:
	make set-lido-ccr-receiver-adapters
	make set-lido-ccr-confirmations

deploy-lido-full:
	make burn-deployer-nonce
	make deploy-lido-cross-chain-infra
	make deploy-lido-bridge-adapters
	make deploy-lido-cross-chain-executor
	make set-lido-ccf
	make set-lido-ccr
	make fund-lido-cross-chain
	make finalize-lido
	make write-lido-json-addresses

test-lido-state:
	ENV=prod forge test -vv --match-path "tests/Lido/state/**/*.sol"

test-lido-integration:
	ENV=prod forge test -vv --match-path "tests/Lido/integration/**/*.sol"

test-lido:
	make test-lido-state-local
	make test-lido-integration-local

vote-lido-agent-change:
	$(call deploy_fn,Lido/e2e/Vote_Agent_Change,ethereum)

# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------- LIDO TESTNET DEPLOYMENT SCRIPTS ---------------------------------------------

deploy-lido-cross-chain-infra-test:
	$(call deploy_fn,Lido/CCC/Deploy_CCC,ethereum binance)

deploy-lido-ccip-bridge-adapters-test:
	$(call deploy_fn,Lido/Adapters/Deploy_CCIP,ethereum binance)

deploy-lido-lz-bridge-adapters-test:
	$(call deploy_fn,Lido/Adapters/Deploy_LZ,ethereum binance)

deploy-lido-hl-bridge-adapters-test:
	$(call deploy_fn,Lido/Adapters/Deploy_HL,ethereum binance)

deploy-lido-wormhole-adapters-test:
	$(call deploy_fn,Lido/Adapters/Deploy_Wormhole,ethereum binance)

deploy-lido-cross-chain-executor-test:
	$(call deploy_fn,Lido/CCC/Deploy_CCE,binance)

set-lido-ccf-approved-senders-test:
	$(call deploy_fn,Lido/CCC/Set_CCF_Approved_Senders,ethereum)

set-lido-ccf-sender-adapters-test:
	$(call deploy_fn,Lido/CCC/Set_CCF_Sender_Adapters,ethereum)

set-lido-ccr-receiver-adapters-test:
	$(call deploy_fn,Lido/CCC/Set_CCR_Receivers_Adapters,ethereum binance)

set-lido-ccr-confirmations-test:
	$(call deploy_fn,Lido/CCC/Set_CCR_Confirmations,ethereum binance)

fund-lido-crosschain-test:
	$(call deploy_fn,Lido/CCC/Fund_CCC,ethereum binance)

finalize-lido-testnet:
	$(call deploy_fn,Lido/CCC/Finalize,ethereum binance)

write-lido-json-addresses-test :; forge script scripts/Lido/WriteAddresses.s.sol:WriteDeployedAddresses -vvvv

vote-mock-update-test:
	$(call deploy_fn,Lido/e2e/Vote_Mock_Update,ethereum)

deploy-lido-bridge-adapters-test:
	make deploy-lido-ccip-bridge-adapters-test
	make deploy-lido-lz-bridge-adapters-test
	make deploy-lido-hl-bridge-adapters-test
	make deploy-lido-wormhole-adapters-test

deploy-lido-testnet:
	make deploy-lido-cross-chain-infra-test
	make deploy-lido-bridge-adapters-test
	make deploy-lido-cross-chain-executor-test
	make set-lido-ccf-approved-senders-test
	make set-lido-ccf-sender-adapters-test
	make set-lido-ccr-receiver-adapters-test
	make set-lido-ccr-confirmations-test
	make fund-lido-crosschain-test
	make finalize-lido-testnet
	make write-lido-json-addresses-test


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------- LIDO TEST SCRIPTS ----------------------------------------------------------

define deploy_local_single_fn
forge script \
 scripts/$(1).s.sol:$(if $(3),$(3),$(shell UP=$(2)_local; echo $${UP} | perl -nE 'say ucfirst')) \
 --rpc-url $(2)-local --legacy --broadcast --slow -vvvv $(BASE_KEY_LOCAL)

endef

define deploy_local_fn
 $(foreach network,$(2),$(call deploy_local_single_fn,$(1),$(network),$(3)))
endef

start-local-blockchain-forks:
	anvil --fork-url fork-source-mainnet --chain-id 1 -p 8545 & \
	anvil --fork-url fork-source-binance --chain-id 56 -p 8546 & \

stop-local-blockchain-forks:
	killall anvil || true

burn-deployer-nonce-local:
	$(call deploy_local_fn,Lido/helpers/Burn_Deployer_Nonce,ethereum)

deploy-lido-cross-chain-infra-local:
	$(call deploy_local_fn,Lido/CCC/Deploy_CCC,ethereum binance)

deploy-lido-ccip-bridge-adapters-local:
	$(call deploy_local_fn,Lido/Adapters/Deploy_CCIP,ethereum binance)

deploy-lido-lz-bridge-adapters-local:
	$(call deploy_local_fn,Lido/Adapters/Deploy_LZ,ethereum binance)

deploy-lido-hl-bridge-adapters-local:
	$(call deploy_local_fn,Lido/Adapters/Deploy_HL,ethereum binance)

deploy-lido-wormhole-adapters-local:
	$(call deploy_local_fn,Lido/Adapters/Deploy_Wormhole,ethereum binance)

deploy-lido-cross-chain-executor-local:
	$(call deploy_local_fn,Lido/CCC/Deploy_CCE,binance)

set-lido-ccf-approved-senders-local:
	$(call deploy_local_fn,Lido/CCC/Set_CCF_Approved_Senders,ethereum)

set-lido-ccf-sender-adapters-local:
	$(call deploy_local_fn,Lido/CCC/Set_CCF_Sender_Adapters,ethereum)

set-lido-ccr-receiver-adapters-local:
	$(call deploy_local_fn,Lido/CCC/Set_CCR_Receivers_Adapters,ethereum binance)

set-lido-ccr-confirmations-local:
	$(call deploy_local_fn,Lido/CCC/Set_CCR_Confirmations,ethereum binance)

fund-lido-crosschain-local:
	$(call deploy_local_fn,Lido/CCC/Fund_CCC,ethereum)

finalize-lido-local:
	$(call deploy_local_fn,Lido/CCC/Finalize,ethereum binance)

fund-deployer-local:
	$(call deploy_local_fn,Lido/helpers/Fund_Deployer,ethereum binance)

vote-lido-agent-change-local:
	$(call deploy_local_fn,Lido/e2e/Vote_Agent_Change,ethereum)

deploy-lido-bridge-adapters-local:
	make deploy-lido-ccip-bridge-adapters-local
	make deploy-lido-lz-bridge-adapters-local
	make deploy-lido-hl-bridge-adapters-local
	make deploy-lido-wormhole-adapters-local

restart-local-blockchain-forks:
	make stop-local-blockchain-forks
	make start-local-blockchain-forks

deploy-lido-local:
	make burn-deployer-nonce-local
	make deploy-lido-cross-chain-infra-local
	make deploy-lido-bridge-adapters-local
	make deploy-lido-cross-chain-executor-local
	make set-lido-ccf-approved-senders-local
	make set-lido-ccf-sender-adapters-local
	make set-lido-ccr-receiver-adapters-local
	make set-lido-ccr-confirmations-local
	make fund-lido-crosschain-local
	make finalize-lido-local

test-lido-state-local:
	ENV=local forge test -vv --match-path "tests/Lido/state/**/*.sol"

test-lido-integration-local:
	ENV=local forge test -vv --match-path "tests/Lido/integration/**/*.sol"

test-lido-local:
	make test-lido-state-local
	make test-lido-integration-local

# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------- LIDO HELPER SCRIPTS --------------------------------------------------------

deploy-lido-mock-destination:
	$(call deploy_fn,Lido/helpers/Deploy_Mock_Destination,binance)

test-lido-send-message:
	$(call deploy_fn,Lido/e2e/Send_Message,ethereum)

test-lido-send-message-to-executor:
	$(call deploy_fn,Lido/e2e/Send_Message_To_Executor,ethereum)

# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------- HELPER SCRIPTS ---------------------------------------------------------
remove-bridge-adapters:
	$(call deploy_fn,helpers/RemoveBridgeAdapters,ethereum polygon)

send-direct-message:
	$(call deploy_fn,helpers/Send_Direct_CCMessage,ethereum)

deploy_mock_destination:
	$(call deploy_fn,helpers/Deploy_Mock_destination,ethereum)

set-approved-ccf-senders:
	$(call deploy_fn,helpers/Set_Approved_Senders,ethereum)

send-message:
	@$(call deploy_fn,helpers/Testnet_ForwardMessage,ethereum,Testnet_ForwardMessage)

deploy_mock_ccc:
	$(call deploy_fn,helpers/mocks/Deploy_Mock_CCC,zkevm)

send-message-via-adapter:
	$(call deploy_fn,helpers/Send_Message_Via_Adapter,ethereum)

