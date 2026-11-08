PATH := ~/.solc-select/artifacts/:~/.solc-select/artifacts/solc-0.8.21:~/.solc-select/artifacts/solc-0.5.12:$(PATH)
certora-stusds      :; PATH=${PATH} certoraRun certora/StUsds.conf$(if $(rule), --rule $(rule),)$(if $(results), --wait_for_results all,)
certora-rate-setter :; PATH=${PATH} certoraRun certora/StUsdsRateSetter.conf$(if $(rule), --rule $(rule),)$(if $(results), --wait_for_results all,)
certora-mom         :; PATH=${PATH} certoraRun certora/StUsdsMom.conf$(if $(rule), --rule $(rule),)$(if $(results), --wait_for_results all,)
