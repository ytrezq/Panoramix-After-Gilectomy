# include .env file and export its env vars
-include .env

test-invariant :; forge test --match-path "test/**/invariant/**/*.sol" --show-progress
test-ui :; forge test --no-match-path "test/**/invariant/**/*.sol"

ifeq ($(VERIFIER),etherscan)
  VERIFIER_PARAMS := --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY)
endif

ifeq ($(VERIFIER),blockscout)
  VERIFIER_PARAMS := --verifier blockscout --verifier-url "$(VERIFIER_URL)"
endif

predeploy :; forge script Deploy --rpc-url $(RPC_URL)

deploy:; forge script Deploy \
  --rpc-url $(RPC_URL) \
  --retries 5 \
  --delay 7 \
  --broadcast \
  --verify \
  $(VERIFIER_PARAMS)

deployMerkl:; forge script DeployMerkl \
  --rpc-url $(RPC_URL) \
  --retries 6 \
  --delay 15 \
  --broadcast \
  --verify \
  $(VERIFIER_PARAMS)
