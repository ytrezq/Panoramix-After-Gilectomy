#!/usr/bin/env node

/**
 * Post-install script to fix package name conflicts
 *
 * All moc-main packages have the same internal name "main-sc-protocol-v2"
 * which causes Hardhat 3 to confuse them during import resolution.
 * This script renames each package to have a unique name.
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// List of packages to fix: [folder name, new package name]
const packagesToFix = [
  ["moc-main-stable", "moc-main-stable"],
  ["moc-main-latest", "moc-main-latest"],
];

for (const [folderName, newName] of packagesToFix) {
  const packagePath = path.join(__dirname, "..", "node_modules", folderName, "package.json");

  try {
    if (fs.existsSync(packagePath)) {
      const packageJson = JSON.parse(fs.readFileSync(packagePath, "utf8"));

      if (packageJson.name === "main-sc-protocol-v2") {
        packageJson.name = newName;
        fs.writeFileSync(packagePath, JSON.stringify(packageJson, null, 2) + "\n");
        console.log(`✓ Fixed ${folderName} package name conflict`);
      } else {
        console.log(`✓ ${folderName} package name already fixed`);
      }
    } else {
      console.log(`⚠ ${folderName} not found, skipping fix`);
    }
  } catch (error) {
    console.error(`Error fixing ${folderName} package name:`, error.message);
    process.exit(1);
  }
}
