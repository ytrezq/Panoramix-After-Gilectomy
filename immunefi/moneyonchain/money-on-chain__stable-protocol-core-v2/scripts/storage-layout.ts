import hre from "hardhat";

async function main() {
  //@ts-ignore
  await hre.storageLayout.export();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
