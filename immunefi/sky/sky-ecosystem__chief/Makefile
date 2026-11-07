PATH := ~/.solc-select/artifacts:~/.solc-select/artifacts/solc-0.8.21:$(PATH)
certora-chief            :; PATH=${PATH} certoraRun certora/Chief.conf --exclude_rule entryPoints storageAffected$(if $(rule), --rule $(rule),)$(if $(results), --wait_for_results all,)
certora-chief-parametric :; PATH=${PATH} certoraRun certora/Chief.conf --rule entryPoints storageAffected --optimistic_loop$(if $(results), --wait_for_results all,)
