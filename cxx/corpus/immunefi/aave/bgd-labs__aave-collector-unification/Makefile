# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
update:; forge update

# Build & test
build  :; forge build --sizes --via-ir
test   :; forge test -vvv

# Deploy payloads
deploy-mainnet :;  forge script scripts/PayloadDeployment.s.sol:DeployMainnet --rpc-url mainnet --broadcast --legacy --ledger --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --verify --etherscan-api-key ${ETHERSCAN_API_KEY_MAINNET} -vvvv
deploy-polygon :;  forge script scripts/PayloadDeployment.s.sol:DeployPolygon --rpc-url polygon --broadcast --legacy --ledger --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --verify --etherscan-api-key ${ETHERSCAN_API_KEY_POLYGON} -vvvv
deploy-avalanche :;  forge script scripts/PayloadDeployment.s.sol:DeployAvalanche --rpc-url avalanche --broadcast --legacy --ledger --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --verify --etherscan-api-key ${ETHERSCAN_API_KEY_AVALANCHE} -vvvv
deploy-optimism :;  forge script scripts/PayloadDeployment.s.sol:DeployOptimism --rpc-url optimism --broadcast --legacy --ledger --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --verify --etherscan-api-key ${ETHERSCAN_API_KEY_OPTIMISM} -vvvv
deploy-arbitrum :;  forge script scripts/PayloadDeployment.s.sol:DeployArbitrum --rpc-url arbitrum --broadcast --legacy --ledger --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --verify --etherscan-api-key ${ETHERSCAN_API_KEY_ARBITRUM} -vvvv
deploy-fantom :;  forge script scripts/PayloadDeployment.s.sol:DeployFantom --rpc-url fantom --broadcast --legacy --ledger --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --verify --etherscan-api-key ${ETHERSCAN_API_KEY_FANTOM} -vvvv

deploy-v2-polygon :;  forge script scripts/PayloadV2Deployment.s.sol:DeployPolygon --rpc-url polygon --broadcast --legacy --ledger --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --verify --etherscan-api-key ${ETHERSCAN_API_KEY_POLYGON} -vvvv
deploy-v2-avalanche :;  forge script scripts/PayloadV2Deployment.s.sol:DeployAvalanche --rpc-url avalanche --broadcast --legacy --ledger --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --verify --etherscan-api-key ${ETHERSCAN_API_KEY_AVALANCHE} -vvvv

# utils
download :; cast etherscan-source --chain ${chain} -d etherscan/${chain}_${address} ${address}
git-diff :
	@mkdir -p diffs
	@printf '%s\n%s\n%s\n' "\`\`\`diff" "$$(git diff --no-index --diff-algorithm=patience --ignore-space-at-eol ${before} ${after})" "\`\`\`" > diffs/${out}.md
	
diff:
	@make git-diff before='./flattened/${chain}.sol' after='./flattened/NewCollector.sol' out=${chain}

# generate storage layouts
storage-layout:
	forge inspect ./flattened/${chain}.sol:Collector storage-layout --pretty > diffs/${chain}_layout.md