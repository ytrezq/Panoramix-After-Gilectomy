PATH := ~/.solc-select/artifacts/:~/.solc-select/artifacts/solc-0.8.24:$(PATH)
certora-nfat :; PATH=${PATH} certoraRun certora/NFATFacility.conf$(if $(rule), --rule $(rule),)$(if $(results), --wait_for_results all,)
