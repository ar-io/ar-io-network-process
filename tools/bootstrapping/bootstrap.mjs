// bootstrap-generator.js
'use strict';

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Number of balances to generate. You can adjust this value.
const NUM_ENTRIES = 10_000;

// The minimum and maximum balance values.
const MIN_BALANCE = 10_000_000; // 10M
const MAX_BALANCE = 100_000_000_000_000; // 100T

// Determine the output format based on command-line arguments.
const args = process.argv.slice(2);
const outputFormat = args.includes('--json') ? 'json' : 'lua';

// Utility function to generate a random 43-character address.
function generateRandomAddress(length) {
  const charset =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let address = '';
  for (let i = 0; i < length; i++) {
    const randomIndex = Math.floor(Math.random() * charset.length);
    address += charset[randomIndex];
  }
  return address;
}

// Utility function to generate a random integer between min and max (inclusive).
function generateRandomBalance(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

if (outputFormat === 'lua') {
  // Build the Lua file content.
  let luaContent = '';
  for (let i = 0; i < NUM_ENTRIES; i++) {
    const address = generateRandomAddress(43);
    const balance = generateRandomBalance(MIN_BALANCE, MAX_BALANCE);
    // Each line follows the Lua syntax:
    // Balances["<43-character-address>"] = <balance>
    luaContent += `Balances["${address}"] = ${balance}\n`;
  }

  // Define the output file path.
  const outputPath = path.join(__dirname, 'bootstrap-balances.lua');

  // Write the Lua content to the file.
  fs.writeFile(outputPath, luaContent, 'utf8', (err) => {
    if (err) {
      console.error('Error writing to bootstrap-balances.lua:', err);
    } else {
      console.log(
        `Successfully wrote ${NUM_ENTRIES} entries to bootstrap-balances.lua`,
      );
    }
  });
} else if (outputFormat === 'json') {
  // Build the JSON object.
  const balances = {};
  for (let i = 0; i < NUM_ENTRIES; i++) {
    const address = generateRandomAddress(43);
    const balance = generateRandomBalance(MIN_BALANCE, MAX_BALANCE);
    balances[address] = balance;
  }

  // Convert the object to a JSON string with pretty-printing.
  const jsonContent = JSON.stringify(balances, null, 2);

  // Define the output file path.
  const outputPath = path.join(__dirname, 'bootstrap-balances.json');

  // Write the JSON content to the file.
  fs.writeFile(outputPath, jsonContent, 'utf8', (err) => {
    if (err) {
      console.error('Error writing to bootstrap-balances.json:', err);
    } else {
      console.log(
        `Successfully wrote ${NUM_ENTRIES} entries to bootstrap-balances.json`,
      );
    }
  });
}
