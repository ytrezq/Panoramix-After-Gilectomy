# Add bucket script

!!! DISCLAIMER: THIS IS ONLY FOR TESTING

This script, allows you to deploy and add a new RC20 bucket on the existent deployment for the given network.
It will deploy a new bucket from scratch based on the [configuration](./add-bucket.config.ts) provided, including the Collateral Token, queue and it will link all base bucket existent TPs on this new bucket.
Finally, it will deploy an execute a changer contract to add this new bucket to the multiCollateralGuard contract, if no `mocMultiCollateralGuard` config is provided, it will use network deployments default one.

WARNING!!
The new bucket and the new queue will be deployed with a InterimGovernor that allow the deployer to execute any protected function.

## Usage on localhost

- Start a node instance on localhost

`npx hardhat node`

- Remove any previous deployment

`rm -r ./deployments/localhost`

- Initialize a multiCollateral solution, for example using the provided deploy.

`npx hardhat deploy --network localhost --tags MocCARC20`

- Complete the [add-bucket.config.ts](./add-bucket.config.ts) file with desired values

- Run the [addBucket script](./add-rc20-bucket.ts)

`npx hardhat --network localhost run ./scripts/addBucket/add-rc20-bucket.ts`
