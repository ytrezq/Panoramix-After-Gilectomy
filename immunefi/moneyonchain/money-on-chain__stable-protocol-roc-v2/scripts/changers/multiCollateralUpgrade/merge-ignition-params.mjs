#!/usr/bin/env node
/**
 * Script to merge multiple JSON parameter files for FullMultiCollateralUpgrade deployment
 *
 * Usage:
 *   node scripts/merge-ignition-params.mjs <network> [output-file]
 *
 * Example:
 *   node scripts/changers/multiCollateralUpgrade/merge-ignition-params.mjs rskMainnet
 *   node scripts/changers/multiCollateralUpgrade/merge-ignition-params.mjs rskTestnet /tmp/params.json
 *
 * This script merges parameters from:
 *   - ignition/modules/changers/multiCollateralUpgrade/parameters/mocSwappers/<network>.json
 *   - ignition/modules/changers/multiCollateralUpgrade/parameters/feeFlow/<network>.json
 *   - ignition/modules/changers/multiCollateralUpgrade/parameters/docBucket/<network>.json
 *   - ignition/modules/changers/multiCollateralUpgrade/parameters/multiCollateralUpgrade/<network>.json
 *
 * Into a single JSON file that can be used with FullMultiCollateralUpgradeV2
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, "../../..");

const network = process.argv[2];
const outputFile = process.argv[3];

if (!network) {
  console.error(
    "Usage: node scripts/changers/multiCollateralUpgrade/merge-ignition-params.mjs <network> [output-file]",
  );
  console.error("Example: node scripts/changers/multiCollateralUpgrade/merge-ignition-params.mjs rskMainnet");
  process.exit(1);
}

const paramDirs = ["mocSwappers", "feeFlow", "docBucket", "multiCollateralUpgrade"];
const parametersBaseDir = path.join("ignition", "modules", "changers", "multiCollateralUpgrade", "parameters");

// Map of expected namespace keys in each JSON file
const namespaceKeys = {
  mocSwappers: ["MocSwappers"],
  feeFlow: ["FeeFlow"],
  docBucket: ["DocBucket"],
  multiCollateralUpgrade: ["MultiCollateralUpgrade"],
};

let merged = {};

for (const dir of paramDirs) {
  const filePath = path.join(
    rootDir,
    parametersBaseDir,
    dir,
    `${network}.json`,
  );

  if (!fs.existsSync(filePath)) {
    console.error(`Error: File not found: ${filePath}`);
    process.exit(1);
  }

  let content = JSON.parse(fs.readFileSync(filePath, "utf-8"));

  // If the content has a namespace wrapper, extract the inner content
  const possibleKeys = namespaceKeys[dir] || [];
  for (const key of possibleKeys) {
    if (content[key] && typeof content[key] === "object") {
      content = content[key];
      break;
    }
  }

  // Remove comment fields
  const filtered = Object.fromEntries(Object.entries(content).filter(([key]) => !key.startsWith("_")));

  const namespace = namespaceKeys[dir]?.[0] ?? dir;
  const namespaced = Object.fromEntries(
    Object.entries(filtered).map(([key, value]) => [`${namespace}.${key}`, value]),
  );

  merged = { ...merged, ...namespaced };
}

// Add metadata
const output = {
  _generatedBy: "merge-ignition-params.mjs",
  _network: network,
  _sources: paramDirs.map(d => path.join(parametersBaseDir, d, `${network}.json`)),
  // Parameters must be under the module namespace for Hardhat Ignition
  FullMultiCollateralUpgrade: merged,
};

const outputPath = outputFile || path.join(rootDir, "ignition", "modules", "changers", "multiCollateralUpgrade", "parameters", `full-${network}.json`);

fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));
console.log(`Merged parameters written to: ${outputPath}`);
console.log(`Total parameters: ${Object.keys(merged).length}`);
